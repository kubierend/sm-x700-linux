#!/usr/bin/env bash
# Build the X700 kernel from the pinned upstream commit + this overlay.
#   ./build.sh [workdir]   (default: ./work)   -> $workdir/out/{Image,sm8450-samsung-gts8wifi.dtb,.config}
# Set DEBUG=1 to also merge config/x700-debug.config.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
work=${1:-$here/work}
commit=bf1d29fced6e156dd6090a9b6600a8c44259c114
src=$work/linux-$commit
out=$work/out
mkdir -p "$work" "$out"

if [ ! -d "$src" ]; then
    [ -f "$work/linux.tar.gz" ] || curl -fL --retry 5 --retry-delay 30 --retry-all-errors -o "$work/linux.tar.gz" \
        "https://github.com/sm8450-mainline/linux/archive/$commit.tar.gz"
    tar -C "$work" -xzf "$work/linux.tar.gz"
    for p in "$here"/patches/*.patch; do
        echo ">> applying $(basename "$p")"
        patch -p1 -d "$src" -s < "$p"
    done
fi

export ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}
make -C "$src" O="$out" defconfig sm8450.config
frags=("$here/config/x700.config")
[ "${DEBUG:-0}" = 1 ] && frags+=("$here/config/x700-debug.config")
(cd "$out" && "$src/scripts/kconfig/merge_config.sh" -m .config "${frags[@]}")
make -C "$src" O="$out" olddefconfig
make -C "$src" O="$out" -j"$(nproc)" Image qcom/sm8450-samsung-gts8wifi.dtb
cp "$out/arch/arm64/boot/Image" "$out/arch/arm64/boot/dts/qcom/sm8450-samsung-gts8wifi.dtb" "$out/"
echo "built: $out/Image  $out/sm8450-samsung-gts8wifi.dtb"
