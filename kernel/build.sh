#!/usr/bin/env bash
# Build the X700 kernel from a pinned upstream + this overlay.
#   [BASE=6.13|7.2] ./build.sh [workdir]   (default: ./work)
#       -> $workdir/out/{Image,sm8450-samsung-gts8wifi.dtb,.config}
# BASE=6.13 (default): sm8450-mainline/linux @ bf1d29fc + patches/, verified on hardware.
# BASE=7.2: stable linux-7.2.9 + patches-7.2/ + config/sm8450.config; builds, not yet
#           booted on hardware (see BASE.md).
# Set DEBUG=1 to also merge config/x700-debug.config.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
work=${1:-$here/work}
base=${BASE:-6.13}
case $base in
    6.13)
        commit=bf1d29fced6e156dd6090a9b6600a8c44259c114
        url=https://github.com/sm8450-mainline/linux/archive/$commit.tar.gz
        tarball=$work/linux.tar.gz src=$work/linux-$commit patches=$here/patches
        defconfigs=(defconfig sm8450.config) frags=() ;;
    7.2)
        version=7.2.9
        url=https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-$version.tar.xz
        tarball=$work/linux-$version.tar.xz src=$work/linux-$version patches=$here/patches-7.2
        defconfigs=(defconfig) frags=("$here/config/sm8450.config") ;;
    *) echo "unknown BASE $base (6.13 or 7.2)" >&2; exit 2 ;;
esac
out=$work/out
mkdir -p "$work" "$out"

if [ ! -d "$src" ]; then
    [ -f "$tarball" ] || curl -fL --retry 5 --retry-delay 30 --retry-all-errors -o "$tarball" "$url"
    tar -C "$work" -xf "$tarball"
    for p in "$patches"/*.patch; do
        echo ">> applying $(basename "$p")"
        patch -p1 -d "$src" -s < "$p"
    done
fi

export ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}
make -C "$src" O="$out" "${defconfigs[@]}"
frags+=("$here/config/x700.config")
[ "${DEBUG:-0}" = 1 ] && frags+=("$here/config/x700-debug.config")
(cd "$out" && "$src/scripts/kconfig/merge_config.sh" -m .config "${frags[@]}")
make -C "$src" O="$out" olddefconfig
make -C "$src" O="$out" -j"$(nproc)" Image qcom/sm8450-samsung-gts8wifi.dtb
cp "$out/arch/arm64/boot/Image" "$out/arch/arm64/boot/dts/qcom/sm8450-samsung-gts8wifi.dtb" "$out/"
echo "built: $out/Image  $out/sm8450-samsung-gts8wifi.dtb"
