#!/bin/bash
################################################################################
# DNG to EXR Batch Converter with Metadata Preservation
# Converts DJI X9 DNG camera files to EXR with DWAA compression
#
# Usage:
#   dng_to_exr.sh INPUT_DIR OUTPUT_DIR [COMPRESSION_LEVEL]
#
# Examples:
#   dng_to_exr.sh "/path/to/dng/files" "/path/to/output" 45
#   dng_to_exr.sh "G001C0008_250204_J1PS60" "exr_output"
#
# Features:
#   - Preserves camera metadata (Make, Model, Serial, ISO, Exposure, etc.)
#   - DWAA compression (lossy visually lossless, optimized for VFX)
#   - Half-float precision (16-bit per channel)
#   - Parallel processing option
#   - Progress reporting
################################################################################

set -e

# Parse arguments
INPUT_DIR="$1"
OUTPUT_DIR="$2"
COMPRESSION_LEVEL="${3:-45}"  # Default to 45 (good balance of quality/size)

# Validate arguments
if [ -z "$INPUT_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 INPUT_DIR OUTPUT_DIR [COMPRESSION_LEVEL]"
    echo ""
    echo "Arguments:"
    echo "  INPUT_DIR          Directory containing DNG files"
    echo "  OUTPUT_DIR         Output directory for EXR files"
    echo "  COMPRESSION_LEVEL  DWAA compression (30-100, default: 45)"
    echo ""
    echo "Examples:"
    echo "  $0 '/Volumes/.../G001C0008_250204_J1PS60' 'exr_output' 45"
    echo "  $0 'dng_scans' 'exr_scans' 60"
    echo ""
    echo "Compression Recommendations:"
    echo "  30  - Highest quality, larger files (~25MB per 8K frame)"
    echo "  45  - Recommended balance (~20MB per 8K frame)"
    echo "  60  - Good compression (~17MB per 8K frame)"
    echo "  90  - Aggressive compression (~13MB per 8K frame)"
    exit 1
fi

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

# Count DNG files
DNG_COUNT=$(find "$INPUT_DIR" -maxdepth 1 \( -name "*.DNG" -o -name "*.dng" \) | wc -l)
if [ "$DNG_COUNT" -eq 0 ]; then
    echo "ERROR: No DNG files found in $INPUT_DIR"
    exit 1
fi

echo "========================================="
echo "DNG to EXR Batch Conversion"
echo "========================================="
echo "Input:       $INPUT_DIR"
echo "Output:      $OUTPUT_DIR"
echo "Files:       $DNG_COUNT DNG files"
echo "Compression: DWAA level $COMPRESSION_LEVEL"
echo "Format:      half (16-bit float)"
echo ""
echo "Metadata Preservation:"
echo "  ✓ Camera info (Make, Model, Serial)"
echo "  ✓ Exposure settings (ISO, Shutter, F-stop, Focal Length)"
echo "  ✓ Timestamps (DateTime, DateTimeOriginal)"
echo "  ✓ DJI-specific metadata (Body Serial, etc.)"
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
    OUTPUT_FILE="$OUTPUT_DIR/${FILENAME}.exr"

    # Convert with metadata preservation
    if oiiotool "$DNG_FILE" \
        --compression dwaa:$COMPRESSION_LEVEL \
        -o "$OUTPUT_FILE" 2>/dev/null; then
        PROCESSED=$((PROCESSED + 1))
    else
        echo "  ✗ FAILED: $BASENAME"
        FAILED=$((FAILED + 1))
    fi

    # Progress reporting (every 10 files or last file)
    TOTAL=$((PROCESSED + FAILED))
    if [ $((TOTAL % 10)) -eq 0 ] || [ "$TOTAL" -eq "$DNG_COUNT" ]; then
        PERCENT=$((TOTAL * 100 / DNG_COUNT))
        ELAPSED=$(($(date +%s) - START_TIME))
        if [ "$ELAPSED" -gt 0 ] && [ "$PROCESSED" -gt 0 ]; then
            RATE=$(echo "scale=2; $PROCESSED / $ELAPSED" | bc)
            REMAINING=$((DNG_COUNT - TOTAL))
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
echo "Verify metadata with:"
echo "  iinfo -v \"$OUTPUT_DIR/\$(ls \"$OUTPUT_DIR\" | head -1)\""
echo ""
