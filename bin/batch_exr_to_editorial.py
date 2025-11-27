#!/usr/bin/env python3
"""
batch_exr_to_editorial.py - Batch convert ACES EXR sequences to editorial MOVs

Pipeline: ACES2065-1 → ARRI LogC4 → Show LUT → Rec709 Gamma2.4 → DNxHR SQ

Usage:
    python3 batch_exr_to_editorial.py /path/to/renders/ [--output-dir /path/to/editorial/]
    python3 batch_exr_to_editorial.py /path/to/renders/ --dry-run
    python3 batch_exr_to_editorial.py /path/to/renders/ --shot ACD1000

Examples:
    # Process all shots in renders directory
    python3 batch_exr_to_editorial.py /Volumes/soupnas_02/Soupkitchen_Jobs/MNG/renders/comps/

    # Output to specific directory
    python3 batch_exr_to_editorial.py /renders/ --output-dir /editorial/

    # Process specific shot only
    python3 batch_exr_to_editorial.py /renders/ --shot ACD1000

Requirements:
    - OpenImageIO (oiiotool) with OCIO support
    - FFmpeg with DNxHD encoder
    - OCIO 2.3+ with built-in ACES configs
"""

import os
import re
import sys
import argparse
import subprocess
import tempfile
import shutil
from pathlib import Path
from typing import Optional, List, Dict, Tuple

# =============================================================================
# Configuration
# =============================================================================

# Show LUT path (LogC4 → Rec709 Gamma 2.4)
DEFAULT_LUT = "/Volumes/soupnas_02/Soupkitchen_Jobs/MNG/LUTS/v4_LUTs/v4_LUTs/post/mon_show_v4_logc4-r709g24_d65_33.cube"

# OCIO config (Studio config includes camera input transforms like ARRI LogC4)
OCIO_CONFIG = "ocio://studio-config-v2.1.0_aces-v1.3_ocio-v2.3"

# DNxHR profile
DNXHR_PROFILE = "dnxhr_sq"

# Default FPS
DEFAULT_FPS = 24

# IMPORTANT: Always start at frame 1000 (slate frame)
SLATE_FRAME = 1000


# =============================================================================
# Sequence Detection
# =============================================================================

def detect_sequence_padding(filename: str) -> Tuple[Optional[int], Optional[str]]:
    """Detect frame padding from filename, return (padding_length, extension)."""
    match = re.search(r'(\d+)(\.[^.]+)$', filename)
    if match:
        digits = match.group(1)
        ext = match.group(2)
        return len(digits), ext
    return None, None


def find_exr_sequences(root_dir: str, shot_filter: Optional[str] = None) -> List[Dict]:
    """
    Find EXR sequences in directory.
    Returns list of dicts with: dir, head, ext, pad, start, end, count
    """
    sequences = []

    for dirpath, _, files in os.walk(root_dir):
        candidates = {}

        for f in files:
            if not f.endswith('.exr'):
                continue

            # Optional shot filter
            if shot_filter and shot_filter not in f:
                continue

            pad, ext = detect_sequence_padding(f)
            if pad is None:
                continue

            # Extract head (everything before frame number)
            head = re.sub(r'\d+(\.[^.]+)$', '', f)
            key = (head, ext, pad)
            candidates.setdefault(key, []).append(f)

        for (head, ext, pad), seq_files in candidates.items():
            seq_files.sort()

            # Extract frame numbers
            start_match = re.search(r'(\d+)\.[^.]+$', seq_files[0])
            end_match = re.search(r'(\d+)\.[^.]+$', seq_files[-1])

            if not start_match or not end_match:
                continue

            sequences.append({
                "dir": Path(dirpath),
                "head": head,
                "ext": ext,
                "pad": pad,
                "start": int(start_match.group(1)),
                "end": int(end_match.group(1)),
                "count": len(seq_files),
            })

    return sequences


def frame_to_timecode(frame: int, fps: int = 24) -> str:
    """Convert frame number to timecode string."""
    hours = frame // (fps * 3600)
    mins = (frame % (fps * 3600)) // (fps * 60)
    secs = (frame % (fps * 60)) // fps
    frames = frame % fps
    return f"{hours:02d}:{mins:02d}:{secs:02d}:{frames:02d}"


def get_exr_timecode(exr_path: str) -> Optional[str]:
    """Try to extract timecode from EXR metadata using iinfo."""
    try:
        result = subprocess.run(
            ['iinfo', '-v', exr_path],
            capture_output=True, text=True, timeout=10
        )
        match = re.search(r'timecode[:\s]+"?(\d{2}:\d{2}:\d{2}[:;]\d{2})"?',
                         result.stdout, re.IGNORECASE)
        if match:
            return match.group(1).strip('"')
    except Exception:
        pass
    return None


# =============================================================================
# Encoding
# =============================================================================

def encode_sequence(
    seq_info: Dict,
    output_path: str,
    lut_path: str,
    fps: int = 24,
    dry_run: bool = False
) -> bool:
    """
    Encode a single EXR sequence to editorial MOV.

    Pipeline: ACES2065-1 → LogC4 → LUT → Rec709 g2.4 → DNxHR SQ

    IMPORTANT: Always starts at frame 1000 (slate frame). Errors if missing.
    """
    # Build input pattern
    frame_pattern = f"%0{seq_info['pad']}d{seq_info['ext']}"
    input_pattern = str(seq_info['dir'] / f"{seq_info['head']}{frame_pattern}")

    # Check slate frame (1000) exists - REQUIRED
    slate_frame_path = str(seq_info['dir'] / f"{seq_info['head']}{SLATE_FRAME:0{seq_info['pad']}d}{seq_info['ext']}")
    if not os.path.exists(slate_frame_path):
        print(f"\n{'='*60}")
        print(f"SKIPPING: {seq_info['head'].rstrip('.')}")
        print(f"  ERROR: Slate frame (1000) not found: {slate_frame_path}")
        print(f"  Editorial MOVs must include the slate frame.")
        return False

    # Always start at frame 1000 (slate)
    start_frame = SLATE_FRAME

    # Get or calculate timecode from frame 1000
    tc = get_exr_timecode(slate_frame_path)
    if not tc:
        tc = frame_to_timecode(start_frame, fps)

    print(f"\n{'='*60}")
    print(f"Encoding: {seq_info['head'].rstrip('.')}")
    print(f"  Input:  {input_pattern}")
    print(f"  Output: {output_path}")
    print(f"  Frames: {start_frame}-{seq_info['end']} (starting from slate)")
    print(f"  TC:     {tc}")

    if dry_run:
        print("  [DRY RUN] Skipping encode")
        return True

    # Create temp directory (use /mnt/caches for large intermediates)
    # Global cache location - exists on all render machines including Deadline workers
    temp_base = "/mnt/caches/cache_ffmpeg"
    os.makedirs(temp_base, exist_ok=True)
    temp_dir = tempfile.mkdtemp(prefix="editorial_encode_", dir=temp_base)

    try:
        # Set OCIO environment
        env = os.environ.copy()
        env['OCIO'] = OCIO_CONFIG

        # Step 1: Color convert with oiiotool
        print("  [1/2] Color: ACES2065-1 → LogC4 → LUT...")

        oiio_cmd = [
            'oiiotool',
            input_pattern,
            '--colorconvert', 'ACES2065-1', 'ARRI LogC4',
            '--ociofiletransform', lut_path,
            '-d', 'uint16',
            '-o', f"{temp_dir}/graded.%04d.png"
        ]

        result = subprocess.run(oiio_cmd, env=env, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"  ERROR: oiiotool failed: {result.stderr}")
            return False

        # Step 2: Encode with FFmpeg
        print("  [2/2] Encoding DNxHR SQ...")

        # Create output directory
        os.makedirs(os.path.dirname(output_path), exist_ok=True)

        # Extract metadata for burn-ins
        # Shot ID is first part before _SUP_ or _CMP_
        full_name = seq_info['head'].rstrip('.').rstrip('_')
        shot_id = re.sub(r'_SUP.*|_CMP.*', '', full_name)
        video_filename = os.path.basename(output_path)
        submit_date = subprocess.run(['date', '+%Y%m%d'], capture_output=True, text=True).stdout.strip()
        vendor_name = "soup kitchen films"

        # Build filter: scale, crop, letterbox, burn-ins
        letterbox_h = 35
        vf = f"scale=1920:-1,crop=1920:1080"
        vf += f",drawbox=x=0:y=0:w=1920:h={letterbox_h}:color=black@0.5:t=fill"
        vf += f",drawbox=x=0:y=ih-{letterbox_h}:w=1920:h={letterbox_h}:color=black@0.5:t=fill"
        vf += f",drawtext=text='{vendor_name}':fontsize=18:fontcolor=white:x=10:y=8"
        vf += f",drawtext=text='{shot_id}':fontsize=18:fontcolor=white:x=(w-text_w)/2:y=8"
        vf += f",drawtext=text='{submit_date}':fontsize=18:fontcolor=white:x=w-text_w-10:y=8"
        vf += f",drawtext=text='{video_filename}':fontsize=18:fontcolor=white:x=10:y=h-text_h-8"
        vf += f",drawtext=text='%{{frame_num}}':start_number={start_frame}:fontsize=18:fontcolor=white:x=w-text_w-10:y=h-text_h-8"

        ffmpeg_cmd = [
            'ffmpeg', '-y',
            '-threads', '0',
            '-framerate', str(fps),
            '-start_number', str(start_frame),
            '-i', f"{temp_dir}/graded.%04d.png",
            '-filter_threads', '0',
            '-vf', vf,
            '-c:v', 'dnxhd',
            '-threads', '0',
            '-profile:v', DNXHR_PROFILE,
            '-pix_fmt', 'yuv422p',
            '-timecode', tc,
            '-color_primaries', 'bt709',
            '-color_trc', 'bt709',
            '-colorspace', 'bt709',
            '-movflags', '+faststart',
            output_path
        ]

        result = subprocess.run(ffmpeg_cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"  ERROR: ffmpeg failed: {result.stderr}")
            return False

        # Success
        if os.path.exists(output_path):
            size_mb = os.path.getsize(output_path) / (1024 * 1024)
            print(f"  SUCCESS: {output_path} ({size_mb:.1f} MB)")
            return True
        else:
            print(f"  ERROR: Output not created")
            return False

    finally:
        # Cleanup temp directory
        shutil.rmtree(temp_dir, ignore_errors=True)


# =============================================================================
# Main
# =============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Batch convert ACES EXR sequences to editorial DNxHR MOVs"
    )
    parser.add_argument("input_dir", help="Directory containing EXR sequences")
    parser.add_argument("--output-dir", "-o",
                        help="Output directory (default: input_dir/editorial/)")
    parser.add_argument("--shot", "-s",
                        help="Process only sequences containing this string")
    parser.add_argument("--lut", default=DEFAULT_LUT,
                        help=f"LUT file path (default: {DEFAULT_LUT})")
    parser.add_argument("--fps", type=int, default=DEFAULT_FPS,
                        help=f"Frame rate (default: {DEFAULT_FPS})")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be processed without encoding")

    args = parser.parse_args()

    # Validate input directory
    if not os.path.isdir(args.input_dir):
        print(f"ERROR: Input directory not found: {args.input_dir}")
        return 1

    # Validate LUT
    if not args.dry_run and not os.path.isfile(args.lut):
        print(f"ERROR: LUT not found: {args.lut}")
        return 1

    # Set output directory
    output_dir = args.output_dir or os.path.join(args.input_dir, "editorial")

    print("="*60)
    print("Batch EXR to Editorial MOV Converter")
    print("="*60)
    print(f"Input:  {args.input_dir}")
    print(f"Output: {output_dir}")
    print(f"LUT:    {os.path.basename(args.lut)}")
    print(f"FPS:    {args.fps}")
    if args.shot:
        print(f"Filter: {args.shot}")
    if args.dry_run:
        print("Mode:   DRY RUN")

    # Find sequences
    print("\nScanning for EXR sequences...")
    sequences = find_exr_sequences(args.input_dir, args.shot)

    if not sequences:
        print("No EXR sequences found.")
        return 0

    print(f"Found {len(sequences)} sequence(s)")

    # Process each sequence
    success_count = 0
    fail_count = 0

    for seq in sequences:
        # Build output filename
        shot_name = seq['head'].rstrip('.').rstrip('_')
        output_path = os.path.join(output_dir, f"{shot_name}.mov")

        if encode_sequence(seq, output_path, args.lut, args.fps, args.dry_run):
            success_count += 1
        else:
            fail_count += 1

    # Summary
    print(f"\n{'='*60}")
    print(f"Summary: {success_count} succeeded, {fail_count} failed")
    print("="*60)

    return 0 if fail_count == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
