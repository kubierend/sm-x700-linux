#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Point one board name in an ath11k board-2.bin at a different BDF.

The SM-X700's 5 GHz Wi-Fi needs Samsung's board data (bdwlang.elf from the stock
vendor partition, /vendor/firmware/qca6490/) together with Samsung's matching
firmware. This rewrites the upstream linux-firmware WCN6855 board-2.bin so the entry
the chip asks for (17cb:0108, chip 18, board 255) carries that BDF; every other entry
is kept.

    mk-ath11k-board2.py UPSTREAM_board-2.bin[.zst] bdwlang.elf OUT_board-2.bin
"""
import struct
import subprocess
import sys

MAGIC = b"QCA-ATH11K-BOARD\0"
IE_BOARD, IE_NAME, IE_DATA = 0, 0, 1
NAME = (b"bus=pci,vendor=17cb,device=1103,subsystem-vendor=17cb,subsystem-device=0108,"
        b"qmi-chip-id=18,qmi-board-id=255")


def pad4(n):
    return (n + 3) & ~3


def ies(buf):
    """Yield (id, payload, raw bytes incl. header and padding) for each IE."""
    off = 0
    while off < len(buf):
        ie_id, ie_len = struct.unpack_from("<II", buf, off)
        end = off + 8 + pad4(ie_len)
        yield ie_id, buf[off + 8:off + 8 + ie_len], buf[off:end]
        off = end


def ie(ie_id, data):
    return struct.pack("<II", ie_id, len(data)) + data + b"\0" * (pad4(len(data)) - len(data))


def main(src, bdf, out):
    raw = open(src, "rb").read()
    if src.endswith(".zst"):
        raw = subprocess.run(["zstd", "-dc"], input=raw, check=True, capture_output=True).stdout
    hdr = pad4(len(MAGIC))
    if raw[:len(MAGIC)] != MAGIC:
        sys.exit("not an ath11k board-2.bin")
    new_bdf = open(bdf, "rb").read()
    body, hits = b"", 0
    for top_id, top, top_raw in ies(raw[hdr:]):
        subs = list(ies(top)) if top_id == IE_BOARD else []
        if any(i == IE_NAME and d == NAME for i, d, _ in subs):
            # only the rewritten entry is re-encoded; everything else is copied verbatim
            top_raw = ie(top_id, b"".join(ie(i, new_bdf if i == IE_DATA else d) for i, d, _ in subs))
            hits += 1
        body += top_raw
    if hits != 1:
        sys.exit(f"expected exactly one '{NAME.decode()}' entry, found {hits}")
    open(out, "wb").write(raw[:hdr] + body)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
