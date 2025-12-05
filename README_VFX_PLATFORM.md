# VFX Reference Platform 2024 Build Tools

Build scripts and encoding tools for VFX Reference Platform CY2024 compliance.

## Components Installed

| Component | Version | Purpose |
|-----------|---------|---------|
| OpenColorIO | 2.3.2 | Color management with built-in ACES 1.3 configs |
| OpenImageIO | 2.5.16 | Image I/O with OCIO integration |
| RAWtoACES | 2.0 | Camera RAW to ACES conversion |
| Encoding Scripts | Custom | EXR to ProRes/H.264 workflows |

## Quick Start

### Ubuntu 24.04

```bash
# Copy build script to target machine
scp vfx_platform_2024_ubuntu_build.sh user@machine:/opt/vfx-platform-2024/

# Run the build (skip xstudio to save 2-3 hours)
sudo bash /opt/vfx-platform-2024/vfx_platform_2024_ubuntu_build.sh --skip-xstudio

# Activate environment
source /etc/profile.d/vfx-platform-2024.sh
```

### Rocky Linux 9.x

See `docs/archive/sessions/VFX_PLATFORM_2024_IMPLEMENTATION.md` for manual build instructions.

## Encoding Scripts

After installation, these scripts are available in `/opt/vfx-platform-2024/bin/`:

### Client Review (ACES -> sRGB H.264)
```bash
exr_to_h264_srgb.sh render/shot.%04d.exr output.mp4 24
```

### Editorial Delivery (ACES -> LogC4 ProRes)
```bash
exr_to_prores_logc4.sh render/shot.%04d.exr output.mov 24
```

### Batch Encode Directory
```bash
batch_encode_exr.sh /path/to/renders/ /path/to/output/ h264
```

## Directory Structure

```
vfx_platform_2024/
├── README.md                           # This file
├── README_UBUNTU.md                    # Ubuntu-specific notes
├── vfx_platform_2024_ubuntu_build.sh   # Ubuntu 24.04 master build script
└── bin/
    ├── exr_to_h264_srgb.sh             # Client review encodes
    ├── exr_to_prores_logc4.sh          # Editorial delivery encodes
    └── batch_encode_exr.sh             # Batch encoding wrapper
```

## Build Time Estimates

| Phase | Component | Time |
|-------|-----------|------|
| 1 | Dependencies | ~10 min |
| 2 | OpenColorIO 2.3.x | ~45 min |
| 3 | OpenImageIO 2.5.x | ~90 min |
| 4 | RAWtoACES | ~30 min |
| 5 | Encoding Scripts | ~5 min |
| 6 | xstudio (optional) | ~2-3 hours |
| 7 | Environment Setup | ~5 min |
| **Total** | **Without xstudio** | **~3 hours** |

## Environment Variables

After build, these are set in `/etc/profile.d/vfx-platform-2024.sh`:

```bash
export VFX_PLATFORM_VERSION="2024"
export PATH="/usr/local/bin:/opt/vfx-platform-2024/bin:$PATH"
export LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH:-}"
```

**Note:** OCIO is NOT set globally - it would break Nuke's color management. The encoding scripts set OCIO locally when needed.

## Verification

```bash
# Check versions
oiiotool --version    # Should show 2.5.16
ociocheck             # Should show 2.3.2
rawtoaces --help      # Should show usage info

# Test OCIO
export OCIO="ocio://cg-config-v2.1.0_aces-v1.3_ocio-v2.3"
python3 -c "import PyOpenColorIO as OCIO; print(OCIO.GetVersion())"
```

## Rollout to Other Machines

After successful build on one machine:

```bash
# Package built libraries
cd /usr/local
sudo tar -czvf /opt/vfx-platform-2024/vfx-platform-binaries.tar.gz \
    lib/libOpenColorIO* \
    lib/libOpenImageIO* \
    lib/librawtoaces* \
    bin/oiiotool bin/ocio* bin/iinfo bin/igrep bin/maketx bin/rawtoaces

# Copy to target machine
scp /opt/vfx-platform-2024/vfx-platform-binaries.tar.gz user@machine:/tmp/

# On target: extract and configure
cd /usr/local && sudo tar -xzvf /tmp/vfx-platform-binaries.tar.gz
sudo ldconfig
```

## Resources

- [VFX Reference Platform](https://vfxplatform.com/)
- [OpenColorIO Docs](https://opencolorio.readthedocs.io/)
- [OpenImageIO Docs](https://openimageio.readthedocs.io/)
- [ACES Central](https://community.acescentral.com/)
- [Encoding Best Practices](https://richardssam.github.io/ffmpeg-tests/)

## History

- **2025-12-05**: Ubuntu 24.04 build completed (OpenColorIO 2.3.2, OIIO 2.5.16, RAWtoACES 2.0)
- **2025-11-23**: Rocky Linux 9.6 build started (see archive docs)
