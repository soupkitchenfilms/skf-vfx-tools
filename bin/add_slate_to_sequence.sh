#!/bin/bash
################################################################################
# Add Slate Information to EXR Sequence
# Production-ready script for adding shot metadata overlays
#
# Usage:
#   add_slate_to_sequence.sh INPUT_PATTERN OUTPUT_PATTERN SHOT_NAME [ARTIST]
#
# Examples:
#   add_slate_to_sequence.sh "render/shot.%04d.exr" "slated/shot.%04d.exr" "ACD1160_v014" "TobyA"
#   add_slate_to_sequence.sh "comp/*.exr" "review/*.png" "ORC4040_v003"
################################################################################

set -e

# Parse arguments
INPUT_PATTERN="$1"
OUTPUT_PATTERN="$2"
SHOT_NAME="${3:-SHOT}"
ARTIST="${4:-Pipeline}"
DATE=$(date '+%Y-%m-%d %H:%M')

# Validate arguments
if [ -z "$INPUT_PATTERN" ] || [ -z "$OUTPUT_PATTERN" ]; then
    echo "Usage: $0 INPUT_PATTERN OUTPUT_PATTERN SHOT_NAME [ARTIST]"
    echo ""
    echo "Examples:"
    echo "  $0 'render/shot.%04d.exr' 'slated/shot.%04d.exr' 'ACD1160_v014' 'TobyA'"
    echo "  $0 'comp/*.exr' 'review/*.png' 'ORC4040_v003'"
    exit 1
fi

# Set OCIO config
export OCIO="${OCIO:-ocio://cg-config-v2.1.0_aces-v1.3_ocio-v2.3}"

# Check if input uses frame pattern
if [[ "$INPUT_PATTERN" == *"%"* ]]; then
    # Frame sequence processing
    echo "Processing frame sequence..."
    echo "  Input: $INPUT_PATTERN"
    echo "  Output: $OUTPUT_PATTERN"
    echo "  Shot: $SHOT_NAME"
    echo "  Artist: $ARTIST"
    echo ""

    # Auto-detect frame range from first matching file
    FIRST_FILE=$(ls $(echo "$INPUT_PATTERN" | sed 's/%04d/*/g') 2>/dev/null | head -1)
    if [ -z "$FIRST_FILE" ]; then
        echo "ERROR: No files match pattern: $INPUT_PATTERN"
        exit 1
    fi

    # Extract frame numbers from filenames
    START_FRAME=$(ls $(echo "$INPUT_PATTERN" | sed 's/%04d/*/g') 2>/dev/null | \
        sed 's/.*\.\([0-9]\{4\}\)\.exr$/\1/' | sort -n | head -1)
    END_FRAME=$(ls $(echo "$INPUT_PATTERN" | sed 's/%04d/*/g') 2>/dev/null | \
        sed 's/.*\.\([0-9]\{4\}\)\.exr$/\1/' | sort -n | tail -1)

    FRAME_COUNT=$((10#$END_FRAME - 10#$START_FRAME + 1))
    echo "  Detected frames: $START_FRAME - $END_FRAME ($FRAME_COUNT frames)"
    echo ""

    # Process each frame
    for ((frame=10#$START_FRAME; frame<=10#$END_FRAME; frame++)); do
        FRAME_NUM=$(printf "%04d" $frame)
        INPUT_FILE=$(printf "$INPUT_PATTERN" $frame)
        OUTPUT_FILE=$(printf "$OUTPUT_PATTERN" $frame)

        # Create output directory if needed
        mkdir -p "$(dirname "$OUTPUT_FILE")"

        # Determine if we need color conversion
        if [[ "$OUTPUT_FILE" == *.png ]] || [[ "$OUTPUT_FILE" == *.jpg ]]; then
            COLORCONVERT="--colorconvert \"ACES - ACEScg\" \"sRGB - Display\""
        else
            COLORCONVERT=""
        fi

        # Process frame with text overlays
        eval "oiiotool \"$INPUT_FILE\" \
            --text:x=50:y=50:size=60:color=1,1,1 \"$SHOT_NAME\" \
            --text:x=50:y=130:size=40:color=0.8,0.8,0.8 \"Artist: $ARTIST\" \
            --text:x=50:y=180:size=36:color=0.7,0.7,0.7 \"$DATE\" \
            --text:x=1700:y=50:size=48:color=1,1,0 \"$FRAME_NUM\" \
            $COLORCONVERT \
            -o \"$OUTPUT_FILE\""

        if [ $((frame % 10)) -eq 0 ]; then
            echo "  Processed frame $FRAME_NUM..."
        fi
    done

    echo ""
    echo "✅ Processed $FRAME_COUNT frames"

else
    # Single file or glob pattern
    echo "Processing files matching: $INPUT_PATTERN"
    echo ""

    COUNT=0
    for INPUT_FILE in $INPUT_PATTERN; do
        if [ ! -f "$INPUT_FILE" ]; then
            continue
        fi

        # Generate output filename
        if [[ "$OUTPUT_PATTERN" == *"*"* ]]; then
            # Pattern with wildcard
            OUTPUT_FILE="${OUTPUT_PATTERN/\*/$INPUT_FILE}"
        else
            # Use output pattern directly
            BASENAME=$(basename "$INPUT_FILE" .exr)
            OUTPUT_FILE=$(dirname "$OUTPUT_PATTERN")/"$BASENAME.${OUTPUT_PATTERN##*.}"
        fi

        mkdir -p "$(dirname "$OUTPUT_FILE")"

        # Determine color conversion
        if [[ "$OUTPUT_FILE" == *.png ]] || [[ "$OUTPUT_FILE" == *.jpg ]]; then
            COLORCONVERT="--colorconvert \"ACES - ACEScg\" \"sRGB - Display\""
        else
            COLORCONVERT=""
        fi

        # Process file
        eval "oiiotool \"$INPUT_FILE\" \
            --text:x=50:y=50:size=60:color=1,1,1 \"$SHOT_NAME\" \
            --text:x=50:y=130:size=40:color=0.8,0.8,0.8 \"Artist: $ARTIST\" \
            --text:x=50:y=180:size=36:color=0.7,0.7,0.7 \"$DATE\" \
            $COLORCONVERT \
            -o \"$OUTPUT_FILE\""

        COUNT=$((COUNT + 1))
        echo "  Processed: $(basename "$INPUT_FILE") → $(basename "$OUTPUT_FILE")"
    done

    echo ""
    echo "✅ Processed $COUNT files"
fi

echo ""
echo "Output saved to: $OUTPUT_PATTERN"
