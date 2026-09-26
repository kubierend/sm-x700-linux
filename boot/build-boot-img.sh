#!/usr/bin/env bash
# Assemble a flashable boot.img for the Galaxy Tab S8 (SM-X700).
#
# ABL cannot be trusted to hand a kernel its own DTB (it overlays and corrupts it), so
# the image's "kernel" is uniLoader (github.com/ivoszbg/uniLoader + boot/uniloader/*.patch)
# with Image + DTB + initramfs embedded. The Android boot-image wrapper only has to satisfy
# ABL, so it carries Samsung's own stock ramdisk.
#
#   build-boot-img.sh --image Image --dtb x.dtb --initramfs initramfs.cpio.gz \
#                     --stock-ramdisk stock-boot-ramdisk --out outdir \
#                     [--stock-fdt runtime.dtb] [--uniloader-src DIR]
#                     [--append-bootargs "pmos_root_uuid=... earlycon ..."]
#
# --stock-ramdisk : the ramdisk from Samsung's own boot.img (unpack_bootimg from AOSP).
#                   Not shipped here (Samsung's file); take it from your firmware download.
# --stock-fdt     : optional live Android FDT (/sys/firmware/fdt from the stock system);
#                   if given, the payload placement is checked against its reservations.
# --uniloader-src : an upstream uniLoader checkout at a3933a2 (default: fetched with git).
# --append-bootargs: appended to the DTB's /chosen/bootargs (uniLoader passes no command
#                   line), e.g. an install's pmos_boot_uuid=/pmos_root_uuid= or debug options.
#                   The DTS default finds the partitions by their pmOS_boot/pmOS_root labels.
# Env: MKBOOTIMG (default: mkbootimg from PATH), CROSS_COMPILE (default aarch64-linux-gnu-),
#      BUILD_DATE (uniLoader embeds it in its banner; set it for a bit-reproducible image).
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
UNILOADER_COMMIT=a3933a2

image= dtb= initramfs= stock_ramdisk= stock_fdt= out= src= append=
while [ $# -gt 0 ]; do
    case $1 in
        --image) image=$2;; --dtb) dtb=$2;; --initramfs) initramfs=$2;;
        --stock-ramdisk) stock_ramdisk=$2;; --stock-fdt) stock_fdt=$2;;
        --out) out=$2;; --uniloader-src) src=$2;; --append-bootargs) append=$2;;
        *) echo "unknown option $1" >&2; exit 2;;
    esac; shift 2
done
for v in image dtb initramfs stock_ramdisk out; do
    [ -n "${!v}" ] || { echo "missing --${v//_/-}" >&2; exit 2; }
done
MKBOOTIMG=${MKBOOTIMG:-mkbootimg}
export CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}
# uniLoader stamps "(git-hash) - date <BUILD_DATE>" into its banner. Our private tree has no .git.
export GIT_VERSION_TAG=$UNILOADER_COMMIT
export BUILD_DATE=${BUILD_DATE:-$(date "+%Y-%m-%d %H:%M:%S")}

mkdir -p "$out"; out=$(cd "$out" && pwd)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# 1. private uniLoader tree: upstream + our board port (never touches other checkouts)
if [ -n "$src" ]; then
    git -C "$src" archive "$UNILOADER_COMMIT" | tar -x -C "$work" \
        || cp -r "$src"/. "$work"/
else
    git clone -q https://github.com/ivoszbg/uniLoader.git "$work/clone"
    git -C "$work/clone" archive "$UNILOADER_COMMIT" | tar -x -C "$work"
    rm -rf "$work/clone"
fi
patch -p1 -d "$work" -s < "$here/uniloader/0001-add-samsung-gts8wifi.patch"

# 2. embed the payloads
cp "$image" "$work/blob/Image"
cp "$dtb" "$work/blob/dtb"
if [ -n "$append" ]; then
    fdtput -t s "$work/blob/dtb" /chosen bootargs \
        "$(fdtget -t s "$work/blob/dtb" /chosen bootargs) $append"
fi
fdtget -t s "$work/blob/dtb" /chosen bootargs > "$out/bootargs.txt"
cp "$initramfs" "$work/blob/ramdisk"
LC_ALL=C make -C "$work" ARCH=aarch64 gts8wifi_defconfig > "$out/loader-build.log" 2>&1
LC_ALL=C make -C "$work" ARCH=aarch64 -j"$(nproc)" >> "$out/loader-build.log" 2>&1

# 3. check placement against the stock reservations (optional, needs fdtget)
if [ -n "$stock_fdt" ]; then
    python3 "$here/audit-boot-layout.py" \
        --kernel "$work/blob/Image" --ramdisk "$work/blob/ramdisk" \
        --dtb "$work/blob/dtb" --loader-config "$work/.config" \
        --loader-elf "$work/uniLoader.o" --stock "$stock_fdt" \
        > "$out/layout-audit.txt"
fi

# 4. Android boot image (header v4): uniLoader as the kernel, stock ramdisk as ramdisk
$MKBOOTIMG --header_version 4 --os_version 12.0.0 --os_patch_level 2025-09 \
    --kernel "$work/uniLoader" --ramdisk "$stock_ramdisk" --cmdline '' -o "$out/boot.img"

cp "$work/uniLoader" "$out/uniLoader"
cp "$work/.config" "$out/uniloader.config"
( cd "$out" && sha256sum boot.img uniLoader > SHA256SUMS )
echo "built: $out/boot.img"
