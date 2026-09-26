#!/usr/bin/env bash
# Build the boot initramfs: a stock postmarketOS initramfs (the mkinitfs output) followed by
# one gzip'd cpio archive per extra tree. The kernel unpacks concatenated archives in order,
# so nothing has to be repacked and the base stays untouched.
#
#   assemble-initramfs.sh --base pmos-initramfs --out initramfs.cpio.gz TREE [TREE...]
#
# TREE: a directory whose contents are extracted at the initramfs root, e.g. the
# gpu/ audio/ sensors/ trees from stage-firmware.sh, or initramfs-extras/usb-debug-tree
# (optional debug hook).
set -euo pipefail
base= out=
while [ $# -gt 0 ]; do
    case $1 in --base) base=$2; shift 2;; --out) out=$2; shift 2;; --) shift; break;; -*) echo "unknown option $1" >&2; exit 2;; *) break;; esac
done
[ -f "$base" ] && [ -n "$out" ] && [ $# -gt 0 ] || { sed -n 2,11p "$0"; exit 2; }
cp "$base" "$out"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for tree in "$@"; do
    [ -d "$tree" ] || { echo "not a directory: $tree" >&2; exit 2; }
    # cpio records mtimes: pin them so the same inputs always give the same initramfs
    rm -rf "$tmp/t"; cp -a "$tree" "$tmp/t"
    find "$tmp/t" -exec touch -h -d @"${SOURCE_DATE_EPOCH:-0}" {} +
    ( cd "$tmp/t" && find . -mindepth 1 | sed 's#^\./##' | LC_ALL=C sort \
        | cpio -o -H newc -R 0:0 --reproducible --quiet | gzip -9n ) >> "$out"
done
# verify: walk the concatenated archive and confirm every extra file landed byte-for-byte
python3 - "$out" "$@" <<'PY'
import gzip, sys
from pathlib import Path
data = gzip.open(sys.argv[1]).read()          # python reads every gzip member
files, pos = {}, 0
while pos < len(data):
    if data[pos] == 0: pos += 1; continue
    assert data[pos:pos+6] == b'070701', f'bad cpio magic at {pos}'
    f = lambda i: int(data[pos+6+8*i:pos+14+8*i], 16)
    size, ns = f(6), f(11)
    name = data[pos+110:pos+110+ns-1].decode()
    body = (pos+110+ns+3) & ~3
    if name != 'TRAILER!!!': files[name] = data[body:body+size]
    pos = (body+size+3) & ~3
n = 0
for tree in sys.argv[2:]:
    for p in Path(tree).rglob('*'):
        if p.is_file():
            assert files.get(str(p.relative_to(tree))) == p.read_bytes(), p
            n += 1
assert 'init' in files, 'base initramfs lost'
print(f'initramfs: {len(files)} entries, {n} extra files verified')
PY
ls -l "$out"
