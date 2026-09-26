#!/usr/bin/env bash
# Copy the three packages into a pmaports checkout (the one pmbootstrap uses) and stage the
# kernel patches and config next to the kernel APKBUILD.
#   install-to-pmaports.sh /path/to/pmaports
# Then:  pmbootstrap checksum linux-postmarketos-qcom-sm8450 device-samsung-gts8wifi hexagonrpcd
#        pmbootstrap build hexagonrpcd linux-postmarketos-qcom-sm8450 device-samsung-gts8wifi
#        pmbootstrap install   (then boot/build-from-pmos.sh makes the flashable boot.img)
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/../.." && pwd)
pm=${1:?usage: $0 /path/to/pmaports}
[ -d "$pm/device" ] || { echo "$pm does not look like a pmaports checkout" >&2; exit 2; }

install -d "$pm/device/testing" "$pm/temp"
for pkg in device-samsung-gts8wifi linux-postmarketos-qcom-sm8450; do
    rm -rf "$pm/device/testing/$pkg"; cp -r "$here/$pkg" "$pm/device/testing/$pkg"
done
rm -rf "$pm/temp/hexagonrpcd"; cp -r "$here/hexagonrpcd" "$pm/temp/hexagonrpcd"
cp "$root"/kernel/patches/*.patch "$root"/kernel/config/x700.config \
    "$pm/device/testing/linux-postmarketos-qcom-sm8450/"
cp "$root"/tools/mk-ath11k-board2.py "$root"/tools/f2fs_extract.py "$root"/boot/tools/mk-tplg.py \
    "$pm/device/testing/device-samsung-gts8wifi/"
echo "installed into $pm (device/testing/{device-samsung-gts8wifi,linux-postmarketos-qcom-sm8450}, temp/hexagonrpcd)"
