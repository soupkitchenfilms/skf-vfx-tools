#!/bin/bash
#===============================================================================
# VFX Reference Platform 2024 - Ubuntu 24.04 Master Build Script
#===============================================================================
#
# This script builds and installs VFX Platform CY2024 components on Ubuntu 24.04
# Adapted from Rocky Linux 9.6 version for Debian/Ubuntu package management
#
# Components:
#   - OpenColorIO 2.3.x (color management, ACES workflows)
#   - OpenImageIO 3.x (image I/O with OCIO integration)
#   - RAWtoACES (camera RAW to ACES conversion)
#   - Encoding scripts (EXR to ProRes/H.264)
#   - xstudio (optional - review/playback application)
#
# Usage:
#   sudo bash vfx_platform_2024_ubuntu_build.sh [--skip-xstudio]
#
# Estimated time: 10-14 hours (unattended)
#
# Author: SKF Pipeline Team
# Date: 2025-12-05
# Platform: Ubuntu 24.04 LTS (Noble Numbat)
#===============================================================================

set -e  # Exit on error

#-------------------------------------------------------------------------------
# Configuration
#-------------------------------------------------------------------------------
VFX_ROOT="/opt/vfx-platform-2024"
LOG_FILE="$VFX_ROOT/build.log"
INSTALL_PREFIX="/usr/local"
NPROC=$(nproc)

# Component versions
OCIO_VERSION="v2.3.2"
OIIO_VERSION="v2.5.16.0"  # Latest stable, OCIO 2.3 compatible
CERES_VERSION="2.2.0"

# Flags
SKIP_XSTUDIO=false
SKIP_RAWTOACES=false

#-------------------------------------------------------------------------------
# Parse arguments
#-------------------------------------------------------------------------------
for arg in "$@"; do
    case $arg in
        --skip-xstudio)
            SKIP_XSTUDIO=true
            shift
            ;;
        --skip-rawtoaces)
            SKIP_RAWTOACES=true
            shift
            ;;
        *)
            ;;
    esac
done

#-------------------------------------------------------------------------------
# Helper functions
#-------------------------------------------------------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_section() {
    echo "" | tee -a "$LOG_FILE"
    echo "===============================================================================" | tee -a "$LOG_FILE"
    echo " $1" | tee -a "$LOG_FILE"
    echo "===============================================================================" | tee -a "$LOG_FILE"
}

check_success() {
    if [ $? -eq 0 ]; then
        log "SUCCESS: $1"
    else
        log "FAILED: $1"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# Pre-flight checks
#-------------------------------------------------------------------------------
log_section "PRE-FLIGHT CHECKS"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Check Ubuntu version
if ! grep -q "Ubuntu 24.04" /etc/os-release 2>/dev/null; then
    log "WARNING: This script is designed for Ubuntu 24.04. Your system:"
    cat /etc/os-release | grep PRETTY_NAME
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create directories
mkdir -p "$VFX_ROOT"/{src,bin}
cd "$VFX_ROOT"

log "Build directory: $VFX_ROOT"
log "Install prefix: $INSTALL_PREFIX"
log "CPU cores: $NPROC"
log "Skip xstudio: $SKIP_XSTUDIO"
log "Skip RAWtoACES: $SKIP_RAWTOACES"

#===============================================================================
# PHASE 1: Install Dependencies
#===============================================================================
log_section "PHASE 1: Installing Ubuntu Dependencies"

log "Updating package lists..."
apt-get update

log "Installing build essentials..."
apt-get install -y \
    build-essential \
    cmake \
    ninja-build \
    git \
    pkg-config \
    curl \
    wget

log "Installing library dependencies..."
apt-get install -y \
    libboost-all-dev \
    libtbb-dev \
    libx11-dev \
    libxext-dev \
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    python3-dev \
    python3-pip \
    python3-numpy \
    pybind11-dev \
    zlib1g-dev \
    libjpeg-turbo8-dev \
    libpng-dev \
    libtiff-dev \
    libwebp-dev \
    libraw-dev \
    libgif-dev \
    libheif-dev \
    libopenjp2-7-dev \
    libopenexr-dev \
    libilmbase-dev \
    libblosc-dev \
    libfmt-dev \
    libyaml-cpp-dev \
    libexpat1-dev \
    libminizip-dev \
    libssl-dev \
    libcurl4-openssl-dev

log "Installing FFmpeg..."
apt-get install -y ffmpeg libavcodec-dev libavformat-dev libavutil-dev libswscale-dev

log "Installing Qt6 (for xstudio)..."
apt-get install -y \
    qt6-base-dev \
    qt6-declarative-dev \
    qt6-multimedia-dev \
    qt6-websockets-dev \
    qt6-svg-dev \
    qt6-5compat-dev \
    qml6-module-qtquick \
    qml6-module-qtquick-controls \
    qml6-module-qtquick-layouts \
    qml6-module-qtquick-window \
    libqt6opengl6-dev

# Install existing OCIO/OIIO tools as fallback
log "Installing Ubuntu OpenColorIO and OpenImageIO packages (fallback)..."
apt-get install -y \
    opencolorio-tools \
    openimageio-tools \
    python3-openimageio \
    python3-pyopencolorio \
    libopencolorio-dev \
    libopenimageio-dev

check_success "Phase 1: Dependencies installed"

#===============================================================================
# PHASE 2: Build OpenColorIO 2.3.x
#===============================================================================
log_section "PHASE 2: Building OpenColorIO $OCIO_VERSION"

cd "$VFX_ROOT/src"

if [ ! -d "OpenColorIO" ]; then
    log "Cloning OpenColorIO..."
    git clone https://github.com/AcademySoftwareFoundation/OpenColorIO.git
fi

cd OpenColorIO
git fetch --all --tags
git checkout $OCIO_VERSION
check_success "Checked out OCIO $OCIO_VERSION"

# Clean previous build
rm -rf build
mkdir build && cd build

log "Configuring OpenColorIO..."
cmake -G Ninja \
    -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
    -DCMAKE_BUILD_TYPE=Release \
    -DOCIO_BUILD_APPS=ON \
    -DOCIO_BUILD_PYTHON=ON \
    -DOCIO_BUILD_TESTS=OFF \
    -DOCIO_BUILD_GPU_TESTS=OFF \
    -DOCIO_INSTALL_EXT_PACKAGES=MISSING \
    -DPython_EXECUTABLE=/usr/bin/python3 \
    ..
check_success "OCIO CMake configuration"

log "Building OpenColorIO (this may take 30-60 minutes)..."
ninja -j$NPROC
check_success "OCIO build"

log "Installing OpenColorIO..."
ninja install
check_success "OCIO install"

# Update library cache
ldconfig

# Verify installation
log "Verifying OpenColorIO installation..."
if $INSTALL_PREFIX/bin/ociocheck 2>&1 | grep -q "OpenColorIO"; then
    log "OpenColorIO installed successfully"
    $INSTALL_PREFIX/bin/ociocheck 2>&1 | head -5 | tee -a "$LOG_FILE"
else
    log "WARNING: ociocheck verification unclear, continuing..."
fi

# Test Python bindings
python3 -c "import PyOpenColorIO as OCIO; print(f'PyOpenColorIO version: {OCIO.GetVersion()}')" 2>&1 | tee -a "$LOG_FILE" || log "WARNING: Python bindings may need PYTHONPATH update"

check_success "Phase 2: OpenColorIO $OCIO_VERSION installed"

#===============================================================================
# PHASE 3: Build OpenImageIO 2.5.x
#===============================================================================
log_section "PHASE 3: Building OpenImageIO $OIIO_VERSION"

cd "$VFX_ROOT/src"

if [ ! -d "OpenImageIO" ]; then
    log "Cloning OpenImageIO..."
    git clone https://github.com/AcademySoftwareFoundation/OpenImageIO.git
fi

cd OpenImageIO
git fetch --all --tags
git checkout $OIIO_VERSION
check_success "Checked out OIIO $OIIO_VERSION"

# Clean previous build
rm -rf build
mkdir build && cd build

log "Configuring OpenImageIO..."
cmake -G Ninja \
    -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
    -DCMAKE_BUILD_TYPE=Release \
    -DUSE_PYTHON=ON \
    -DUSE_OPENCOLORIO=ON \
    -DOpenColorIO_ROOT=$INSTALL_PREFIX \
    -DUSE_OPENCV=OFF \
    -DUSE_OPENVDB=OFF \
    -DUSE_PTEX=OFF \
    -DUSE_LIBRAW=ON \
    -DUSE_OPENEXR=ON \
    -DUSE_FFMPEG=ON \
    -DUSE_FREETYPE=ON \
    -DUSE_GIF=ON \
    -DUSE_LIBHEIF=ON \
    -DUSE_OPENJPEG=ON \
    -DUSE_WEBP=ON \
    -DBUILD_TESTING=OFF \
    -DOIIO_BUILD_TESTS=OFF \
    -DPython_EXECUTABLE=/usr/bin/python3 \
    ..
check_success "OIIO CMake configuration"

log "Building OpenImageIO (this may take 60-90 minutes)..."
ninja -j$NPROC
check_success "OIIO build"

log "Installing OpenImageIO..."
ninja install
check_success "OIIO install"

# Update library cache
ldconfig

# Verify installation
log "Verifying OpenImageIO installation..."
$INSTALL_PREFIX/bin/oiiotool --version 2>&1 | tee -a "$LOG_FILE"
$INSTALL_PREFIX/bin/oiiotool --help 2>&1 | grep -i colorconvert | head -3 | tee -a "$LOG_FILE"

check_success "Phase 3: OpenImageIO $OIIO_VERSION installed"

#===============================================================================
# PHASE 4: Build RAWtoACES (Optional)
#===============================================================================
if [ "$SKIP_RAWTOACES" = false ]; then
    log_section "PHASE 4: Building RAWtoACES"

    cd "$VFX_ROOT/src"

    # Build Ceres Solver (dependency)
    log "Building Ceres Solver $CERES_VERSION..."
    apt-get install -y libgoogle-glog-dev libgflags-dev libeigen3-dev libsuitesparse-dev

    if [ ! -d "ceres-solver" ]; then
        git clone https://github.com/ceres-solver/ceres-solver.git
    fi
    cd ceres-solver
    git checkout $CERES_VERSION
    rm -rf build && mkdir build && cd build

    cmake -G Ninja \
        -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTING=OFF \
        -DBUILD_EXAMPLES=OFF \
        ..
    ninja -j$NPROC
    ninja install
    ldconfig
    check_success "Ceres Solver installed"

    # Build ACES Container
    log "Building ACES Container..."
    cd "$VFX_ROOT/src"
    if [ ! -d "aces_container" ]; then
        git clone https://github.com/ampas/aces_container.git
    fi
    cd aces_container
    rm -rf build && mkdir build && cd build
    cmake -G Ninja \
        -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
        -DCMAKE_BUILD_TYPE=Release \
        ..
    ninja -j$NPROC
    ninja install
    ldconfig
    check_success "ACES Container installed"

    # Build RAWtoACES
    log "Building RAWtoACES..."
    cd "$VFX_ROOT/src"
    if [ ! -d "rawtoaces" ]; then
        git clone https://github.com/AcademySoftwareFoundation/rawtoaces.git
    fi
    cd rawtoaces
    rm -rf build && mkdir build && cd build

    cmake -G Ninja \
        -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
        -DCMAKE_BUILD_TYPE=Release \
        ..
    ninja -j$NPROC || log "WARNING: RAWtoACES build may have issues, continuing..."
    ninja install || log "WARNING: RAWtoACES install may have issues"
    ldconfig

    # Verify
    if command -v rawtoaces &> /dev/null; then
        log "RAWtoACES installed successfully"
        rawtoaces --help 2>&1 | head -5 | tee -a "$LOG_FILE"
    else
        log "WARNING: RAWtoACES not in PATH, may need manual setup"
    fi

    check_success "Phase 4: RAWtoACES build attempted"
else
    log_section "PHASE 4: Skipping RAWtoACES (--skip-rawtoaces flag)"
fi

#===============================================================================
# PHASE 5: Create Encoding Scripts
#===============================================================================
log_section "PHASE 5: Creating Encoding Scripts"

# Script 1: EXR to H.264 sRGB (Client Review)
cat > "$VFX_ROOT/bin/exr_to_h264_srgb.sh" << 'SCRIPT_EOF'
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
SCRIPT_EOF

# Script 2: EXR to ProRes LogC4 (Editorial)
cat > "$VFX_ROOT/bin/exr_to_prores_logc4.sh" << 'SCRIPT_EOF'
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
SCRIPT_EOF

# Script 3: Batch encoder
cat > "$VFX_ROOT/bin/batch_encode_exr.sh" << 'SCRIPT_EOF'
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
SCRIPT_EOF

# Make scripts executable
chmod +x "$VFX_ROOT/bin/"*.sh

# Create symlinks in /usr/local/bin
ln -sf "$VFX_ROOT/bin/exr_to_h264_srgb.sh" /usr/local/bin/
ln -sf "$VFX_ROOT/bin/exr_to_prores_logc4.sh" /usr/local/bin/
ln -sf "$VFX_ROOT/bin/batch_encode_exr.sh" /usr/local/bin/

check_success "Phase 5: Encoding scripts created"

#===============================================================================
# PHASE 6: Build xstudio (Optional)
#===============================================================================
if [ "$SKIP_XSTUDIO" = false ]; then
    log_section "PHASE 6: Building xstudio"

    cd "$VFX_ROOT/src"

    # Additional xstudio dependencies
    apt-get install -y \
        libsqlite3-dev \
        libuuid1 \
        uuid-dev \
        nlohmann-json3-dev \
        libspdlog-dev \
        libfftw3-dev \
        libasound2-dev

    if [ ! -d "xstudio" ]; then
        log "Cloning xstudio..."
        git clone https://github.com/AcademySoftwareFoundation/xstudio.git
    fi

    cd xstudio
    git pull

    rm -rf build && mkdir build && cd build

    log "Configuring xstudio..."
    cmake -G Ninja \
        -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DOpenColorIO_ROOT=$INSTALL_PREFIX \
        -DOpenImageIO_ROOT=$INSTALL_PREFIX \
        .. || log "WARNING: xstudio CMake may have issues"

    log "Building xstudio (this may take 2-3 hours)..."
    ninja -j$NPROC || log "WARNING: xstudio build may have failed"

    ninja install || log "WARNING: xstudio install may have failed"
    ldconfig

    # Create desktop entry
    cat > /usr/share/applications/xstudio.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=xSTUDIO
Comment=VFX Playback and Review
Exec=/usr/local/bin/xstudio
Icon=xstudio
Terminal=false
Categories=AudioVideo;Video;Graphics;
DESKTOP_EOF

    check_success "Phase 6: xstudio build attempted"
else
    log_section "PHASE 6: Skipping xstudio (--skip-xstudio flag)"
fi

#===============================================================================
# PHASE 7: Environment Setup
#===============================================================================
log_section "PHASE 7: Environment Setup"

# Create environment script
cat > /etc/profile.d/vfx-platform-2024.sh << 'ENV_EOF'
# VFX Reference Platform 2024 Environment
# NOTE: OCIO is NOT set globally - it would break Nuke's color management
# Encoding scripts set OCIO locally when needed
export VFX_PLATFORM_VERSION="2024"
export PATH="/usr/local/bin:/opt/vfx-platform-2024/bin:$PATH"
export LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH:-}"
export PYTHONPATH="/usr/local/lib/python3/dist-packages:${PYTHONPATH:-}"
ENV_EOF

chmod +x /etc/profile.d/vfx-platform-2024.sh

# Update library cache
ldconfig

check_success "Phase 7: Environment configured"

#===============================================================================
# PHASE 8: Verification
#===============================================================================
log_section "PHASE 8: Final Verification"

log "Checking installed components..."

echo "" | tee -a "$LOG_FILE"
echo "VFX Reference Platform CY2024 - Ubuntu 24.04 Build Complete" | tee -a "$LOG_FILE"
echo "============================================================" | tee -a "$LOG_FILE"

# System info
echo "" | tee -a "$LOG_FILE"
echo "System:" | tee -a "$LOG_FILE"
cat /etc/os-release | grep PRETTY_NAME | tee -a "$LOG_FILE"
gcc --version | head -1 | tee -a "$LOG_FILE"
python3 --version | tee -a "$LOG_FILE"

# OCIO
echo "" | tee -a "$LOG_FILE"
echo "OpenColorIO:" | tee -a "$LOG_FILE"
$INSTALL_PREFIX/bin/ociocheck 2>&1 | head -3 | tee -a "$LOG_FILE" || echo "ociocheck not working" | tee -a "$LOG_FILE"

# OIIO
echo "" | tee -a "$LOG_FILE"
echo "OpenImageIO:" | tee -a "$LOG_FILE"
$INSTALL_PREFIX/bin/oiiotool --version 2>&1 | head -1 | tee -a "$LOG_FILE" || echo "oiiotool not found" | tee -a "$LOG_FILE"

# RAWtoACES
echo "" | tee -a "$LOG_FILE"
echo "RAWtoACES:" | tee -a "$LOG_FILE"
$INSTALL_PREFIX/bin/rawtoaces --help 2>&1 | head -1 | tee -a "$LOG_FILE" || echo "rawtoaces not installed" | tee -a "$LOG_FILE"

# xstudio
echo "" | tee -a "$LOG_FILE"
echo "xstudio:" | tee -a "$LOG_FILE"
$INSTALL_PREFIX/bin/xstudio --version 2>&1 | head -1 | tee -a "$LOG_FILE" || echo "xstudio not installed" | tee -a "$LOG_FILE"

# FFmpeg
echo "" | tee -a "$LOG_FILE"
echo "FFmpeg:" | tee -a "$LOG_FILE"
ffmpeg -version 2>&1 | head -1 | tee -a "$LOG_FILE"

echo "" | tee -a "$LOG_FILE"
echo "============================================================" | tee -a "$LOG_FILE"
echo "Build complete! Log file: $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "To activate the environment, run:" | tee -a "$LOG_FILE"
echo "  source /etc/profile.d/vfx-platform-2024.sh" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Or log out and log back in." | tee -a "$LOG_FILE"
echo "============================================================" | tee -a "$LOG_FILE"

check_success "VFX Platform 2024 Ubuntu build complete"
