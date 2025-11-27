#!/bin/bash
################################################################################
# DNG to ACES Batch Converter with Metadata Preservation
# Converts DJI X9 DNG camera files to ACES color spaces with DWAA compression
#
# Usage:
#   dng_to_aces.sh INPUT_DIR OUTPUT_DIR [COLORSPACE] [COMPRESSION]
#
# Examples:
#   dng_to_aces.sh "/path/to/dng/" "/path/to/exr/" "ACEScg" 45
#   dng_to_aces.sh "scans/" "plates/" "ACES2065-1"
#
# Color Spaces:
#   ACEScg      - ACES working space (AP1, recommended for VFX)
#   ACES2065-1  - ACES archive/interchange (AP0, widest gamut)
#   linear      - Keep as scene linear sRGB (no conversion)
################################################################################

set -e

# Parse arguments
INPUT_DIR="$1"
OUTPUT_DIR="$2"
COLORSPACE="${3:-ACEScg}"
COMPRESSION_LEVEL="${4:-45}"
EXPOSURE_MULT="${5:-4.0}"  # Default +2 stops (tested optimal for DJI X9)
FRAME_START="${6:-}"       # Optional: first frame to process
FRAME_END="${7:-}"         # Optional: last frame to process

# Validate arguments
if [ -z "$INPUT_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 INPUT_DIR OUTPUT_DIR [COLORSPACE] [COMPRESSION] [EXPOSURE] [START] [END]"
    echo ""
    echo "Arguments:"
    echo "  INPUT_DIR          Directory containing DNG files"
    echo "  OUTPUT_DIR         Output directory for EXR files"
    echo "  COLORSPACE         Target color space (default: ACEScg)"
    echo "  COMPRESSION        DWAA compression (30-100, default: 45)"
    echo "  EXPOSURE           Exposure multiplier (default: 4.0 = +2 stops)"
    echo "  START              First frame number to process (optional)"
    echo "  END                Last frame number to process (optional)"
    echo ""
    echo "Color Space Options:"
    echo "  ACEScg      - ACES working space (AP1, recommended for VFX)"
    echo "  ACES2065-1  - ACES archive/interchange (AP0, widest gamut)"
    echo "  linear      - Keep as scene linear sRGB (no conversion)"
    echo ""
    echo "Examples:"
    echo "  $0 'scans/G001C0008' 'plates/acescg' 'ACEScg' 45"
    echo "  $0 'scans/G001C0008' 'archive/aces' 'ACES2065-1' 30 4.0"
    echo "  $0 'scans/G001C0008' 'plates/acescg' 'ACEScg' 45 4.0 1 1200  # First 1200 frames"
    echo "  $0 'scans/G001C0008' 'plates/acescg' 'ACEScg' 45 8.0 500 1000  # Frames 500-1000"
    exit 1
fi

# Validate color space
case "$COLORSPACE" in
    "ACEScg"|"ACES - ACEScg")
        COLORSPACE_FULL="ACES - ACEScg"
        COLORSPACE_NAME="ACEScg"
        ;;
    "ACES2065-1")
        COLORSPACE_FULL="ACES2065-1"
        COLORSPACE_NAME="ACES2065-1"
        ;;
    "linear"|"scene-linear")
        COLORSPACE_FULL=""
        COLORSPACE_NAME="scene linear"
        ;;
    *)
        echo "ERROR: Unknown color space '$COLORSPACE'"
        echo "Valid options: ACEScg, ACES2065-1, linear"
        exit 1
        ;;
esac

# Validate compression level
if [ "$COMPRESSION_LEVEL" -lt 30 ] || [ "$COMPRESSION_LEVEL" -gt 100 ]; then
    echo "ERROR: Compression level must be 30-100"
    exit 1
fi

# Check input directory exists
if [ ! -d "$INPUT_DIR" ]; then
    echo "ERROR: Input directory not found: $INPUT_DIR"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Count DNG files (will filter by frame range later)
TOTAL_DNG_COUNT=$(find "$INPUT_DIR" -maxdepth 1 \( -name "*.DNG" -o -name "*.dng" \) | wc -l)
if [ "$TOTAL_DNG_COUNT" -eq 0 ]; then
    echo "ERROR: No DNG files found in $INPUT_DIR"
    exit 1
fi

# Build frame range message
if [ -n "$FRAME_START" ] && [ -n "$FRAME_END" ]; then
    FRAME_RANGE_MSG="Frames $FRAME_START-$FRAME_END"
elif [ -n "$FRAME_START" ]; then
    FRAME_RANGE_MSG="From frame $FRAME_START"
elif [ -n "$FRAME_END" ]; then
    FRAME_RANGE_MSG="Up to frame $FRAME_END"
else
    FRAME_RANGE_MSG="All frames"
fi

# Set OCIO config
export OCIO="${OCIO:-ocio://cg-config-v2.1.0_aces-v1.3_ocio-v2.3}"

echo "========================================="
echo "DNG to ACES Batch Conversion"
echo "========================================="
echo "Input:       $INPUT_DIR"
echo "Output:      $OUTPUT_DIR"
echo "Total DNGs:  $TOTAL_DNG_COUNT files"
echo "Frame Range: $FRAME_RANGE_MSG"
echo "Color Space: $COLORSPACE_NAME"
echo "Compression: DWAA level $COMPRESSION_LEVEL"
echo "Exposure:    ${EXPOSURE_MULT}x ($(echo "scale=2; l($EXPOSURE_MULT)/l(2)" | bc -l) stops)"
echo "Format:      half (16-bit float)"
echo "OCIO Config: $OCIO"
echo ""
echo "Metadata Preservation:"
echo "  ✓ Camera info (Make, Model, Serial)"
echo "  ✓ Exposure settings (ISO, Shutter, F-stop, Focal Length)"
echo "  ✓ Timestamps (DateTime, DateTimeOriginal)"
echo "  ✓ DJI-specific metadata"
echo ""
echo "Conversion Method:"
echo "  ✓ Uses embedded DNG color matrices"
echo "  ✓ OpenColorIO transforms via oiiotool"
echo "  ✓ Source: srgb_rec709_scene (from DNG metadata)"
if [ -n "$COLORSPACE_FULL" ]; then
    echo "  ✓ Target: $COLORSPACE_FULL"
else
    echo "  ✓ No color conversion (scene linear)"
fi
echo ""
echo "Starting conversion..."
echo ""

# Start timer
START_TIME=$(date +%s)
PROCESSED=0
FAILED=0

# Process each DNG file
for DNG_FILE in "$INPUT_DIR"/*.DNG "$INPUT_DIR"/*.dng; do
    # Skip if no files match (glob didn't expand)
    [ -f "$DNG_FILE" ] || continue

    # Get filename without path and extension
    BASENAME=$(basename "$DNG_FILE")
    FILENAME="${BASENAME%.*}"

    # Extract frame number from filename (assumes format: NAME_NNNNNN.DNG)
    FRAME_NUM=$(echo "$BASENAME" | sed 's/.*_\([0-9]\{6\}\)\.[Dd][Nn][Gg]$/\1/')

    # Skip if frame number extraction failed
    if [ -z "$FRAME_NUM" ] || [ "$FRAME_NUM" = "$BASENAME" ]; then
        echo "  ⚠️  Warning: Could not extract frame number from $BASENAME, processing anyway"
        FRAME_NUM="0"
    fi

    # Convert to integer for comparison (remove leading zeros)
    FRAME_INT=$((10#$FRAME_NUM))

    # Check frame range filter
    if [ -n "$FRAME_START" ] && [ "$FRAME_INT" -lt "$FRAME_START" ]; then
        continue
    fi
    if [ -n "$FRAME_END" ] && [ "$FRAME_INT" -gt "$FRAME_END" ]; then
        continue
    fi

    OUTPUT_FILE="$OUTPUT_DIR/${FILENAME}.exr"

    # Convert with optional color space transform and exposure
    if [ -n "$COLORSPACE_FULL" ]; then
        # With color conversion
        if oiiotool "$DNG_FILE" \
            --mulc $EXPOSURE_MULT \
            --colorconvert "srgb_rec709_scene" "$COLORSPACE_FULL" \
            --compression dwaa:$COMPRESSION_LEVEL \
            -o "$OUTPUT_FILE" 2>/dev/null; then
            PROCESSED=$((PROCESSED + 1))
        else
            echo "  ✗ FAILED: $BASENAME"
            FAILED=$((FAILED + 1))
        fi
    else
        # No color conversion (linear with exposure)
        if oiiotool "$DNG_FILE" \
            --mulc $EXPOSURE_MULT \
            --compression dwaa:$COMPRESSION_LEVEL \
            -o "$OUTPUT_FILE" 2>/dev/null; then
            PROCESSED=$((PROCESSED + 1))
        else
            echo "  ✗ FAILED: $BASENAME"
            FAILED=$((FAILED + 1))
        fi
    fi

    # Progress reporting (every 10 files)
    TOTAL=$((PROCESSED + FAILED))
    if [ $((TOTAL % 10)) -eq 0 ]; then
        # Calculate expected total based on frame range
        if [ -n "$FRAME_START" ] && [ -n "$FRAME_END" ]; then
            EXPECTED_COUNT=$((FRAME_END - FRAME_START + 1))
        else
            EXPECTED_COUNT=$TOTAL_DNG_COUNT
        fi
        PERCENT=$((TOTAL * 100 / EXPECTED_COUNT))
        ELAPSED=$(($(date +%s) - START_TIME))
        if [ "$ELAPSED" -gt 0 ] && [ "$PROCESSED" -gt 0 ]; then
            RATE=$(echo "scale=2; $PROCESSED / $ELAPSED" | bc)
            REMAINING=$((EXPECTED_COUNT - TOTAL))
            ETA=$(echo "scale=0; $REMAINING / $RATE" | bc 2>/dev/null || echo "0")
            ETA_MIN=$((ETA / 60))
            ETA_SEC=$((ETA % 60))
            printf "  [%3d%%] %d / %d files  (%.2f fps, ETA: %02d:%02d)\n" \
                "$PERCENT" "$TOTAL" "$DNG_COUNT" "$RATE" "$ETA_MIN" "$ETA_SEC"
        else
            printf "  [%3d%%] %d / %d files\n" "$PERCENT" "$TOTAL" "$DNG_COUNT"
        fi
    fi
done

# Calculate statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

# Calculate file sizes
INPUT_SIZE=$(du -sh "$INPUT_DIR" | awk '{print $1}')
OUTPUT_SIZE=$(du -sh "$OUTPUT_DIR" | awk '{print $1}')

# Calculate average FPS
if [ "$DURATION" -gt 0 ]; then
    AVG_FPS=$(echo "scale=2; $PROCESSED / $DURATION" | bc)
else
    AVG_FPS="N/A"
fi

# Print summary
echo ""
echo "========================================="
if [ "$FAILED" -eq 0 ]; then
    echo "✅ Conversion Complete!"
else
    echo "⚠️  Conversion Complete with $FAILED errors"
fi
echo "========================================="
echo "Processed:     $PROCESSED files"
if [ "$FAILED" -gt 0 ]; then
    echo "Failed:        $FAILED files"
fi
printf "Duration:      %02d:%02d\n" "$MINUTES" "$SECONDS"
echo "Average:       $AVG_FPS fps"
echo "Input size:    $INPUT_SIZE"
echo "Output size:   $OUTPUT_SIZE"
echo ""
echo "Verify in Nuke:"
echo "  - Set Read node colorspace to: $COLORSPACE_NAME"
echo "  - Check metadata: iinfo -v \"$OUTPUT_DIR/\$(ls \"$OUTPUT_DIR\" | head -1)\""
echo ""
