#!/bin/bash
# ACES Linear EXR -> sRGB H.264 (Client Review)
# Usage: exr_to_h264_srgb.sh input.%04d.exr output.mp4 [fps]

set -e

INPUT_PATTERN="$1"
OUTPUT="$2"
FPS="${3:-24}"

if [ -z "$INPUT_PATTERN" ] || [ -z "$OUTPUT" ]; then
    echo "Usage: $0 input_pattern.%04d.exr output.mp4 [fps]"
    echo "Example: $0 render/shot.%04d.exr client_review.mp4 24"
    exit 1
fi

# Use built-in ACES 1.3 config
export OCIO="ocio://cg-config-v2.1.0_aces-v1.3_ocio-v2.3"

# Temp directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "Converting colorspace: ACEScg -> sRGB (OCIO)..."

# Step 1: Color convert with oiiotool
/usr/local/bin/oiiotool "$INPUT_PATTERN" \
    --colorconvert "ACES - ACEScg" "sRGB - Display" \
    --resize 1920x0 \
    --dither \
    -d uint8 \
    -o "$TEMP_DIR/intermediate.%04d.png"

echo "Encoding to H.264..."

# Step 2: Encode with ffmpeg
ffmpeg -y \
    -framerate "$FPS" \
    -i "$TEMP_DIR/intermediate.%04d.png" \
    -c:v libx264 \
    -preset slow \
    -crf 18 \
    -pix_fmt yuv420p \
    -colorspace bt709 \
    -color_primaries bt709 \
    -color_trc iec61966-2-1 \
    -movflags +faststart \
    "$OUTPUT"

echo "Done: $OUTPUT"
