#!/usr/bin/env python3
"""Check arm64 payload placement and static DT memory reservations (no device I/O)."""
import argparse
import os
import pathlib
import re
import struct
import subprocess


def prop(dtb, node, name, kind="x"):
    result = subprocess.run(["fdtget", "-t" + kind, str(dtb), node, name],
                            capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def children(dtb, node):
    return subprocess.check_output(["fdtget", "-l", str(dtb), node], text=True).split()


def ranges(dtb, node):
    value = prop(dtb, node, "reg")
    if value is None:
        return []
    cells = [int(c, 16) for c in value.split()]
    if len(cells) % 4:
        raise ValueError(f"Expected 2 address + 2 size cells: {node}")
    return [(cells[i] << 32 | cells[i + 1], cells[i + 2] << 32 | cells[i + 3])
            for i in range(0, len(cells), 4)]


def reservations(dtb):
    return [(node, start, size)
            for name in children(dtb, "/reserved-memory")
            for node in ["/reserved-memory/" + name]
            if prop(dtb, node, "status", "s") in (None, "ok", "okay")
            for start, size in ranges(dtb, node) if size]


def uncovered(start, size, cover):
    end = start + size
    for a, n in sorted(cover):
        if a > start:
            yield start, min(a, end) - start
        start = max(start, min(a + n, end)) if a <= end else end
        if start >= end:
            return
    if start < end:
        yield start, end - start


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dtb", type=pathlib.Path, required=True)
    parser.add_argument("--stock", type=pathlib.Path)
    parser.add_argument("--kernel", type=pathlib.Path, required=True)
    parser.add_argument("--ramdisk", type=pathlib.Path, required=True)
    parser.add_argument("--loader-config", type=pathlib.Path, required=True)
    parser.add_argument("--loader-elf", type=pathlib.Path)
    args = parser.parse_args()
    config = dict(re.findall(r"^(CONFIG_\w+)=(\S+)",
                             args.loader_config.read_text(), re.M))
    kernel = int(config["CONFIG_PAYLOAD_ENTRY"], 0)
    initrd = int(config["CONFIG_RAMDISK_ENTRY"], 0)
    with args.kernel.open("rb") as stream:
        header = stream.read(64)
    if len(header) != 64 or header[56:60] != b"ARM\x64":
        raise ValueError("Payload must be an uncompressed arm64 Image")
    offset, image_size = struct.unpack_from("<QQ", header, 8)
    if not image_size:
        raise ValueError("Legacy zero image_size not supported")
    ram = [r for name in children(args.dtb, "/")
           if prop(args.dtb, "/" + name, "device_type", "s") == "memory"
           for r in ranges(args.dtb, "/" + name)]
    reserved = reservations(args.dtb)
    errors = []
    if (kernel - offset) % (2 << 20):
        errors.append(f"kernel {kernel:#x} minus text_offset {offset:#x} is not 2 MiB aligned")
    payloads = [("kernel", kernel, max(image_size, args.kernel.stat().st_size)),
                ("initramfs", initrd, args.ramdisk.stat().st_size)]
    for label, start, size in payloads:
        print(f"{label}: [{start:#x}, {start + size:#x})")
        if list(uncovered(start, size, ram)):
            errors.append(f"{label} is outside declared RAM")
        for node, a, n in reserved:
            if start < a + n and a < start + size:
                errors.append(f"{label} overlaps {node}")
    _, a, n = payloads[0]
    _, b, m = payloads[1]
    if a < b + m and b < a + n:
        errors.append("kernel and initramfs overlap")
    window_start = min(a, b) & ~((1 << 30) - 1)
    if max(a + n, b + m) - window_start > 32 << 30:
        errors.append("kernel/initramfs exceed the arm64 32 GiB window")
    if args.loader_elf:
        output = subprocess.check_output(
            [os.environ.get("NM", "aarch64-linux-gnu-nm"), "-n", str(args.loader_elf)], text=True)
        symbols = {name: int(addr, 16) for addr, name in
                   re.findall(r"^([0-9a-f]+)\s+\w\s+(\S+)$", output, re.M)}
        # reloc.S copies _reloc_size bytes starting at _start (past _head).
        start, size = symbols["_start"], symbols["_reloc_size"]
        print(f"uniLoader relocation: [{start:#x}, {start + size:#x})")
        if list(uncovered(start, size, ram)):
            errors.append("uniLoader relocation is outside declared RAM")
        for node, a, n in reserved:
            if start < a + n and a < start + size:
                errors.append(f"uniLoader relocation overlaps {node}")
        for label, a, n in payloads:
            if start < a + n and a < start + size:
                errors.append(f"uniLoader relocation overlaps {label}")
        if symbols["fdt_buf"] % 8:
            errors.append("uniLoader FDT buffer is not 8-byte aligned")
    if args.stock:
        coverage = [(a, n) for _, a, n in reserved]
        for node, start, size in reservations(args.stock):
            for a, n in uncovered(start, size, coverage):
                # Only ranges advertised as usable RAM can be allocated by Linux.
                for b, m in ram:
                    lo, hi = max(a, b), min(a + n, b + m)
                    if lo < hi:
                        errors.append(f"stock reservation {node}: [{lo:#x}, {hi:#x}) exposed as RAM")
    for error in errors:
        print("FAIL:", error)
    print("Static layout:", "FAIL" if errors else "PASS")
    print("RAM bank population and ABL runtime placement still require device verification.")
    raise SystemExit(bool(errors))


if __name__ == "__main__":
    main()
