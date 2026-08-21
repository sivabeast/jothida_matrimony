#!/usr/bin/env python3
"""Verify every native library is compatible with Android 16 KB memory pages.

Google Play rejects an app whose shared libraries were linked for 4 KB pages.
The check that actually matters is the **ELF `p_align` of each PT_LOAD segment**:
it must be >= 16384 (0x4000), which is what `readelf -lW` shows as `Align`.
A library linked with NDK r26 or older (or without
`-Wl,-z,max-page-size=16384`) reports 0x1000 and fails on a 16 KB device.

For an AAB/APK there is a second, independent requirement: when the libraries
are stored uncompressed (`useLegacyPackaging = false`, the AGP 8 default), each
`lib/**/*.so` zip entry must START on a 16 KB boundary. AGP 8.5.1+ does that
automatically; this script verifies it anyway rather than trusting it.

Usage:
    python tool/check_16kb_alignment.py <file.so | dir | app.aab | app.apk> ...

Exit code 0 = every library is 16 KB compatible, 1 = at least one is not.
"""
from __future__ import annotations

import os
import struct
import sys
import zipfile

PAGE_16K = 16 * 1024


def load_segment_aligns(data: bytes):
    """Return the p_align of every PT_LOAD segment in an ELF image.

    Raises ValueError when the bytes are not an ELF we understand.
    """
    if len(data) < 64 or data[:4] != b"\x7fELF":
        raise ValueError("not an ELF file")
    ei_class = data[4]  # 1 = 32-bit, 2 = 64-bit
    ei_data = data[5]  # 1 = little endian, 2 = big endian
    endian = "<" if ei_data == 1 else ">"

    if ei_class == 2:  # ELF64
        e_phoff = struct.unpack_from(endian + "Q", data, 0x20)[0]
        e_phentsize = struct.unpack_from(endian + "H", data, 0x36)[0]
        e_phnum = struct.unpack_from(endian + "H", data, 0x38)[0]
        p_type_off, p_align_off, fmt = 0x00, 0x30, endian + "Q"
    elif ei_class == 1:  # ELF32
        e_phoff = struct.unpack_from(endian + "I", data, 0x1C)[0]
        e_phentsize = struct.unpack_from(endian + "H", data, 0x2A)[0]
        e_phnum = struct.unpack_from(endian + "H", data, 0x2C)[0]
        p_type_off, p_align_off, fmt = 0x00, 0x1C, endian + "I"
    else:
        raise ValueError("unknown ELF class %r" % ei_class)

    aligns = []
    for i in range(e_phnum):
        base = e_phoff + i * e_phentsize
        if base + e_phentsize > len(data):
            break
        p_type = struct.unpack_from(endian + "I", data, base + p_type_off)[0]
        if p_type != 1:  # PT_LOAD
            continue
        aligns.append(struct.unpack_from(fmt, data, base + p_align_off)[0])
    return aligns


def check_elf(name: str, data: bytes, failures: list):
    try:
        aligns = load_segment_aligns(data)
    except ValueError as e:
        print("  ?  %-56s (%s)" % (name, e))
        return
    if not aligns:
        print("  ?  %-56s no PT_LOAD segments" % name)
        return
    worst = min(aligns)
    ok = worst >= PAGE_16K
    print("  %s %-56s p_align=0x%x" % ("OK " if ok else "BAD", name, worst))
    if not ok:
        failures.append("%s (p_align=0x%x, needs >=0x4000)" % (name, worst))


def check_archive(path: str, failures: list):
    """Check the ELF alignment of every lib/**/*.so plus, when the entry is
    stored uncompressed, its 16 KB offset alignment inside the zip."""
    print("\n== %s" % path)
    with zipfile.ZipFile(path) as z:
        entries = [i for i in z.infolist() if i.filename.endswith(".so")]
        if not entries:
            print("  (no .so entries)")
            return
        for info in entries:
            check_elf(info.filename, z.read(info.filename), failures)
            if info.compress_type == zipfile.ZIP_STORED:
                # header_offset points at the local header; the payload starts
                # after it, so compute the real data offset.
                with open(path, "rb") as fh:
                    fh.seek(info.header_offset + 26)
                    n, m = struct.unpack("<HH", fh.read(4))
                data_off = info.header_offset + 30 + n + m
                if data_off % PAGE_16K != 0:
                    msg = ("%s stored uncompressed at zip offset %d, which is "
                           "not a 16 KB boundary" % (info.filename, data_off))
                    print("  BAD %s" % msg)
                    failures.append(msg)


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    failures: list = []
    checked = 0
    for target in argv:
        if not os.path.exists(target):
            # A missing artifact means the build did not produce what we are
            # supposed to be gating on — that is a failure, not a skip.
            print("\n== %s\n  BAD file not found" % target)
            failures.append("%s does not exist" % target)
            checked += 1
        elif os.path.isdir(target):
            print("\n== %s" % target)
            for root, _dirs, files in os.walk(target):
                for f in sorted(files):
                    if f.endswith(".so"):
                        p = os.path.join(root, f)
                        with open(p, "rb") as fh:
                            check_elf(os.path.relpath(p, target), fh.read(),
                                      failures)
                        checked += 1
        elif target.endswith((".aab", ".apk", ".zip")):
            check_archive(target, failures)
            checked += 1
        else:
            print("\n== %s" % target)
            with open(target, "rb") as fh:
                check_elf(os.path.basename(target), fh.read(), failures)
            checked += 1

    print("")
    if failures:
        print("FAIL - %d native library problem(s) for 16 KB page sizes:"
              % len(failures))
        for f in failures:
            print("  - %s" % f)
        return 1
    if checked == 0:
        print("FAIL - nothing was checked (bad path?)")
        return 1
    print("PASS - every native library is 16 KB page-size compatible.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
