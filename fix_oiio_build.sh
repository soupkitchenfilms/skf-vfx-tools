#!/bin/bash
################################################################################
# OpenImageIO Build Fix Script
# Fixes OpenJPEG version detection and other dependency issues
################################################################################

set -e

echo "🔧 Applying fixes to OpenImageIO build..."

cd /opt/vfx-platform-2024/repos/OpenImageIO

# 1. Fix OpenJPEG pkg-config name (libopenjp2 instead of openjpeg)
echo "  📝 Patching FindOpenJPEG.cmake..."
if grep -q "pkg_check_modules(OPENJPEG_PC QUIET openjpeg)" src/cmake/modules/FindOpenJPEG.cmake; then
    sed -i 's/pkg_check_modules(OPENJPEG_PC QUIET openjpeg)/# Rocky Linux\/RHEL use libopenjp2 as the pkg-config name\n    pkg_check_modules(OPENJPEG_PC QUIET libopenjp2)\n    # Fallback to openjpeg if libopenjp2 not found\n    if(NOT OPENJPEG_PC_FOUND)\n        pkg_check_modules(OPENJPEG_PC QUIET openjpeg)\n    endif()/' src/cmake/modules/FindOpenJPEG.cmake
    echo "     ✅ FindOpenJPEG.cmake patched"
else
    echo "     ℹ️  FindOpenJPEG.cmake already patched"
fi

# 2. Remove PREFER_CONFIG from OpenJPEG detection
echo "  📝 Patching externalpackages.cmake..."
if grep -q "PREFER_CONFIG)" src/cmake/externalpackages.cmake | grep -B2 "OpenJPEG"; then
    sed -i '/checked_find_package (OpenJPEG/,/PREFER_CONFIG)/s/PREFER_CONFIG)/)/; /checked_find_package (OpenJPEG/,/# Note: Recent OpenJPEG/a# PREFER_CONFIG removed to force use of FindOpenJPEG.cmake (fixed for Rocky Linux)' src/cmake/externalpackages.cmake
    echo "     ✅ externalpackages.cmake patched"
else
    echo "     ℹ️  externalpackages.cmake already patched"
fi

# 3. Install missing dependencies
echo "  📦 Installing additional dependencies..."
sudo dnf install -y \
    robin-map-devel \
    libwebp-devel \
    bzip2-devel \
    || echo "     ⚠️  Some packages may not be available"

# 4. Fix build directory ownership
echo "  🔐 Fixing build directory permissions..."
sudo chown -R souprender:souprender /opt/vfx-platform-2024/repos/OpenImageIO/build/
sudo rm -rf /opt/vfx-platform-2024/repos/OpenImageIO/build/*
echo "     ✅ Build directory cleaned and ownership fixed"

# 5. Run CMake with proper configuration
echo "  ⚙️  Configuring OpenImageIO..."
cd /opt/vfx-platform-2024/repos/OpenImageIO/build

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
    -DUSE_JPEGTURBO=OFF \
    -DBUILD_TESTING=OFF \
    .. 2>&1 | tee /opt/vfx-platform-2024/logs/oiio_configure_fixed.log

# Check if configuration succeeded
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "✅ CMake configuration successful!"
    echo ""
    echo "🏗️  Ready to build. Run:"
    echo "   cd /opt/vfx-platform-2024/repos/OpenImageIO/build"
    echo "   ninja -j\$(nproc)"
    echo "   sudo ninja install"
    echo "   sudo ldconfig"
else
    echo "❌ CMake configuration failed. Check logs at:"
    echo "   /opt/vfx-platform-2024/logs/oiio_configure_fixed.log"
    exit 1
fi
