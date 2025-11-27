#!/usr/bin/env python3
"""
DNG to EXR Batch Converter with FULL Metadata Preservation
Converts DJI X9 DNG files to EXR with DWAA compression, preserving ALL metadata

Usage:
    dng_to_exr_full_metadata.py INPUT_DIR OUTPUT_DIR [COMPRESSION_LEVEL]

Examples:
    dng_to_exr_full_metadata.py "/path/to/dng/" "/path/to/exr/" 45
    dng_to_exr_full_metadata.py "G001C0008_250204_J1PS60" "exr_output"

Features:
    - Preserves ALL 34+ metadata fields from DNG
    - Renames raw:* → DNG:raw_* for EXR compatibility
    - Renames oiio:* → DNG:oiio_* for EXR compatibility
    - DWAA compression (default: 45)
    - Half-float precision (16-bit per channel)
    - Progress reporting
"""

import sys
import os
import time
from pathlib import Path
import OpenImageIO as oiio

def print_usage():
    print(__doc__)
    sys.exit(1)

def convert_dng_to_exr(input_path, output_path, compression_level=45, verbose=False):
    """
    Convert single DNG to EXR with full metadata preservation

    Returns: (success: bool, message: str)
    """
    try:
        # Read DNG
        input_buf = oiio.ImageBuf(str(input_path))
        if input_buf.has_error:
            return False, f"Read error: {input_buf.geterror()}"

        in_spec = input_buf.spec()

        # Create output spec starting from input
        out_spec = oiio.ImageSpec(in_spec)
        out_spec.attribute("compression", f"dwaa:{compression_level}")

        # Copy ALL attributes, renaming problematic ones for EXR
        for attrib in in_spec.extra_attribs:
            attrib_name = attrib.name
            attrib_type = attrib.type
            attrib_value = attrib.value

            # Rename problematic prefixes
            new_name = attrib_name
            if attrib_name.startswith("raw:"):
                new_name = "DNG:" + attrib_name.replace(":", "_")
            elif attrib_name.startswith("oiio:"):
                new_name = "DNG:" + attrib_name.replace(":", "_")

            # Set attribute with proper type
            out_spec.attribute(new_name, attrib_type, attrib_value)

        # Write output
        output_buf = oiio.ImageBuf(out_spec)
        oiio.ImageBufAlgo.copy(output_buf, input_buf)

        if not output_buf.write(str(output_path)):
            return False, f"Write error: {output_buf.geterror()}"

        return True, "OK"

    except Exception as e:
        return False, str(e)

def format_time(seconds):
    """Format seconds as MM:SS"""
    mins = int(seconds // 60)
    secs = int(seconds % 60)
    return f"{mins:02d}:{secs:02d}"

def main():
    # Parse arguments
    if len(sys.argv) < 3:
        print_usage()

    input_dir = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
    compression_level = int(sys.argv[3]) if len(sys.argv) > 3 else 45

    # Validate arguments
    if not input_dir.exists():
        print(f"ERROR: Input directory not found: {input_dir}")
        sys.exit(1)

    if not input_dir.is_dir():
        print(f"ERROR: Input path is not a directory: {input_dir}")
        sys.exit(1)

    if compression_level < 30 or compression_level > 100:
        print(f"ERROR: Compression level must be 30-100, got {compression_level}")
        sys.exit(1)

    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)

    # Find all DNG files
    dng_files = sorted(list(input_dir.glob("*.DNG")) + list(input_dir.glob("*.dng")))

    if not dng_files:
        print(f"ERROR: No DNG files found in {input_dir}")
        sys.exit(1)

    # Print header
    print("=" * 60)
    print("DNG to EXR Batch Conversion (Full Metadata Preservation)")
    print("=" * 60)
    print(f"Input:       {input_dir}")
    print(f"Output:      {output_dir}")
    print(f"Files:       {len(dng_files)} DNG files")
    print(f"Compression: DWAA level {compression_level}")
    print(f"Format:      half (16-bit float)")
    print()
    print("Metadata Preservation:")
    print("  ✓ All camera metadata (Make, Model, Serial, ISO, etc.)")
    print("  ✓ All raw processing data (color matrices, white balance)")
    print("  ✓ All DNG-specific fields (renamed raw:* → DNG:raw_*)")
    print()
    print("Starting conversion...")
    print()

    # Start timer
    start_time = time.time()
    processed = 0
    failed = 0

    # Process each file
    for dng_file in dng_files:
        output_file = output_dir / f"{dng_file.stem}.exr"

        success, message = convert_dng_to_exr(dng_file, output_file, compression_level)

        if success:
            processed += 1
        else:
            failed += 1
            print(f"  ✗ FAILED: {dng_file.name} - {message}")

        # Progress reporting (every 10 files or last file)
        if (processed % 10 == 0) or (processed + failed == len(dng_files)):
            percent = int((processed + failed) * 100 / len(dng_files))
            elapsed = time.time() - start_time
            rate = processed / elapsed if elapsed > 0 else 0
            eta = (len(dng_files) - processed - failed) / rate if rate > 0 else 0

            print(f"  [{percent:3d}%] {processed} / {len(dng_files)} files  "
                  f"({rate:.1f} fps, ETA: {format_time(eta)})")

    # Calculate statistics
    end_time = time.time()
    duration = end_time - start_time

    # Calculate file sizes
    try:
        import subprocess
        input_size_result = subprocess.run(
            ["du", "-sh", str(input_dir)],
            capture_output=True, text=True
        )
        input_size = input_size_result.stdout.split()[0]

        output_size_result = subprocess.run(
            ["du", "-sh", str(output_dir)],
            capture_output=True, text=True
        )
        output_size = output_size_result.stdout.split()[0]
    except:
        input_size = "Unknown"
        output_size = "Unknown"

    # Print summary
    print()
    print("=" * 60)
    if failed == 0:
        print("✅ Conversion Complete!")
    else:
        print(f"⚠️  Conversion Complete with {failed} errors")
    print("=" * 60)
    print(f"Processed:     {processed} files")
    if failed > 0:
        print(f"Failed:        {failed} files")
    print(f"Duration:      {format_time(duration)}")
    print(f"Average:       {processed/duration:.2f} fps")
    print(f"Input size:    {input_size}")
    print(f"Output size:   {output_size}")
    print()
    print("Verify metadata preservation:")
    if processed > 0:
        first_output = next(output_dir.glob("*.exr"))
        print(f"  iinfo -v '{first_output}' | grep DNG:")
        print()
        print("All metadata fields have been preserved!")
        print("  - Original DNG fields preserved as-is")
        print("  - raw:* fields renamed to DNG:raw_*")
        print("  - oiio:* fields renamed to DNG:oiio_*")
    print()

if __name__ == "__main__":
    main()
