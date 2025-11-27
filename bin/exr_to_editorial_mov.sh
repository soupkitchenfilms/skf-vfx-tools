#!/bin/bash
# =============================================================================
# exr_to_editorial_mov.sh - Convert ACES EXR sequences to editorial DNxHR MOV
# =============================================================================
#
# Pipeline: ACES2065-1 → ARRI LogC4 → Show LUT → Rec709 Gamma2.4 → DNxHR SQ
#
# Usage:
#     exr_to_editorial_mov.sh <input_pattern> <output.mov> [first_frame] [fps]
#
# Examples:
#     exr_to_editorial_mov.sh /path/to/shot.%04d.exr /path/to/shot.mov 1001 24
#     exr_to_editorial_mov.sh "/renders/ACD1000_SUP_CMP_v001.%04d.exr" "/editorial/ACD1000.mov"
#
# Requirements:
#     - OpenImageIO (oiiotool) with OCIO support
#     - FFmpeg with DNxHD encoder
#     - OCIO 2.3+ with built-in ACES configs
#
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# Show LUT path (LogC4 → Rec709 Gamma 2.4)
LUT_PATH="/Volumes/soupnas_02/Soupkitchen_Jobs/MNG/LUTS/v4_LUTs/v4_LUTs/post/mon_show_v4_logc4-r709g24_d65_33.cube"

# OCIO config (ACES 1.3 Studio config - includes camera input transforms)
export OCIO="ocio://studio-config-v2.1.0_aces-v1.3_ocio-v2.3"

# DNxHR profile (sq = LT quality, good for editorial)
DNXHR_PROFILE="dnxhr_sq"

# Intermediate format (uint16 PNG preserves quality, uint8 is faster)
INTERMEDIATE_DEPTH="uint16"

# -----------------------------------------------------------------------------
# Arguments
# -----------------------------------------------------------------------------

INPUT_PATTERN="$1"
OUTPUT="$2"
FPS="${3:-24}"

# IMPORTANT: Always start at frame 1000 (slate frame)
FIRST_FRAME=1000

if [ -z "$INPUT_PATTERN" ] || [ -z "$OUTPUT" ]; then
    echo "Usage: $0 <input_pattern> <output.mov> [fps]"
    echo ""
    echo "Arguments:"
    echo "  input_pattern  EXR sequence with %04d placeholder (e.g., shot.%04d.exr)"
    echo "  output.mov     Output MOV file path"
    echo "  fps            Frame rate (default: 24)"
    echo ""
    echo "NOTE: Always starts at frame 1000 (slate frame). Will error if missing."
    echo ""
    echo "Example:"
    echo "  $0 /renders/ACD1000_SUP_CMP_v001.%04d.exr /editorial/ACD1000.mov 24"
    exit 1
fi

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------

# Check dependencies
if ! command -v oiiotool &> /dev/null; then
    echo "ERROR: oiiotool not found. Install OpenImageIO."
    exit 1
fi

if ! command -v ffmpeg &> /dev/null; then
    echo "ERROR: ffmpeg not found."
    exit 1
fi

# Check LUT exists
if [ ! -f "$LUT_PATH" ]; then
    echo "ERROR: LUT not found at $LUT_PATH"
    exit 1
fi

# Check slate frame (1000) exists - REQUIRED
SLATE_EXR=$(printf "$INPUT_PATTERN" 1000)
if [ ! -f "$SLATE_EXR" ]; then
    echo "ERROR: Slate frame (1000) not found: $SLATE_EXR"
    echo ""
    echo "Editorial MOVs must include the slate frame."
    echo "Please ensure frame 1000 exists in the sequence."
    exit 1
fi
FIRST_EXR="$SLATE_EXR"

# Create output directory
OUTPUT_DIR=$(dirname "$OUTPUT")
mkdir -p "$OUTPUT_DIR"

# -----------------------------------------------------------------------------
# Extract Timecode
# -----------------------------------------------------------------------------

echo "=========================================="
echo "EXR to Editorial MOV Converter"
echo "=========================================="
echo ""
echo "Input:  $INPUT_PATTERN"
echo "Output: $OUTPUT"
echo "Frames: starting at $FIRST_FRAME @ ${FPS}fps"
echo "LUT:    $(basename "$LUT_PATH")"
echo ""

# Try to extract timecode from first EXR
TC=""
if command -v iinfo &> /dev/null; then
    TC=$(iinfo -v "$FIRST_EXR" 2>/dev/null | grep -i "timecode" | head -1 | awk '{print $NF}' | tr -d '"' || true)
fi

# If no timecode in EXR, calculate from frame number
if [ -z "$TC" ]; then
    # Calculate timecode from frame number
    HOURS=$((FIRST_FRAME / (FPS * 3600)))
    MINS=$(((FIRST_FRAME % (FPS * 3600)) / (FPS * 60)))
    SECS=$(((FIRST_FRAME % (FPS * 60)) / FPS))
    FRAMES=$((FIRST_FRAME % FPS))
    TC=$(printf "%02d:%02d:%02d:%02d" $HOURS $MINS $SECS $FRAMES)
    echo "Timecode: $TC (calculated from frame $FIRST_FRAME)"
else
    echo "Timecode: $TC (from EXR metadata)"
fi

# -----------------------------------------------------------------------------
# Create Temp Directory (use /mnt/caches for large intermediates)
# -----------------------------------------------------------------------------

# Global cache location - exists on all render machines including Deadline workers
TEMP_BASE="/mnt/caches/cache_ffmpeg"
mkdir -p "$TEMP_BASE"
TEMP_DIR=$(mktemp -d -p "$TEMP_BASE" editorial_encode_XXXXXX)
trap "rm -rf $TEMP_DIR" EXIT

echo ""
echo "Processing..."

# -----------------------------------------------------------------------------
# Step 1: Color Convert + LUT with oiiotool
# -----------------------------------------------------------------------------

echo "[1/2] Color pipeline: ACES2065-1 → LogC4 → LUT → Rec709..."

oiiotool "$INPUT_PATTERN" \
    --colorconvert "ACES2065-1" "ARRI LogC4" \
    --ociofiletransform "$LUT_PATH" \
    -d "$INTERMEDIATE_DEPTH" \
    -o "$TEMP_DIR/graded.%04d.png"

# Count frames
FRAME_COUNT=$(ls -1 "$TEMP_DIR"/graded.*.png 2>/dev/null | wc -l)
echo "      Processed $FRAME_COUNT frames"

# -----------------------------------------------------------------------------
# Step 2: Encode to DNxHR with FFmpeg
# -----------------------------------------------------------------------------

echo "[2/2] Encoding DNxHR SQ MOV..."

# Extract metadata for burn-ins
# Shot ID is first part before _SUP_ or _CMP_ (e.g., ACD1050 from ACD1050_SUP_CMP_v005)
FULL_NAME=$(basename "$INPUT_PATTERN" | sed 's/\.[^.]*$//' | sed 's/%[0-9]*d//')
FULL_NAME="${FULL_NAME%_}"  # Remove trailing underscore
SHOT_ID=$(echo "$FULL_NAME" | sed 's/_SUP.*//;s/_CMP.*//')
VIDEO_FILENAME=$(basename "$OUTPUT")
SUBMIT_DATE=$(date +%Y%m%d)
VENDOR_NAME="soup kitchen films"

# Build filter: scale, crop, add 0.5 opacity letterbox, then text burn-ins
# 1.9:1 in 1920x1080 = 1010px image, 35px letterbox top/bottom
LETTERBOX_H=35
FILTER="scale=1920:-1,crop=1920:1080"
# Add semi-transparent letterbox bars (50% opacity black)
FILTER="$FILTER,drawbox=x=0:y=0:w=1920:h=$LETTERBOX_H:color=black@0.5:t=fill"
FILTER="$FILTER,drawbox=x=0:y=ih-$LETTERBOX_H:w=1920:h=$LETTERBOX_H:color=black@0.5:t=fill"
# Text burn-ins
FILTER="$FILTER,drawtext=text='$VENDOR_NAME':fontsize=18:fontcolor=white:x=10:y=8"
FILTER="$FILTER,drawtext=text='$SHOT_ID':fontsize=18:fontcolor=white:x=(w-text_w)/2:y=8"
FILTER="$FILTER,drawtext=text='$SUBMIT_DATE':fontsize=18:fontcolor=white:x=w-text_w-10:y=8"
FILTER="$FILTER,drawtext=text='$VIDEO_FILENAME':fontsize=18:fontcolor=white:x=10:y=h-text_h-8"
FILTER="$FILTER,drawtext=text='%{frame_num}':start_number=$FIRST_FRAME:fontsize=18:fontcolor=white:x=w-text_w-10:y=h-text_h-8"

ffmpeg -y \
    -threads 0 \
    -framerate "$FPS" \
    -start_number "$FIRST_FRAME" \
    -i "$TEMP_DIR/graded.%04d.png" \
    -filter_threads 0 \
    -vf "$FILTER" \
    -c:v dnxhd \
    -threads 0 \
    -profile:v "$DNXHR_PROFILE" \
    -pix_fmt yuv422p \
    -timecode "$TC" \
    -color_primaries bt709 \
    -color_trc bt709 \
    -colorspace bt709 \
    -movflags +faststart \
    "$OUTPUT" \
    -loglevel warning -stats

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------

echo ""
if [ -f "$OUTPUT" ]; then
    SIZE=$(du -h "$OUTPUT" | cut -f1)
    echo "=========================================="
    echo "SUCCESS: $OUTPUT ($SIZE)"
    echo "=========================================="
else
    echo "ERROR: Output file not created"
    exit 1
fi
