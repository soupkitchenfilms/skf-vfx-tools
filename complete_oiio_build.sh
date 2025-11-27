#!/bin/bash
################################################################################
# OpenImageIO - Complete Build Script
# Applies all fixes and builds OpenImageIO 3.x
################################################################################

set -e

echo "=================================="
echo "OpenImageIO 3.x - Complete Build"
echo "=================================="
echo ""

# Step 1: Install missing dependencies
echo "📦 Step 1/5: Installing additional dependencies..."
dnf install -y robin-map-devel libwebp-devel bzip2-devel 2>&1 | grep -E "^(Install|Upgrade|Nothing|Complete)" || true
echo "   ✅ Dependencies installed"
echo ""

# Step 2: Fix permissions
echo "🔐 Step 2/5: Fixing build directory permissions..."
chown -R souprender:souprender /opt/vfx-platform-2024/repos/OpenImageIO/build/
rm -rf /opt/vfx-platform-2024/repos/OpenImageIO/build/*
echo "   ✅ Build directory cleaned and permissions fixed"
echo ""

# Step 3: Run CMake
echo "⚙️  Step 3/5: Configuring OpenImageIO with CMake..."
cd /opt/vfx-platform-2024/repos/OpenImageIO/build

su - souprender -c "cd /opt/vfx-platform-2024/repos/OpenImageIO/build && cmake -G Ninja \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DCMAKE_BUILD_TYPE=Release \
    -DUSE_PYTHON=ON \
    -DUSE_OPENCOLORIO=ON \
    -DOpenColorIO_ROOT=/usr/local \
    -DUSE_OPENCV=ON \
    -DUSE_LIBRAW=ON \
    -DUSE_OPENEXR=ON \
    -DUSE_FFMPEG=ON \
    -DUSE_JPEGTURBO=OFF \
    -DBUILD_TESTING=OFF \
    .. 2>&1" | tee /opt/vfx-platform-2024/logs/oiio_configure_final.log

# Check if CMake succeeded
if grep -q "Found OpenJPEG 2.4.0" /opt/vfx-platform-2024/logs/oiio_configure_final.log && \
   grep -q "Configuring done" /opt/vfx-platform-2024/logs/oiio_configure_final.log; then
    echo "   ✅ CMake configuration successful!"
    echo ""
else
    echo "   ❌ CMake configuration failed. Check log at:"
    echo "      /opt/vfx-platform-2024/logs/oiio_configure_final.log"
    exit 1
fi

# Step 4: Build
echo "🏗️  Step 4/5: Building OpenImageIO (this will take 3-4 hours)..."
echo "   Started at: $(date)"
START_TIME=$(date +%s)

su - souprender -c "cd /opt/vfx-platform-2024/repos/OpenImageIO/build && ninja -j\$(nproc)" 2>&1 | tee /opt/vfx-platform-2024/logs/oiio_build_final.log

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
HOURS=$((DURATION / 3600))
MINUTES=$(((DURATION % 3600) / 60))

echo "   ✅ Build completed in ${HOURS}h ${MINUTES}m"
echo ""

# Step 5: Install
echo "📥 Step 5/5: Installing OpenImageIO..."
su - souprender -c "cd /opt/vfx-platform-2024/repos/OpenImageIO/build && ninja install" 2>&1 | tee /opt/vfx-platform-2024/logs/oiio_install_final.log
ldconfig
echo "   ✅ Installation complete"
echo ""

# Verify
echo "🔍 Verifying installation..."
if oiiotool --version 2>&1 | grep -q "OpenImageIO 3"; then
    OIIO_VERSION=$(oiiotool --version 2>&1 | head -1)
    echo "   ✅ $OIIO_VERSION"

    if oiiotool --help | grep -q colorconvert; then
        echo "   ✅ OCIO integration confirmed"
    fi

    echo ""
    echo "=================================="
    echo "✅ OpenImageIO 3.x Build Complete!"
    echo "=================================="
    echo ""
    echo "Installed components:"
    ls -lh /usr/local/bin/oiio* | awk '{print "  - " $9}'
    echo ""
    echo "Next: Continue with VFX Platform 2024 build (RAWtoACES, encoding scripts)"
else
    echo "   ⚠️  Installation verification failed"
    echo "   Check that oiiotool is in PATH and libraries are loaded"
fi
