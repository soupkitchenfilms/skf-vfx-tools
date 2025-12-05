#!/bin/bash
# ACES Linear EXR -> LogC4 ProRes (Editorial Delivery)
# Usage: exr_to_prores_logc4.sh input.%04d.exr output.mov [fps]

set -e

INPUT_PATTERN="$1"
OUTPUT="$2"
FPS="${3:-24}"

if [ -z "$INPUT_PATTERN" ] || [ -z "$OUTPUT" ]; then
    echo "Usage: $0 input_pattern.%04d.exr output.mov [fps]"
    exit 1
fi

export OCIO="ocio://studio-config-v2.1.0_aces-v1.3_ocio-v2.3"

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "Converting: ACES Linear -> ARRI LogC4 (OCIO)..."

/usr/local/bin/oiiotool "$INPUT_PATTERN" \
    --colorconvert "ACES - ACES2065-1" "ARRI LogC4" \
    --resize 1920x1080 \
    -d uint16 \
    -o "$TEMP_DIR/logc4.%04d.png"

echo "Encoding to ProRes 422 HQ..."

ffmpeg -y \
    -framerate "$FPS" \
    -i "$TEMP_DIR/logc4.%04d.png" \
    -c:v prores_ks \
    -profile:v 3 \
    -pix_fmt yuv422p10le \
    -vendor apl0 \
    -movflags +faststart \
    "$OUTPUT"

echo "Done: $OUTPUT"
