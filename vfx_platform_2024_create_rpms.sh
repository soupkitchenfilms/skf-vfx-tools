#!/bin/bash
################################################################################
# VFX Reference Platform 2024 - RPM Package Creator
# Soup Kitchen Films Pipeline Upgrade
#
# This script creates RPM packages from the built VFX Platform components
# for easy deployment to other machines (8-10 machines).
#
# Prerequisites:
#   - Master build script has been run successfully
#   - Components are installed in /usr/local
#   - fpm (Effing Package Manager) is installed
#
# Usage:
#   sudo bash vfx_platform_2024_create_rpms.sh
#
# Output:
#   RPM packages in /opt/vfx-platform-2024/rpms/
#
# Author: Claude (Anthropic)
# Date: 2025-11-22
################################################################################

set -e
set -u

################################################################################
# Configuration
################################################################################

BUILD_ROOT="/opt/vfx-platform-2024"
RPM_DIR="$BUILD_ROOT/rpms"
VERSION="2024.1"  # VFX Platform CY2024 version
ITERATION="1"     # Package iteration

################################################################################
# Helper Functions
################################################################################

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
    echo "❌ ERROR: $1"
    exit 1
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        error_exit "Required command not found: $1"
    fi
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

    # Check if fpm is installed
    if ! command -v fpm &> /dev/null; then
        log "  Installing fpm (Effing Package Manager)..."
        dnf install -y ruby-devel gcc make rpm-build
        gem install --no-document fpm
    fi

    check_command fpm

    # Check if components are built
    if ! ociocheck --version &> /dev/null; then
        error_exit "OpenColorIO not found. Run master build script first."
    fi

    if ! oiiotool --version &> /dev/null; then
        error_exit "OpenImageIO not found. Run master build script first."
    fi

    log "✅ Prerequisites check passed"
}

################################################################################
# Create RPM Directory
################################################################################

setup_rpm_directory() {
    log "📁 Setting up RPM directory..."
    mkdir -p "$RPM_DIR"
    log "  RPMs will be created in: $RPM_DIR"
}

################################################################################
# Package OpenColorIO
################################################################################

package_opencolorio() {
    log "📦 Creating OpenColorIO RPM..."

    local version=$(ociocheck --version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1)
    local pkg_name="vfx-opencolorio"

    fpm -s dir -t rpm \
        -n "$pkg_name" \
        -v "$version" \
        --iteration "$ITERATION" \
        --prefix /usr/local \
        --architecture x86_64 \
        --maintainer "Soup Kitchen Films <pipeline@soupkitchenfilms.com>" \
        --description "OpenColorIO 2.3.x - VFX Platform CY2024" \
        --url "https://opencolorio.org/" \
        --license "BSD-3-Clause" \
        --category "Graphics" \
        --depends "boost >= 1.70" \
        --depends "yaml-cpp" \
        --depends "expat" \
        --rpm-summary "Color management library for VFX" \
        -C /usr/local \
        --package "$RPM_DIR" \
        bin/ociocheck \
        bin/ocioconvert \
        bin/ociolutimage \
        bin/ociowrite \
        lib64/libOpenColorIO*.so* \
        lib64/cmake/OpenColorIO \
        include/OpenColorIO \
        share/ocio

    log "  ✅ Created: ${pkg_name}-${version}-${ITERATION}.x86_64.rpm"
}

################################################################################
# Package OpenImageIO
################################################################################

package_openimageio() {
    log "📦 Creating OpenImageIO RPM..."

    local version=$(oiiotool --version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1)
    local pkg_name="vfx-openimageio"

    fpm -s dir -t rpm \
        -n "$pkg_name" \
        -v "$version" \
        --iteration "$ITERATION" \
        --prefix /usr/local \
        --architecture x86_64 \
        --maintainer "Soup Kitchen Films <pipeline@soupkitchenfilms.com>" \
        --description "OpenImageIO 3.x - VFX Platform CY2024" \
        --url "https://openimageio.org/" \
        --license "Apache-2.0" \
        --category "Graphics" \
        --depends "vfx-opencolorio" \
        --depends "boost >= 1.70" \
        --depends "libraw" \
        --depends "openexr-libs" \
        --rpm-summary "Image I/O library for VFX" \
        -C /usr/local \
        --package "$RPM_DIR" \
        bin/oiiotool \
        bin/maketx \
        bin/iinfo \
        bin/igrep \
        bin/iconvert \
        bin/idiff \
        bin/iv \
        lib64/libOpenImageIO*.so* \
        lib64/cmake/OpenImageIO \
        include/OpenImageIO \
        share/fonts/OpenImageIO

    log "  ✅ Created: ${pkg_name}-${version}-${ITERATION}.x86_64.rpm"
}

################################################################################
# Package RAWtoACES
################################################################################

package_rawtoaces() {
    log "📦 Creating RAWtoACES RPM..."

    local version="1.0.0"  # RAWtoACES doesn't have easy version detection
    local pkg_name="vfx-rawtoaces"

    fpm -s dir -t rpm \
        -n "$pkg_name" \
        -v "$version" \
        --iteration "$ITERATION" \
        --prefix /usr/local \
        --architecture x86_64 \
        --maintainer "Soup Kitchen Films <pipeline@soupkitchenfilms.com>" \
        --description "RAWtoACES - Camera RAW to ACES converter" \
        --url "https://github.com/AcademySoftwareFoundation/rawtoaces" \
        --license "AMPAS" \
        --category "Graphics" \
        --depends "libraw" \
        --rpm-summary "Convert camera RAW files to ACES EXR" \
        -C /usr/local \
        --package "$RPM_DIR" \
        bin/rawtoaces \
        lib64/libAcesContainer*.so* \
        lib64/libceres*.so* \
        include/acescontainer \
        include/ceres

    log "  ✅ Created: ${pkg_name}-${version}-${ITERATION}.x86_64.rpm"
}

################################################################################
# Package Encoding Scripts
################################################################################

package_encoding_scripts() {
    log "📦 Creating encoding scripts RPM..."

    local pkg_name="vfx-encoding-scripts"

    fpm -s dir -t rpm \
        -n "$pkg_name" \
        -v "$VERSION" \
        --iteration "$ITERATION" \
        --prefix /opt/vfx-platform-2024 \
        --architecture noarch \
        --maintainer "Soup Kitchen Films <pipeline@soupkitchenfilms.com>" \
        --description "EXR to Movie encoding scripts with OCIO support" \
        --license "Proprietary" \
        --category "Graphics" \
        --depends "vfx-opencolorio" \
        --depends "vfx-openimageio" \
        --depends "ffmpeg" \
        --rpm-summary "Production encoding workflows for VFX" \
        --after-install "$BUILD_ROOT/post_install_scripts.sh" \
        -C /opt/vfx-platform-2024 \
        --package "$RPM_DIR" \
        bin/exr_to_h264_srgb.sh \
        bin/exr_to_prores_logc4.sh \
        bin/batch_encode_exr.sh

    log "  ✅ Created: ${pkg_name}-${VERSION}-${ITERATION}.noarch.rpm"
}

################################################################################
# Create post-install script for encoding scripts
################################################################################

create_post_install_script() {
    log "📝 Creating post-install script..."

    cat > "$BUILD_ROOT/post_install_scripts.sh" << 'POST_INSTALL_EOF'
#!/bin/bash
# Post-install script for encoding scripts package

# Add scripts to PATH
if ! grep -q "/opt/vfx-platform-2024/bin" /etc/profile.d/vfx-platform.sh 2>/dev/null; then
    echo 'export PATH="/opt/vfx-platform-2024/bin:$PATH"' > /etc/profile.d/vfx-platform.sh
    chmod 644 /etc/profile.d/vfx-platform.sh
fi

# Update ldconfig
ldconfig

echo "✅ VFX Platform encoding scripts installed"
echo "   Scripts added to PATH: /opt/vfx-platform-2024/bin"
echo "   Reload shell or run: source /etc/profile.d/vfx-platform.sh"
POST_INSTALL_EOF

    chmod +x "$BUILD_ROOT/post_install_scripts.sh"
}

################################################################################
# Package xstudio (if installed)
################################################################################

package_xstudio() {
    if ! xstudio --version &> /dev/null; then
        log "⏭️  Skipping xstudio package (not installed)"
        return
    fi

    log "📦 Creating xstudio RPM..."

    local version=$(xstudio --version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "1.0.0")
    local pkg_name="vfx-xstudio"

    fpm -s dir -t rpm \
        -n "$pkg_name" \
        -v "$version" \
        --iteration "$ITERATION" \
        --prefix /usr/local \
        --architecture x86_64 \
        --maintainer "Soup Kitchen Films <pipeline@soupkitchenfilms.com>" \
        --description "xstudio - Open source playback and review application" \
        --url "https://github.com/AcademySoftwareFoundation/xstudio" \
        --license "Apache-2.0" \
        --category "AudioVideo" \
        --depends "vfx-opencolorio" \
        --depends "vfx-openimageio" \
        --depends "qt6-qtbase" \
        --depends "ffmpeg" \
        --rpm-summary "VFX playback and review player" \
        -C /usr/local \
        --package "$RPM_DIR" \
        bin/xstudio \
        lib64/libxstudio*.so* \
        lib64/xstudio \
        share/xstudio \
        share/applications/xstudio.desktop

    log "  ✅ Created: ${pkg_name}-${version}-${ITERATION}.x86_64.rpm"
}

################################################################################
# Create master installation script
################################################################################

create_install_script() {
    log "📝 Creating master installation script..."

    cat > "$RPM_DIR/install_vfx_platform.sh" << 'INSTALL_EOF'
#!/bin/bash
################################################################################
# VFX Platform 2024 - Installation Script
# Installs all VFX Platform RPM packages on target machine
#
# Usage: sudo bash install_vfx_platform.sh
################################################################################

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   VFX Platform 2024 - Package Installation                    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)"
    exit 1
fi

# Get directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "📦 Installing VFX Platform 2024 packages..."
echo ""

# Install in dependency order
echo "1️⃣  Installing OpenColorIO..."
rpm -Uvh --force "$SCRIPT_DIR"/vfx-opencolorio-*.rpm

echo "2️⃣  Installing OpenImageIO..."
rpm -Uvh --force "$SCRIPT_DIR"/vfx-openimageio-*.rpm

echo "3️⃣  Installing RAWtoACES..."
rpm -Uvh --force "$SCRIPT_DIR"/vfx-rawtoaces-*.rpm

echo "4️⃣  Installing encoding scripts..."
rpm -Uvh --force "$SCRIPT_DIR"/vfx-encoding-scripts-*.rpm

# Optional: xstudio
if ls "$SCRIPT_DIR"/vfx-xstudio-*.rpm 1> /dev/null 2>&1; then
    echo "5️⃣  Installing xstudio..."
    rpm -Uvh --force "$SCRIPT_DIR"/vfx-xstudio-*.rpm
fi

# Update ldconfig
ldconfig

echo ""
echo "✅ VFX Platform 2024 installed successfully!"
echo ""
echo "📋 Installed components:"
echo "  🎨 OpenColorIO: $(ociocheck --version 2>&1 | head -1)"
echo "  🖼️  OpenImageIO: $(oiiotool --version 2>&1 | head -1)"
echo "  📸 RAWtoACES: $(which rawtoaces)"
echo "  🎬 Encoding scripts: /opt/vfx-platform-2024/bin/"
if command -v xstudio &> /dev/null; then
    echo "  🎭 xstudio: $(xstudio --version 2>&1 | head -1)"
fi
echo ""
echo "📝 Next steps:"
echo "  1. Reload shell: source /etc/profile.d/vfx-platform.sh"
echo "  2. Test: ociocheck --version"
echo "  3. Test: oiiotool --version"
echo ""
INSTALL_EOF

    chmod +x "$RPM_DIR/install_vfx_platform.sh"

    log "  ✅ Created: $RPM_DIR/install_vfx_platform.sh"
}

################################################################################
# Create deployment tarball
################################################################################

create_deployment_tarball() {
    log "📦 Creating deployment tarball..."

    cd "$BUILD_ROOT"

    tar -czf "vfx-platform-2024-rpms.tar.gz" -C "$RPM_DIR" .

    local size=$(du -h "vfx-platform-2024-rpms.tar.gz" | cut -f1)

    log "  ✅ Created: $BUILD_ROOT/vfx-platform-2024-rpms.tar.gz ($size)"
}

################################################################################
# Summary
################################################################################

generate_summary() {
    log ""
    log "╔════════════════════════════════════════════════════════════════╗"
    log "║       VFX Platform 2024 - RPM Packages Created                ║"
    log "╚════════════════════════════════════════════════════════════════╝"
    log ""
    log "📁 RPM packages location: $RPM_DIR/"
    log ""
    log "📦 Created packages:"
    ls -1h "$RPM_DIR"/*.rpm | while read -r rpm; do
        local size=$(du -h "$rpm" | cut -f1)
        log "  $(basename "$rpm") ($size)"
    done
    log ""
    log "📦 Deployment tarball:"
    log "  $BUILD_ROOT/vfx-platform-2024-rpms.tar.gz"
    log ""
    log "🚀 Deployment to other machines:"
    log ""
    log "1. Copy tarball to target machine:"
    log "   scp vfx-platform-2024-rpms.tar.gz user@machine:/tmp/"
    log ""
    log "2. On target machine, extract and install:"
    log "   cd /tmp"
    log "   tar -xzf vfx-platform-2024-rpms.tar.gz"
    log "   sudo bash install_vfx_platform.sh"
    log ""
    log "3. Reload shell:"
    log "   source /etc/profile.d/vfx-platform.sh"
    log ""
    log "✅ Ready to deploy to 8-10 machines!"
    log ""
}

################################################################################
# Main Execution
################################################################################

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║   VFX Platform 2024 - RPM Package Creator                     ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    check_prerequisites
    setup_rpm_directory
    create_post_install_script

    # Create all packages
    package_opencolorio
    package_openimageio
    package_rawtoaces
    package_encoding_scripts
    package_xstudio

    # Create deployment tools
    create_install_script
    create_deployment_tarball

    generate_summary

    log "✅ All done! RPM packages ready for deployment."
}

# Run main function
main "$@"
