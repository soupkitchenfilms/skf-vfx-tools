#!/bin/bash
# VFX Platform 2024 - Quick Start
# This script helps you get started with the implementation

set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   VFX Reference Platform 2024 - Quick Start                  ║"
echo "║   Soup Kitchen Films Pipeline Upgrade                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "❌ Please do not run this script as root"
    echo "   It will use sudo when necessary"
    exit 1
fi

# Check documentation
DOC_FILE="/Volumes/soupnas_01/souptracker/DB/skf_pipeline_v01/docs/VFX_PLATFORM_2024_IMPLEMENTATION.md"
if [ ! -f "$DOC_FILE" ]; then
    echo "❌ Implementation plan not found!"
    echo "   Expected: $DOC_FILE"
    exit 1
fi

echo "📚 Implementation plan found:"
echo "   $DOC_FILE"
echo ""

# Show what we'll do
cat << 'EOF'
This script will help you:

1. ✅ Check current system status
2. ✅ Install base dependencies
3. ✅ Create build directory structure
4. ⏸️  Guide you through manual build steps

The complete implementation takes 16-25 hours across 2-3 days.
This quick start handles Phase 1 (Preparation).

EOF

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "PHASE 1: SYSTEM CHECK"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check OS
echo "🖥️  Operating System:"
cat /etc/rocky-release
echo ""

# Check Python
echo "🐍 Python Version:"
python3 --version
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}' | cut -d. -f1,2)
if [[ "$PYTHON_VERSION" == "3.11" ]]; then
    echo "   ✅ VFX Platform 2024 compliant (3.11.x)"
elif [[ "$PYTHON_VERSION" == "3.9" ]]; then
    echo "   ⚠️  Current: 3.9.x, Target: 3.11.x (optional upgrade)"
else
    echo "   ⚠️  Unexpected version"
fi
echo ""

# Check GCC
echo "🔧 GCC Compiler:"
gcc --version | head -1
echo "   ✅ VFX Platform 2024 requires GCC 11.2.1"
echo ""

# Check installed libraries
echo "📦 Currently Installed VFX Libraries:"
rpm -qa | grep -iE "(openimageio|openexr|imath)" | sort || echo "   (none found via RPM)"
echo ""

# Check missing critical components
echo "❌ Missing Critical Components:"
if ! command -v ociocheck &> /dev/null; then
    echo "   - OpenColorIO 2.3.x (REQUIRED)"
fi
if ! command -v rawtoaces &> /dev/null; then
    echo "   - RAWtoACES (for camera RAW processing)"
fi
if ! command -v xstudio &> /dev/null; then
    echo "   - xstudio (playback/review player)"
fi
echo ""

# Check disk space
echo "💾 Disk Space:"
df -h / | grep -v Filesystem
echo ""
AVAILABLE=$(df / | awk 'NR==2 {print $4}')
if [ "$AVAILABLE" -lt 10485760 ]; then  # 10GB in KB
    echo "   ⚠️  Warning: Less than 10GB available"
    echo "   Recommendation: Free up space before building"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "PHASE 1: INSTALL DEPENDENCIES"
echo "═══════════════════════════════════════════════════════════════"
echo ""

read -p "Install base dependencies? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "📦 Installing development tools..."
    sudo dnf groupinstall -y "Development Tools"

    echo "📦 Installing build tools..."
    sudo dnf install -y cmake ninja-build git

    echo "📦 Installing base libraries..."
    sudo dnf install -y \
        boost-devel \
        tbb-devel \
        libX11-devel \
        libXext-devel \
        qt6-qtbase-devel \
        python3-devel \
        python3-pip \
        zlib-devel \
        libjpeg-turbo-devel \
        libpng-devel \
        libtiff-devel \
        libwebp-devel \
        openexr-devel \
        imath-devel

    echo "✅ Dependencies installed!"
else
    echo "⏭️  Skipping dependency installation"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "PHASE 1: CREATE BUILD DIRECTORY"
echo "═══════════════════════════════════════════════════════════════"
echo ""

BUILD_ROOT="/opt/vfx-platform-2024"

if [ -d "$BUILD_ROOT" ]; then
    echo "⚠️  Build directory already exists: $BUILD_ROOT"
    read -p "Remove and recreate? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo rm -rf "$BUILD_ROOT"
        echo "   Removed existing directory"
    fi
fi

if [ ! -d "$BUILD_ROOT" ]; then
    echo "📁 Creating build directory: $BUILD_ROOT"
    sudo mkdir -p "$BUILD_ROOT"
    sudo chown $USER:$USER "$BUILD_ROOT"
    echo "✅ Build directory created"
fi

# Create subdirectories
mkdir -p "$BUILD_ROOT"/{repos,bin,configs}
echo "✅ Created subdirectories: repos, bin, configs"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "SUMMARY & NEXT STEPS"
echo "═══════════════════════════════════════════════════════════════"
echo ""

cat << EOF
✅ Phase 1 Complete: System prepared for VFX Platform 2024 build

📂 Build Directory: $BUILD_ROOT
   ├── repos/     (source code will be cloned here)
   ├── bin/       (encoding scripts will be installed here)
   └── configs/   (OCIO configs will be stored here)

📋 Next Steps:

1. Read the full implementation plan:
   less $DOC_FILE

2. Start with Phase 2 - OpenColorIO 2.3.x:
   cd $BUILD_ROOT
   git clone https://github.com/AcademySoftwareFoundation/OpenColorIO.git
   cd OpenColorIO
   git checkout RB-2.3
   # (Follow build instructions in the plan)

3. Continue through each phase sequentially:
   - Phase 2: OpenColorIO (2-3 hours) ← START HERE
   - Phase 3: OpenImageIO (3-4 hours)
   - Phase 4: RAWtoACES (2-3 hours)
   - Phase 5: xstudio (3-4 hours)
   - Phase 6: Encoding scripts (1-2 hours)

4. Test each component before proceeding to next phase

⏱️  Estimated Total Time: 16-25 hours (2-3 days)

🆘 Need Help?
   - Review plan: $DOC_FILE
   - ASWF Slack: https://slack.aswf.io/
   - Documentation: https://vfxplatform.com/

Good luck! 🚀
EOF

echo ""
