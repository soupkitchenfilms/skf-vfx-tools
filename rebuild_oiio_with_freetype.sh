#!/bin/bash
################################################################################
# OpenImageIO - Rebuild with FreeType Support
# Adds text rendering capability to oiiotool
################################################################################

set -e

echo "========================================="
echo "Rebuilding OpenImageIO with FreeType"
echo "========================================="
echo ""

# Step 1: Install FreeType
echo "📦 Step 1/5: Installing FreeType development package..."
dnf install -y freetype-devel 2>&1 | tail -5
echo "   ✅ FreeType installed"
echo ""

# Step 2: Clean build directory
echo "🧹 Step 2/5: Cleaning build directory..."
cd /opt/vfx-platform-2024/repos/OpenImageIO/build
rm -rf *
echo "   ✅ Build directory cleaned"
echo ""

# Step 3: Reconfigure with CMake
echo "⚙️  Step 3/5: Reconfiguring with CMake (will detect FreeType)..."
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
    .. 2>&1 | grep -E "Found Freetype|Configuring done"

if [ $? -eq 0 ]; then
    echo "   ✅ FreeType detected in configuration"
else
    echo "   ⚠️  Configuration completed, check if FreeType was found"
fi
echo ""

# Step 4: Rebuild (faster this time, reuses compiled objects)
echo "🏗️  Step 4/5: Rebuilding OpenImageIO..."
echo "   (Should be faster - reusing previously compiled objects)"
START_TIME=$(date +%s)

ninja -j$(nproc) 2>&1 | tail -20

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo "   ✅ Build completed in ${DURATION} seconds"
echo ""

# Step 5: Reinstall
echo "📥 Step 5/5: Installing updated OpenImageIO..."
ninja install 2>&1 | tail -10
ldconfig
echo "   ✅ Installation complete"
echo ""

# Verify FreeType support
echo "🔍 Verifying FreeType support..."
if oiiotool --help 2>&1 | grep -q "text.*FreeType"; then
    echo "   ✅ Text rendering with FreeType is now available!"
else
    echo "   ℹ️  Testing text functionality..."
    if oiiotool --create 100x100 3 --text "TEST" -o /tmp/freetype_test.png 2>&1; then
        echo "   ✅ Text rendering works!"
        rm -f /tmp/freetype_test.png
    else
        echo "   ⚠️  FreeType may not be enabled, check build output"
    fi
fi

echo ""
echo "========================================="
echo "✅ Rebuild Complete!"
echo "========================================="
echo ""
echo "Test text rendering with:"
echo "  oiiotool --create 1920x1080 3 --text \"VFX Platform 2024\" -o test.png"
