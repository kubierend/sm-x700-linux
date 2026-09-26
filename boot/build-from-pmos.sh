#!/usr/bin/env bash
# Flashable boot.img from a postmarketOS /boot (the kernel, DTB and initramfs that
# `pmbootstrap install` or an on-device `apk upgrade` + mkinitfs produced).
#
#   build-from-pmos.sh --boot DIR --stock-ramdisk FILE --out DIR [options]
#
# --boot DIR          a pmOS /boot: vmlinuz, initramfs, dtbs/qcom/sm8450-samsung-gts8wifi.dtb
#                     e.g. <pmbootstrap work>/chroot_rootfs_samsung-gts8wifi/boot, or a copy
#                     of the tablet's /boot (after gts8wifi-firmware-setup it carries the
#                     device firmware in its initramfs)
# --stock-ramdisk     ramdisk of Samsung's boot.img (see README.md)
# --firmware DIR      optional: gpu/ audio/ sensors/ trees from stage-firmware.sh, appended
#                     to the initramfs (for a first boot before gts8wifi-firmware-setup)
# --stock-fdt FILE    optional: stock Android FDT, to audit the payload placement
# Other options (--append-bootargs, --uniloader-src) are passed to build-boot-img.sh.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
boot= fw= out= pass=()
while [ $# -gt 0 ]; do
    case $1 in
        --boot) boot=$2;; --firmware) fw=$2;; --out) out=$2; pass+=("$1" "$2");;
        --stock-ramdisk|--stock-fdt|--append-bootargs|--uniloader-src) pass+=("$1" "$2");;
        *) echo "unknown option $1" >&2; exit 2;;
    esac; shift 2
done
[ -d "$boot" ] && [ -n "$out" ] || { sed -n 2,15p "$0"; exit 2; }
mkdir -p "$out"; out=$(cd "$out" && pwd)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# uniLoader boots a raw arm64 Image
case $(file -b "$boot/vmlinuz") in
    gzip*) gzip -dc "$boot/vmlinuz" > "$work/Image" ;;
    *) cp "$boot/vmlinuz" "$work/Image" ;;
esac
dtb=$boot/dtbs/qcom/sm8450-samsung-gts8wifi.dtb
[ -f "$dtb" ] || dtb=$boot/sm8450-samsung-gts8wifi.dtb

initramfs=$boot/initramfs
if [ -n "$fw" ]; then
    trees=()
    for t in gpu audio sensors; do [ -d "$fw/$t" ] && trees+=("$fw/$t"); done
    "$here/assemble-initramfs.sh" --base "$initramfs" --out "$work/initramfs" "${trees[@]}"
    initramfs=$work/initramfs
fi

"$here/build-boot-img.sh" --image "$work/Image" --dtb "$dtb" --initramfs "$initramfs" "${pass[@]}"
cp "$work/Image" "$out/Image"
cp "$dtb" "$out/sm8450-samsung-gts8wifi.dtb"
cp "$initramfs" "$out/initramfs"
( cd "$out" && sha256sum boot.img Image sm8450-samsung-gts8wifi.dtb initramfs > SHA256SUMS )
