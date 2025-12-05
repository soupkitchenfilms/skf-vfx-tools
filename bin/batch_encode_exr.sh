#!/bin/bash
# Batch encode all EXR sequences in directory
# Usage: batch_encode_exr.sh /path/to/renders/ [output_dir] [codec]

set -e

INPUT_DIR="$1"
OUTPUT_DIR="${2:-$INPUT_DIR/encoded}"
CODEC="${3:-h264}"

if [ -z "$INPUT_DIR" ]; then
    echo "Usage: $0 input_dir [output_dir] [codec]"
    echo "Codecs: h264 (default), prores"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "Scanning for EXR sequences in: $INPUT_DIR"

find "$INPUT_DIR" -name "*.exr" | \
    sed 's/\.[0-9]\{4,\}\.exr$//' | \
    sort -u | \
while read -r BASENAME; do
    SHOT_NAME=$(basename "$BASENAME")
    echo ""
    echo "Processing: $SHOT_NAME"

    PATTERN="${BASENAME}.%04d.exr"

    case "$CODEC" in
        prores)
            OUTPUT_FILE="$OUTPUT_DIR/${SHOT_NAME}.mov"
            /opt/vfx-platform-2024/bin/exr_to_prores_logc4.sh "$PATTERN" "$OUTPUT_FILE"
            ;;
        h264|*)
            OUTPUT_FILE="$OUTPUT_DIR/${SHOT_NAME}.mp4"
            /opt/vfx-platform-2024/bin/exr_to_h264_srgb.sh "$PATTERN" "$OUTPUT_FILE"
            ;;
    esac
done

echo ""
echo "Batch encoding complete!"
echo "Output: $OUTPUT_DIR"
