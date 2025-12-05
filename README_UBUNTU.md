# VFX Reference Platform 2024 - Ubuntu 24.04 Build

**Date**: 2025-12-05
**Platform**: Ubuntu 24.04 LTS (Noble Numbat) / Ubuntu Studio
**Target**: VFX Reference Platform CY2024 Compliance

---

## Quick Start

```bash
# Run the master build script (skip xstudio to save 2-3 hours)
sudo bash /opt/vfx-platform-2024/vfx_platform_2024_ubuntu_build.sh --skip-xstudio

# Or build everything including xstudio:
sudo bash /opt/vfx-platform-2024/vfx_platform_2024_ubuntu_build.sh
```

**Estimated time**: 8-12 hours (mostly unattended)

---

## What Gets Installed

| Component | Version | Purpose |
|-----------|---------|---------|
| OpenColorIO | 2.3.2 | Color management, built-in ACES 1.3 configs |
| OpenImageIO | 2.5.16 | Image I/O with OCIO integration |
| RAWtoACES | Latest | Camera RAW to ACES conversion |
| Encoding Scripts | Custom | EXR to ProRes/H.264 workflows |
| xstudio | Latest | Review/playback (optional) |

---

## Ubuntu 24.04 vs Rocky Linux 9.6

| Difference | Rocky (dnf) | Ubuntu (apt) |
|------------|-------------|--------------|
| Package manager | `dnf install` | `apt-get install` |
| Python version | 3.9 | 3.12 (better) |
| GCC version | 11 | 13 (newer) |
| Pre-installed OCIO | None | 2.1.3 (older) |
| Pre-installed OIIO | 2.4.17 | 2.4.17 (same) |

Ubuntu has better Python/GCC but needs the same source builds for full VFX 2024 compliance.

---

## Build Phases

1. **Dependencies** (~10 min) - Install Ubuntu packages
2. **OpenColorIO 2.3.x** (~45 min) - Color management foundation
3. **OpenImageIO 2.5.x** (~90 min) - Image processing with OCIO
4. **RAWtoACES** (~30 min) - Camera RAW workflows
5. **Encoding Scripts** (~5 min) - Production encode tools
6. **xstudio** (~2-3 hours) - Review player (optional)
7. **Environment Setup** (~5 min) - PATH, OCIO, etc.

---

## After Build

```bash
# Activate environment (or just log out/in)
source /etc/profile.d/vfx-platform-2024.sh

# Verify
oiiotool --version
ociocheck
echo $OCIO
```

---

## Encoding Scripts Installed

```bash
# Client review (ACES -> sRGB H.264)
exr_to_h264_srgb.sh render/shot.%04d.exr output.mp4 24

# Editorial delivery (ACES -> LogC4 ProRes)
exr_to_prores_logc4.sh render/shot.%04d.exr output.mov 24

# Batch encode directory
batch_encode_exr.sh /path/to/renders/ /path/to/output/ h264
```

---

## Troubleshooting

### Build fails on a dependency
```bash
# Check the log
cat /opt/vfx-platform-2024/build.log

# Re-run specific phase manually if needed
cd /opt/vfx-platform-2024/src/OpenColorIO/build
ninja -j$(nproc)
sudo ninja install
```

### Library not found errors
```bash
sudo ldconfig
export LD_LIBRARY_PATH="/usr/local/lib:$LD_LIBRARY_PATH"
```

### Python can't import PyOpenColorIO
```bash
export PYTHONPATH="/usr/local/lib/python3/dist-packages:$PYTHONPATH"
python3 -c "import PyOpenColorIO; print(PyOpenColorIO.GetVersion())"
```

---

## Files

| File | Purpose |
|------|---------|
| `/opt/vfx-platform-2024/vfx_platform_2024_ubuntu_build.sh` | Master build script |
| `/opt/vfx-platform-2024/build.log` | Build log |
| `/opt/vfx-platform-2024/bin/` | Encoding scripts |
| `/etc/profile.d/vfx-platform-2024.sh` | Environment setup |

---

## Rollout to Other Ubuntu Machines

After successful build, create a tarball of built binaries:

```bash
# Package the built libraries and tools
cd /usr/local
sudo tar -czvf /opt/vfx-platform-2024/vfx-platform-2024-ubuntu-binaries.tar.gz \
    lib/libOpenColorIO* \
    lib/libOpenImageIO* \
    bin/oiiotool \
    bin/ocio* \
    bin/iinfo \
    bin/igrep \
    bin/maketx

# Copy to other machines
scp /opt/vfx-platform-2024/vfx-platform-2024-ubuntu-binaries.tar.gz user@machine2:/tmp/

# On target machine:
cd /usr/local
sudo tar -xzvf /tmp/vfx-platform-2024-ubuntu-binaries.tar.gz
sudo ldconfig
```

---

## Support

- Build log: `/opt/vfx-platform-2024/build.log`
- ASWF Slack: https://slack.aswf.io/
- OpenColorIO: https://opencolorio.readthedocs.io/
- OpenImageIO: https://openimageio.readthedocs.io/
