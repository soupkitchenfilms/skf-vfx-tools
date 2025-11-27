#!/bin/bash
################################################################################
# VFX Reference Platform 2024 - Master Build Script
# Soup Kitchen Films Pipeline Upgrade
#
# This script builds all VFX Platform 2024 components from source in the
# correct dependency order.
#
# Build Order (revised per user request):
#   1. OpenColorIO 2.3.x (Foundation for color management)
#   2. OpenImageIO 3.x (Image processing with OCIO support)
#   3. RAWtoACES (Camera RAW to ACES conversion)
#   4. xstudio (Review player - OPTIONAL, can skip with --skip-xstudio)
#   5. Encoding scripts (Production workflow scripts)
#
# Usage:
#   sudo bash vfx_platform_2024_master_build.sh [--skip-xstudio]
#
# Requirements:
#   - Rocky Linux 9.x
#   - Root/sudo access
#   - ~50GB free disk space
#   - Internet connection
#
# Estimated Time: 16-20 hours (without xstudio: 12-15 hours)
#
# Author: Claude (Anthropic)
# Date: 2025-11-22
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

################################################################################
# Configuration
################################################################################

BUILD_ROOT="/opt/vfx-platform-2024"
LOG_DIR="$BUILD_ROOT/logs"
BIN_DIR="$BUILD_ROOT/bin"
CONFIG_DIR="$BUILD_ROOT/configs"
REPOS_DIR="$BUILD_ROOT/repos"

# OCIO config for encoding scripts
OCIO_CONFIG="ocio://cg-config-v2.1.0_aces-v1.3_ocio-v2.3"

# Parse arguments
SKIP_XSTUDIO=0
if [ "${1:-}" = "--skip-xstudio" ]; then
    SKIP_XSTUDIO=1
    echo "⏭️  Will skip xstudio build (optional component)"
fi

################################################################################
# Helper Functions
################################################################################

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_DIR/master_build.log"
}

error_exit() {
    echo "❌ ERROR: $1" | tee -a "$LOG_DIR/master_build.log"
    exit 1
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        error_exit "Required command not found: $1"
    fi
}

time_phase() {
    local start_time=$1
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local hours=$((duration / 3600))
    local minutes=$(( (duration % 3600) / 60 ))
    local seconds=$((duration % 60))
    printf "%02d:%02d:%02d" $hours $minutes $seconds
}

################################################################################
# Prerequisite Checks
################################################################################

check_prerequisites() {
    log "🔍 Checking prerequisites..."

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        error_exit "This script must be run as root (use sudo)"
    fi

    # Check OS
    if [ ! -f /etc/rocky-release ]; then
        error_exit "This script is designed for Rocky Linux"
    fi
    log "  ✅ OS: $(cat /etc/rocky-release)"

    # Check disk space (need at least 30GB)
    local available=$(df / | awk 'NR==2 {print $4}')
    local needed=$((30 * 1024 * 1024))  # 30GB in KB
    if [ "$available" -lt "$needed" ]; then
        error_exit "Insufficient disk space. Need 30GB, have $(($available / 1024 / 1024))GB"
    fi
    log "  ✅ Disk space: $(($available / 1024 / 1024))GB available"

    # Check required commands (only those that should already exist)
    check_command git
    check_command gcc
    check_command g++

    # cmake and ninja-build will be installed in Phase 1

    log "✅ Prerequisites check passed"
}

################################################################################
# Directory Setup
################################################################################

setup_directories() {
    log "📁 Setting up build directories..."

    # Create main directories
    mkdir -p "$BUILD_ROOT"
    mkdir -p "$LOG_DIR"
    mkdir -p "$BIN_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$REPOS_DIR"

    # Set ownership to souprender (assume this is the build user)
    if id "souprender" &>/dev/null; then
        chown -R souprender:souprender "$BUILD_ROOT"
        log "  ✅ Set ownership to souprender"
    fi

    log "✅ Directory structure created"
}

################################################################################
# Phase 1: Install Base Dependencies
################################################################################

install_base_dependencies() {
    log "📦 Phase 1: Installing base dependencies..."
    local start_time=$(date +%s)

    # Enable repos
    log "  Enabling EPEL and CRB repositories..."
    dnf install -y epel-release
    dnf config-manager --set-enabled crb

    # Development tools
    log "  Installing Development Tools..."
    dnf groupinstall -y "Development Tools"

    # Build tools
    log "  Installing build tools..."
    dnf install -y cmake ninja-build git

    # Base libraries
    log "  Installing base libraries..."
    dnf install -y \
        boost-devel \
        tbb-devel \
        libX11-devel \
        libXext-devel \
        qt6-qtbase-devel \
        python3-devel \
        python3-pip \
        zlib-devel \
        libjpeg-turbo \
        libjpeg-turbo-devel \
        turbojpeg \
        turbojpeg-devel \
        libpng-devel \
        libtiff-devel \
        libwebp-devel \
        openexr-devel \
        imath-devel \
        yaml-cpp-devel \
        expat-devel \
        LibRaw-devel \
        openjpeg2-devel \
        giflib-devel \
        pybind11-devel \
        fmt-devel

    # Install opencv-devel (for video codec support)
    # Use --nobest to allow compatible older versions if dependency issues exist
    log "  Installing opencv-devel..."
    dnf install -y --nobest opencv-devel || {
        log "  ⚠️  Using --skip-broken for opencv-devel..."
        dnf install -y --skip-broken opencv-devel
    }

    local duration=$(time_phase $start_time)
    log "✅ Phase 1 complete ($duration)"
}

################################################################################
# Phase 2: Build OpenColorIO 2.3.x
################################################################################

build_opencolorio() {
    log "🎨 Phase 2: Building OpenColorIO 2.3.x..."
    local start_time=$(date +%s)

    cd "$REPOS_DIR"

    # Clone if not exists
    if [ ! -d "OpenColorIO" ]; then
        log "  Cloning OpenColorIO..."
        git clone https://github.com/AcademySoftwareFoundation/OpenColorIO.git
    fi

    cd OpenColorIO
    git fetch --all
    git checkout RB-2.3

    # Clean previous build
    rm -rf build
    mkdir build
    cd build

    log "  Configuring with CMake..."
    cmake -G Ninja \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_BUILD_TYPE=Release \
        -DOCIO_BUILD_APPS=ON \
        -DOCIO_BUILD_PYTHON=ON \
        -DOCIO_BUILD_TESTS=OFF \
        -DOCIO_BUILD_GPU_TESTS=OFF \
        -DOCIO_INSTALL_EXT_PACKAGES=ALL \
        .. 2>&1 | tee "$LOG_DIR/ocio_configure.log"

    log "  Building OpenColorIO (this will take 2-3 hours)..."
    ninja -j$(nproc) 2>&1 | tee "$LOG_DIR/ocio_build.log"

    log "  Installing OpenColorIO..."
    ninja install 2>&1 | tee "$LOG_DIR/ocio_install.log"

    ldconfig

    # Verify installation (check binaries and libraries exist)
    if [ -x /usr/local/bin/ociocheck ] && [ -f /usr/local/lib64/libOpenColorIO.so.2.3.2 ]; then
        log "  ✅ OpenColorIO 2.3.2 installed successfully"
        log "     Binaries: /usr/local/bin/ocio*"
        log "     Libraries: /usr/local/lib64/libOpenColorIO.so.2.3.2"
    else
        error_exit "OpenColorIO installation verification failed"
    fi

    local duration=$(time_phase $start_time)
    log "✅ Phase 2 complete ($duration)"
}

################################################################################
# Phase 3: Build OpenImageIO 3.x
################################################################################

build_openimageio() {
    log "🖼️  Phase 3: Building OpenImageIO 3.x..."
    local start_time=$(date +%s)

    cd "$REPOS_DIR"

    # Clone if not exists
    if [ ! -d "OpenImageIO" ]; then
        log "  Cloning OpenImageIO..."
        git clone https://github.com/AcademySoftwareFoundation/OpenImageIO.git
    fi

    cd OpenImageIO
    git fetch --all

    # Find latest 3.x tag
    local latest_tag=$(git tag | grep '^v3\.' | sort -V | tail -1)
    log "  Using tag: $latest_tag"
    git checkout "$latest_tag"

    # Clean previous build
    rm -rf build
    mkdir build
    cd build

    log "  Configuring with CMake..."
    cmake -G Ninja \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_BUILD_TYPE=Release \
        -DUSE_PYTHON=ON \
        -DUSE_OPENCOLORIO=ON \
        -DOpenColorIO_ROOT=/usr/local \
        -DUSE_OPENCV=ON \
        -DUSE_LIBRAW=ON \
        -DUSE_OPENEXR=ON \
        -DUSE_FFMPEG=ON \
        -DBUILD_TESTING=OFF \
        .. 2>&1 | tee "$LOG_DIR/oiio_configure.log"

    log "  Building OpenImageIO (this will take 3-4 hours)..."
    ninja -j$(nproc) 2>&1 | tee "$LOG_DIR/oiio_build.log"

    log "  Installing OpenImageIO..."
    ninja install 2>&1 | tee "$LOG_DIR/oiio_install.log"

    ldconfig

    # Update library path for verification
    export LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    export PATH=/usr/local/bin:$PATH

    # Verify
    if /usr/local/bin/oiiotool --version &> /dev/null; then
        local version=$(/usr/local/bin/oiiotool --version 2>&1 | head -1)
        log "  ✅ Installed: $version"

        # Test OCIO integration
        if /usr/local/bin/oiiotool --help | grep -q colorconvert; then
            log "  ✅ OCIO integration verified"
        else
            error_exit "OCIO integration not found in oiiotool"
        fi
    else
        error_exit "OpenImageIO installation verification failed"
    fi

    local duration=$(time_phase $start_time)
    log "✅ Phase 3 complete ($duration)"
}

################################################################################
# Phase 4: Build RAWtoACES
################################################################################

build_rawtoaces() {
    log "📸 Phase 4: Building RAWtoACES..."
    local start_time=$(date +%s)

    cd "$REPOS_DIR"

    # Build dependencies first

    # 1. Ceres Solver
    log "  Building Ceres Solver..."
    if [ ! -d "ceres-solver" ]; then
        git clone https://github.com/ceres-solver/ceres-solver.git
    fi
    cd ceres-solver
    git pull
    rm -rf build
    mkdir build
    cd build
    cmake -G Ninja \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_BUILD_TYPE=Release \
        .. 2>&1 | tee "$LOG_DIR/ceres_configure.log"
    ninja -j$(nproc) 2>&1 | tee "$LOG_DIR/ceres_build.log"
    ninja install 2>&1 | tee "$LOG_DIR/ceres_install.log"
    ldconfig

    # 2. ACES Container
    cd "$REPOS_DIR"
    log "  Building ACES Container..."
    if [ ! -d "aces_container" ]; then
        git clone https://github.com/ampas/aces_container.git
    fi
    cd aces_container
    git pull
    rm -rf build
    mkdir build
    cd build
    cmake -G Ninja \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_BUILD_TYPE=Release \
        .. 2>&1 | tee "$LOG_DIR/aces_container_configure.log"
    ninja -j$(nproc) 2>&1 | tee "$LOG_DIR/aces_container_build.log"
    ninja install 2>&1 | tee "$LOG_DIR/aces_container_install.log"
    ldconfig

    # 3. RAWtoACES
    cd "$REPOS_DIR"
    log "  Building RAWtoACES..."
    if [ ! -d "rawtoaces" ]; then
        git clone https://github.com/AcademySoftwareFoundation/rawtoaces.git
    fi
    cd rawtoaces
    git pull
    rm -rf build
    mkdir build
    cd build
    cmake -G Ninja \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_BUILD_TYPE=Release \
        -DIlmbase_ROOT=/usr \
        -DLibRaw_ROOT=/usr \
        -DAcesContainer_ROOT=/usr/local \
        -DCeres_ROOT=/usr/local \
        .. 2>&1 | tee "$LOG_DIR/rawtoaces_configure.log"
    ninja -j$(nproc) 2>&1 | tee "$LOG_DIR/rawtoaces_build.log"
    ninja install 2>&1 | tee "$LOG_DIR/rawtoaces_install.log"
    ldconfig

    # Update library path for verification
    export LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    export PATH=/usr/local/bin:$PATH

    # Verify
    if /usr/local/bin/rawtoaces --help &> /dev/null; then
        log "  ✅ RAWtoACES installed successfully"
    else
        error_exit "RAWtoACES installation verification failed"
    fi

    local duration=$(time_phase $start_time)
    log "✅ Phase 4 complete ($duration)"
}

################################################################################
# Phase 5: Create Encoding Scripts
################################################################################

create_encoding_scripts() {
    log "🎬 Phase 5: Creating encoding scripts..."
    local start_time=$(date +%s)

    # Script 1: EXR to H.264 sRGB
    log "  Creating exr_to_h264_srgb.sh..."
    cat > "$BIN_DIR/exr_to_h264_srgb.sh" << 'SCRIPT_EOF'
#!/bin/bash
# ACES Linear EXR → sRGB H.264 (Client Review)
# Usage: exr_to_h264_srgb.sh input_pattern.####.exr output.mp4 [fps]

set -e

INPUT_PATTERN="$1"
OUTPUT="$2"
FPS="${3:-24}"

if [ -z "$INPUT_PATTERN" ] || [ -z "$OUTPUT" ]; then
    echo "Usage: $0 input_pattern.####.exr output.mp4 [fps]"
    echo "Example: $0 render/shot.%04d.exr client_review.mp4 24"
    exit 1
fi

# Set OCIO config (built-in ACES 1.3)
export OCIO="ocio://cg-config-v2.1.0_aces-v1.3_ocio-v2.3"

# Temp directory for intermediates
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "🎨 Converting colorspace: ACEScg → sRGB (OCIO)..."

# STEP 1: Color convert with oiiotool
oiiotool "$INPUT_PATTERN" \
    --colorconvert "ACES - ACEScg" "sRGB - Display" \
    --resize 1920x0 \
    --dither \
    -d uint16 \
    -o "$TEMP_DIR/intermediate.%04d.png"

echo "🎬 Encoding to H.264..."

# STEP 2: Encode with ffmpeg (no color conversion)
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

echo "✅ Encode complete: $OUTPUT"
SCRIPT_EOF

    # Script 2: EXR to ProRes LogC4
    log "  Creating exr_to_prores_logc4.sh..."
    cat > "$BIN_DIR/exr_to_prores_logc4.sh" << 'SCRIPT_EOF'
#!/bin/bash
# ACES Linear EXR → LogC4 ProRes (Editorial Delivery)
# Usage: exr_to_prores_logc4.sh input_pattern.####.exr output.mov [cdl.ccc] [lut.cube] [fps]

set -e

INPUT_PATTERN="$1"
OUTPUT="$2"
CDL_FILE="$3"
LUT_FILE="$4"
FPS="${5:-24}"

if [ -z "$INPUT_PATTERN" ] || [ -z "$OUTPUT" ]; then
    echo "Usage: $0 input_pattern.####.exr output.mov [cdl.ccc] [lut.cube] [fps]"
    echo "Example: $0 render/shot.%04d.exr editorial.mov grade.ccc look.cube 24"
    exit 1
fi

# Set OCIO config
export OCIO="ocio://studio-config-v2.1.0_aces-v1.3_ocio-v2.3"

# Temp directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "🎨 Converting: ACES Linear → LogC4 (OCIO)..."

# Build oiiotool command
OIIO_CMD="oiiotool '$INPUT_PATTERN'"
OIIO_CMD="$OIIO_CMD --colorconfig '$OCIO'"
OIIO_CMD="$OIIO_CMD --colorconvert 'ACES - ACES2065-1' 'ARRI - Curve - V3 LogC (EI800)'"

# Apply CDL if provided
if [ -n "$CDL_FILE" ]; then
    echo "📊 Applying CDL: $CDL_FILE"
    OIIO_CMD="$OIIO_CMD --ociofiletransform '$CDL_FILE'"
fi

# Apply LUT if provided
if [ -n "$LUT_FILE" ]; then
    echo "🎨 Applying LUT: $LUT_FILE"
    OIIO_CMD="$OIIO_CMD --ociofiletransform '$LUT_FILE'"
fi

# Complete command
OIIO_CMD="$OIIO_CMD --resize 1920x1080"
OIIO_CMD="$OIIO_CMD -o '$TEMP_DIR/logc4.%04d.exr'"

# Execute
eval $OIIO_CMD

echo "🎬 Encoding to ProRes 422 HQ..."

# Encode to ProRes
ffmpeg -y \
    -framerate "$FPS" \
    -i "$TEMP_DIR/logc4.%04d.exr" \
    -c:v prores_ks \
    -profile:v 3 \
    -pix_fmt yuv422p10le \
    -vendor apl0 \
    -movflags +faststart \
    "$OUTPUT"

echo "✅ Encode complete: $OUTPUT"
SCRIPT_EOF

    # Script 3: Batch encoder
    log "  Creating batch_encode_exr.sh..."
    cat > "$BIN_DIR/batch_encode_exr.sh" << 'SCRIPT_EOF'
#!/bin/bash
# Batch encode all EXR sequences in directory
# Usage: batch_encode_exr.sh /path/to/renders/ [output_dir] [codec]

set -e

INPUT_DIR="$1"
OUTPUT_DIR="${2:-$INPUT_DIR/encoded}"
CODEC="${3:-h264}"  # h264, prores

if [ -z "$INPUT_DIR" ]; then
    echo "Usage: $0 input_dir [output_dir] [codec]"
    echo "Codecs: h264 (default), prores"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Find all unique EXR sequences (by base name)
echo "🔍 Scanning for EXR sequences in: $INPUT_DIR"

find "$INPUT_DIR" -name "*.exr" | \
    sed 's/\.[0-9]\{4,\}\.exr$//' | \
    sort -u | \
while read -r BASENAME; do
    SHOT_NAME=$(basename "$BASENAME")
    echo ""
    echo "📦 Processing: $SHOT_NAME"

    # Determine pattern
    PATTERN="${BASENAME}.%04d.exr"

    case "$CODEC" in
        prores)
            OUTPUT_FILE="$OUTPUT_DIR/${SHOT_NAME}.mov"
            /opt/vfx-platform-2024/bin/exr_to_prores_logc4.sh "$PATTERN" "$OUTPUT_FILE"
            ;;
        h264)
            OUTPUT_FILE="$OUTPUT_DIR/${SHOT_NAME}.mp4"
            /opt/vfx-platform-2024/bin/exr_to_h264_srgb.sh "$PATTERN" "$OUTPUT_FILE"
            ;;
        *)
            echo "❌ Unknown codec: $CODEC"
            exit 1
            ;;
    esac
done

echo ""
echo "✅ Batch encoding complete!"
echo "📁 Output directory: $OUTPUT_DIR"
SCRIPT_EOF

    # Make all scripts executable
    chmod +x "$BIN_DIR"/*.sh

    # Add to PATH in system profile
    if ! grep -q "/opt/vfx-platform-2024/bin" /etc/profile.d/vfx-platform.sh 2>/dev/null; then
        echo 'export PATH="/opt/vfx-platform-2024/bin:$PATH"' > /etc/profile.d/vfx-platform.sh
        log "  ✅ Added scripts to system PATH (/etc/profile.d/vfx-platform.sh)"
    fi

    local duration=$(time_phase $start_time)
    log "✅ Phase 5 complete ($duration)"
}

################################################################################
# Phase 6: Build xstudio (OPTIONAL)
################################################################################

build_xstudio() {
    if [ "$SKIP_XSTUDIO" -eq 1 ]; then
        log "⏭️  Phase 6: Skipping xstudio (optional component)"
        return
    fi

    log "🎭 Phase 6: Building xstudio..."
    local start_time=$(date +%s)

    # Install Qt6 and other dependencies
    log "  Installing xstudio dependencies..."
    dnf install -y \
        qt6-qtbase-devel \
        qt6-qtdeclarative-devel \
        qt6-qtmultimedia-devel \
        qt6-qtwebsockets-devel \
        qt6-qtsvg-devel \
        qt6-qt5compat-devel \
        ffmpeg-devel \
        portaudio-devel \
        portmidi-devel \
        alsa-lib-devel \
        sqlite-devel \
        libcurl-devel \
        libuuid-devel \
        nlohmann-json-devel

    cd "$REPOS_DIR"

    # Clone if not exists
    if [ ! -d "xstudio" ]; then
        log "  Cloning xstudio..."
        git clone https://github.com/AcademySoftwareFoundation/xstudio.git
    fi

    cd xstudio
    git pull

    # Clean previous build
    rm -rf build
    mkdir build
    cd build

    log "  Configuring with CMake..."
    cmake -G Ninja \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DOpenColorIO_ROOT=/usr/local \
        -DOpenImageIO_ROOT=/usr/local \
        .. 2>&1 | tee "$LOG_DIR/xstudio_configure.log"

    log "  Building xstudio (this will take 3-4 hours)..."
    ninja -j$(nproc) 2>&1 | tee "$LOG_DIR/xstudio_build.log"

    log "  Installing xstudio..."
    ninja install 2>&1 | tee "$LOG_DIR/xstudio_install.log"

    ldconfig

    # Create desktop entry
    log "  Creating desktop entry..."
    cat > /usr/share/applications/xstudio.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=xSTUDIO
Comment=VFX Playback and Review
Exec=/usr/local/bin/xstudio
Icon=/usr/local/share/xstudio/icons/xstudio.png
Terminal=false
Categories=AudioVideo;Video;Graphics;
DESKTOP_EOF

    # Verify
    if xstudio --version &> /dev/null; then
        local version=$(xstudio --version 2>&1 | head -1)
        log "  ✅ Installed: $version"
    else
        error_exit "xstudio installation verification failed"
    fi

    local duration=$(time_phase $start_time)
    log "✅ Phase 6 complete ($duration)"
}

################################################################################
# Summary Report
################################################################################

generate_summary() {
    # Update library path for summary verification
    export LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    export PATH=/usr/local/bin:$PATH

    log ""
    log "╔════════════════════════════════════════════════════════════════╗"
    log "║       VFX Reference Platform 2024 - Build Complete!            ║"
    log "╚════════════════════════════════════════════════════════════════╝"
    log ""
    log "✅ Installed Components:"
    log ""

    if [ -x /usr/local/bin/ociocheck ]; then
        log "  🎨 OpenColorIO 2.3.2"
    fi

    if /usr/local/bin/oiiotool --version &> /dev/null; then
        log "  🖼️  OpenImageIO: $(/usr/local/bin/oiiotool --version 2>&1 | head -1)"
    fi

    if /usr/local/bin/rawtoaces --help &> /dev/null; then
        log "  📸 RAWtoACES: Installed"
    fi

    if [ "$SKIP_XSTUDIO" -eq 0 ] && /usr/local/bin/xstudio --version &> /dev/null; then
        log "  🎭 xstudio: $(/usr/local/bin/xstudio --version 2>&1 | head -1)"
    fi

    log ""
    log "📁 Encoding Scripts:"
    log "  $BIN_DIR/exr_to_h264_srgb.sh"
    log "  $BIN_DIR/exr_to_prores_logc4.sh"
    log "  $BIN_DIR/batch_encode_exr.sh"
    log ""
    log "📋 Next Steps:"
    log ""
    log "1. Test OCIO functionality:"
    log "   export OCIO=\"$OCIO_CONFIG\""
    log "   ociocheck"
    log ""
    log "2. Test encoding workflow:"
    log "   exr_to_h264_srgb.sh /path/to/shot.%04d.exr output.mp4 24"
    log ""
    log "3. Deploy to other machines:"
    log "   - Create RPM packages (see deployment script)"
    log "   - Or copy /usr/local/lib and /usr/local/bin to other machines"
    log ""
    log "📚 Documentation:"
    log "  /Volumes/soupnas_01/souptracker/DB/skf_pipeline_v01/docs/VFX_PLATFORM_2024_IMPLEMENTATION.md"
    log ""
    log "📝 Build logs saved to: $LOG_DIR/"
    log ""
}

################################################################################
# Main Execution
################################################################################

main() {
    local total_start_time=$(date +%s)

    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║   VFX Reference Platform 2024 - Master Build Script            ║"
    echo "║   Soup Kitchen Films Pipeline Upgrade                          ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    # Run all phases
    check_prerequisites
    setup_directories
    install_base_dependencies
    build_opencolorio
    build_openimageio
    build_rawtoaces
    create_encoding_scripts
    build_xstudio

    # Generate summary
    local total_duration=$(time_phase $total_start_time)
    log ""
    log "⏱️  Total build time: $total_duration"

    generate_summary

    log "✅ All done! Enjoy your VFX Platform 2024 compliant system!"
}

# Run main function
main "$@"
