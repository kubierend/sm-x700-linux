#!/usr/bin/env bash
# Extract the device firmware from a Samsung SM-X700 firmware download, on a PC, without
# root or loop mounts. Only needed when the tablet can't read its own partitions
# (gts8wifi-firmware-setup does that by default); nothing proprietary is stored in this repo.
#
#   extract-firmware.sh FIRMWARE_DIR OUT_DIR
#
# FIRMWARE_DIR: the unzipped download (BL_*.tar.md5 and AP_*.tar.md5)
# OUT_DIR receives
#   apnhlos/image/{a730_zap,adsp,slpi}.*          from NON-HLOS.bin (BL)
#   vendor/firmware/qca6490/{amss20.bin,m3.bin,bdwlang.elf}
#   vendor/etc/sensors/                           from the vendor partition in super (AP)
# Copy OUT_DIR to the tablet and run:
#   sudo gts8wifi-firmware-setup --apnhlos OUT_DIR/apnhlos --vendor OUT_DIR/vendor
# The same apnhlos/image directory is what boot/stage-firmware.sh --modem-image takes.
#
# Needs: tar, lz4, mtools, python3, and simg2img + lpunpack (android-tools; run through nix
# if they are not installed). Scratch space: ~25 GB while super is unpacked.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fw=${1:?firmware dir}; out=${2:?output dir}
mkdir -p "$out"; out=$(cd "$out" && pwd)
tmp=$(mktemp -d -p "$out"); trap 'rm -rf "$tmp"' EXIT

android_tool() {
    if command -v "$1" >/dev/null; then "$@"
    else nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#android-tools --command "$@"; fi
}

bl=$(ls "$fw"/BL_*.tar.md5 | head -1)
ap=$(ls "$fw"/AP_*.tar.md5 | head -1)

echo ">> NON-HLOS (GPU zap, audio DSP, sensor DSP)"
tar -xOf "$bl" NON-HLOS.bin.lz4 | lz4 -dc > "$tmp/NON-HLOS.bin"
rm -rf "$out/apnhlos"; mkdir -p "$out/apnhlos/image"
# a FAT image shorter than its header says (7z stops at that), which mtools reads fine
mcopy -n -i "$tmp/NON-HLOS.bin" '::/image/a730_zap.*' '::/image/adsp.*' '::/image/slpi.*' \
    "$out/apnhlos/image/"
rm "$tmp/NON-HLOS.bin"

echo ">> vendor (Wi-Fi firmware, sensor configuration)"
tar -xOf "$ap" super.img.lz4 | lz4 -dc > "$tmp/super.sparse"
android_tool simg2img "$tmp/super.sparse" "$tmp/super.img" 2>/dev/null \
    || mv "$tmp/super.sparse" "$tmp/super.img"
rm -f "$tmp/super.sparse"
android_tool lpunpack -p vendor "$tmp/super.img" "$tmp/"
rm "$tmp/super.img"
rm -rf "$out/vendor"
for f in amss20.bin m3.bin bdwlang.elf; do
    python3 "$here/f2fs_extract.py" "$tmp/vendor.img" extract "/firmware/qca6490/$f" \
        "$out/vendor/firmware/qca6490/$f"
done
python3 "$here/f2fs_extract.py" "$tmp/vendor.img" extractdir /etc/sensors "$out/vendor/etc/sensors"
echo "done: $out/{apnhlos,vendor}"
