#!/usr/bin/env bash
# Stage the firmware that must be in the initramfs (the kernel loads it before the rootfs
# is mounted): Adreno 730 GPU, audio DSP + speaker topology, sensor DSP.
# None of it is stored in this repo. It comes from your own device/firmware:
#
#   stage-firmware.sh --modem-image DIR --linux-firmware DIR --out DIR
#
# --modem-image     the image/ directory of Samsung's NON-HLOS.bin (in the BL tarball), e.g.
#                   apnhlos/image from tools/extract-firmware.sh: adsp.mdt/.bNN, slpi.mdt/.bNN,
#                   a730_zap.mdt/.bNN
# --linux-firmware  a linux-firmware tree/checkout with qcom/a730_sqe.fw,
#                   qcom/gmu_gen70000.bin and qcom/sm8450/SM8450-HDK-tplg.bin
# --out             receives gpu/, audio/, sensors/ trees for assemble-initramfs.sh
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
modem= lfw= out=
while [ $# -gt 0 ]; do
    case $1 in --modem-image) modem=$2;; --linux-firmware) lfw=$2;; --out) out=$2;;
        *) echo "unknown option $1" >&2; exit 2;; esac; shift 2
done
[ -d "$modem" ] && [ -d "$lfw" ] && [ -n "$out" ] || { sed -n 2,13p "$0"; exit 2; }
fw=usr/lib/firmware/qcom
dev=$fw/sm8450/gts8wifi
rm -rf "$out"; mkdir -p "$out"/{gpu,audio,sensors}/"$dev"

# split PIL image: the .mdt holds the headers and .b00 must equal its first segment
check_pil() { cmp -n "$(stat -c %s "$1/${2}.b00")" "$1/${2}.b00" "$1/${2}.mdt"; }

# GPU: SQE + GMU firmware are redistributable (linux-firmware); the zap shader is Samsung-signed
install -m644 "$lfw/qcom/a730_sqe.fw" "$lfw/qcom/gmu_gen70000.bin" "$out/gpu/$fw/"
for f in a730_zap.mdt a730_zap.b00 a730_zap.b01 a730_zap.b02; do
    install -m644 "$modem/$f" "$out/gpu/$dev/"
done
check_pil "$out/gpu/$dev" a730_zap

# Audio DSP + the speaker (CS35L45 / primary MI2S) topology derived from the HDK one
install -m644 "$modem"/adsp.mdt "$modem"/adsp.b* "$out/audio/$dev/"
check_pil "$out/audio/$dev" adsp
python3 "$here/tools/mk-tplg.py" "$lfw/qcom/sm8450/SM8450-HDK-tplg.bin" \
    "$out/audio/$fw/sm8450/Samsung-Galaxy-Tab-S8-tplg.bin"

# Sensor DSP
install -m644 "$modem"/slpi.mdt "$modem"/slpi.b* "$out/sensors/$dev/"
check_pil "$out/sensors/$dev" slpi
echo "staged: $out/{gpu,audio,sensors}"
