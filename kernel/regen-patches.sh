#!/usr/bin/env bash
# Regenerate kernel/patches/ (or kernel/patches-7.2/ with BASE=7.2) from a modified kernel tree.
#   [BASE=7.2] ./regen-patches.sh PRISTINE_TREE MODIFIED_TREE
# PRISTINE_TREE is the unpacked upstream tarball (see BASE.md). Each patch is
# the diff of its file list below; a file belongs to exactly one patch. Patches
# marked "upstream" are backports kept verbatim and are only checked, not
# rewritten. Anything changed in MODIFIED_TREE but not listed here is reported.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
a=${1:?pristine tree}
b=${2:?modified tree}
base=${BASE:-6.13}

# name | files (space separated) | description (first line = subject)
series_6_13=(
"0001-drm-msm-dpu-active-ctl-for-bonded-dsi|drivers/gpu/drm/msm/disp/dpu1/catalog/dpu_8_1_sm8450.h drivers/gpu/drm/msm/disp/dpu1/dpu_encoder.c drivers/gpu/drm/msm/disp/dpu1/dpu_encoder_phys_cmd.c drivers/gpu/drm/msm/disp/dpu1/dpu_encoder_phys_vid.c drivers/gpu/drm/msm/disp/dpu1/dpu_hw_ctl.c drivers/gpu/drm/msm/disp/dpu1/dpu_hw_ctl.h drivers/gpu/drm/msm/disp/dpu1/dpu_rm.c drivers/gpu/drm/msm/disp/dpu1/dpu_rm.h|drm/msm/dpu: use one ACTIVE CTL for bonded DSI on SM8450

SM8450 has ACTIVE CTLs; a bonded (dual) DSI pipeline needs a single CTL
driving both interfaces with CTL_INTF_MASTER, not DPU_CTL_SPLIT_DISPLAY."
"0002-drm-msm-dsi-bonded-phy-setup-order-and-error-irq|drivers/gpu/drm/msm/dsi/dsi_host.c drivers/gpu/drm/msm/dsi/dsi_manager.c|drm/msm/dsi: configure both bonded PHYs first; don't re-arm the error irq

Set up both PHYs before host registration can start a modeset. The DSI error
interrupt is no longer re-armed by default (dsi_err_rearm parameter): on this
panel it storms at ~55k irq/s and starves UFS."
"0003-drm-panel-novatek-nt36523-gts8wifi|drivers/gpu/drm/panel/panel-novatek-nt36523.c|drm/panel: novatek-nt36523: add the Galaxy Tab S8 (CSOT PPA957DB1) panel"
"0004-drm-simpledrm-hold-interconnect-bandwidth|drivers/gpu/drm/tiny/simpledrm.c|drm/simpledrm: hold an interconnect bandwidth vote

Without a vote the boot-time interconnect floor is dropped at sync_state and
the bootloader framebuffer underruns and blanks before msm takes over."
"0005-interconnect-qcom-sm8450-fix-node-link-symbols|drivers/interconnect/qcom/sm8450.c|interconnect: qcom: sm8450: use the SM8450_-prefixed IDs in two node links

qhs_compute_cfg and qhs_lpass_cfg linked to the un-prefixed dt-bindings
macros (value 0) instead of the driver's own IDs."
"0006-input-novatek-nvt-ts-samsung-firmware|Documentation/devicetree/bindings/input/touchscreen/novatek,nvt-ts.yaml drivers/input/touchscreen/novatek-nvt-ts.c|Input: novatek-nvt-ts: support Samsung's NT36523 firmware

Page select at 0x2FE00, Samsung touch-state values and firmware check."
"0007-iio-qcom-spmi-adc5-expose-adc7-raw-code|drivers/iio/adc/qcom-spmi-adc5.c|iio: adc: qcom-spmi-adc5: expose the ADC7 raw code

Lets board code apply its own NTC tables."
"0008-power-supply-max17042-add-max77705-battery|drivers/power/supply/max17042_battery.c|power: supply: max17042: add the maxim,max77705-battery compatible"
"0009-power-supply-x700-max77705-and-sm5440-chargers|drivers/power/supply/Kconfig drivers/power/supply/Makefile drivers/power/supply/gts8-charging-ntc.h drivers/power/supply/gts8-thermal-policy.h drivers/power/supply/max77705-altmode.h drivers/power/supply/max77705-charge-lease.h drivers/power/supply/max77705-charger-monitor.c drivers/power/supply/max77705-float-control.h drivers/power/supply/max77705-pd-protocol.h drivers/power/supply/sm5440-charger-monitor.c drivers/power/supply/sm5440-direct-charge.h drivers/power/supply/sm5440-protection.h|power: supply: add the SM-X700 MAX77705 and SM5440 charger drivers

max77705-charger-monitor: switching charger, thermal policy, USB-C/PD
(fixed and PPS contracts), USB role and OTG boost, PS5169/SBU orientation
and DisplayPort alternate mode with an HPD bridge.
sm5440-charger-monitor: SM5440 charge-pump direct charging (up to ~43 W over
PPS) with its protections. See docs/CHARGING.md."
"0010-regulator-userspace-consumer-tolerate-unknown-state|drivers/regulator/userspace-consumer.c|regulator: userspace-consumer: treat an unknown state as disabled

RPMh regulators report -EINVAL until first voted; don't fail probe on it."
"0011-asoc-qcom-mi2s-codec-format-and-lpaif-type|sound/soc/qcom/sc8280xp.c sound/soc/qcom/qdsp6/audioreach.c sound/soc/qcom/qdsp6/q6apm-lpass-dais.c|ASoC: qcom: MI2S codec format/bclk, I2S lpaif_type and set_fmt for AudioReach

Needed for CS35L45 amplifiers on primary MI2S (same as the Tab S8+ port)."
"0012-input-touchscreen-wacom-wez01-s-pen|drivers/input/touchscreen/Makefile drivers/input/touchscreen/wacom-wez01.c|Input: add the Wacom WEZ01 (Galaxy Tab S8 S Pen) driver"
"0013-usb-dwc3-set-suspendenable-soon-after-phy-init|drivers/usb/dwc3/core.c drivers/usb/dwc3/core.h drivers/usb/dwc3/drd.c|upstream"
"0014-usb-typec-mux-add-parade-ps5169|drivers/usb/typec/mux/Kconfig drivers/usb/typec/mux/Makefile drivers/usb/typec/mux/ps5169.c|usb: typec: mux: add the Parade PS5169 USB3/DP redriver

Orientation and mode switch; forwards the orientation to the next switch
(the QMP PHY), which has to flip as well."
"0015-pinctrl-qcom-lpass-lpi-runtime-pm|drivers/pinctrl/qcom/pinctrl-lpass-lpi.c drivers/pinctrl/qcom/pinctrl-lpass-lpi.h drivers/pinctrl/qcom/pinctrl-sm8450-lpass-lpi.c|pinctrl: qcom: lpass-lpi: runtime PM for the LPASS clock votes

The driver held its LPASS core/audio clock votes from probe to remove. The
ADSP then keeps voting CX on for audio, and the SoC never reaches CX
collapse in suspend. Hold the votes only around register access (100 ms
autosuspend). Wired up for SM8450."
"0016-asoc-codecs-lpass-macros-drop-core-votes-in-runtime-suspend|sound/soc/codecs/lpass-rx-macro.c sound/soc/codecs/lpass-tx-macro.c sound/soc/codecs/lpass-va-macro.c sound/soc/codecs/lpass-wsa-macro.c|ASoC: codecs: lpass-*-macro: release the macro/dcodec votes in runtime suspend

Same reason as the LPI pinctrl change: the LPASS_HW_MACRO/DCODEC votes were
held from probe and kept the ADSP's CX vote up while audio was idle."
"0017-arm64-dts-qcom-add-sm8450-samsung-gts8wifi|arch/arm64/boot/dts/qcom/Makefile arch/arm64/boot/dts/qcom/sm8450-samsung-gts8wifi.dts|arm64: dts: qcom: add the Samsung Galaxy Tab S8 (SM-X700)"
)

# The 7.2 series (linux-7.2.9). 6.13 patches 0005, 0008, 0013 and 0015 are upstream,
# 0001 and the PHY-order half of 0002 too, and most of 0011.
series_7_2=(
"0001-drm-msm-dsi-dont-rearm-the-error-irq|drivers/gpu/drm/msm/dsi/dsi_host.c|drm/msm/dsi: don't re-arm the error irq by default

The DSI error interrupt is no longer re-armed by default (dsi_err_rearm
parameter): on this panel it storms at ~55k irq/s and starves UFS."
"0002-drm-panel-novatek-nt36523-gts8wifi|drivers/gpu/drm/panel/panel-novatek-nt36523.c|drm/panel: novatek-nt36523: add the Galaxy Tab S8 (CSOT PPA957DB1) panel"
"0003-drm-simpledrm-hold-interconnect-bandwidth|drivers/gpu/drm/sysfb/simpledrm.c|drm/simpledrm: hold an interconnect bandwidth vote

Without a vote the boot-time interconnect floor is dropped at sync_state and
the bootloader framebuffer underruns and blanks before msm takes over."
"0004-input-novatek-nvt-ts-samsung-firmware|Documentation/devicetree/bindings/input/touchscreen/novatek,nvt-ts.yaml drivers/input/touchscreen/novatek-nvt-ts.c|Input: novatek-nvt-ts: support Samsung's NT36523 firmware

Page select at 0x2FE00, Samsung touch-state values and firmware check."
"0005-iio-qcom-spmi-adc5-expose-adc7-raw-code|drivers/iio/adc/qcom-spmi-adc5.c|iio: adc: qcom-spmi-adc5: expose the ADC7 raw code

Lets board code apply its own NTC tables."
"0006-power-supply-x700-max77705-and-sm5440-chargers|drivers/power/supply/Kconfig drivers/power/supply/Makefile drivers/power/supply/gts8-charging-ntc.h drivers/power/supply/gts8-thermal-policy.h drivers/power/supply/max77705-altmode.h drivers/power/supply/max77705-charge-lease.h drivers/power/supply/max77705-charger-monitor.c drivers/power/supply/max77705-float-control.h drivers/power/supply/max77705-pd-protocol.h drivers/power/supply/sm5440-charger-monitor.c drivers/power/supply/sm5440-direct-charge.h drivers/power/supply/sm5440-protection.h|power: supply: add the SM-X700 MAX77705 and SM5440 charger drivers

max77705-charger-monitor: switching charger, thermal policy, USB-C/PD
(fixed and PPS contracts), USB role and OTG boost, PS5169/SBU orientation
and DisplayPort alternate mode with an HPD bridge.
sm5440-charger-monitor: SM5440 charge-pump direct charging (up to ~43 W over
PPS) with its protections. See docs/CHARGING.md.
Independent of the upstream MAX77705 MFD driver (which binds maxim,max77705)."
"0007-regulator-userspace-consumer-tolerate-unknown-state|drivers/regulator/userspace-consumer.c|regulator: userspace-consumer: treat an unknown state as disabled

RPMh regulators report -EINVAL until first voted; don't fail probe on it."
"0008-asoc-qcom-sc8280xp-mi2s-codec-format-and-bclk|sound/soc/qcom/sc8280xp.c|ASoC: qcom: sc8280xp: give MI2S codecs their format and bit clock

Needed for CS35L45 amplifiers on primary MI2S (same as the Tab S8+ port).
The CPU-side format, the I2S lpaif_type and q6i2s set_fmt are upstream."
"0009-input-touchscreen-wacom-wez01-s-pen|drivers/input/touchscreen/Makefile drivers/input/touchscreen/wacom-wez01.c|Input: add the Wacom WEZ01 (Galaxy Tab S8 S Pen) driver"
"0010-usb-typec-mux-add-parade-ps5169|drivers/usb/typec/mux/Kconfig drivers/usb/typec/mux/Makefile drivers/usb/typec/mux/ps5169.c|usb: typec: mux: add the Parade PS5169 USB3/DP redriver

Orientation and mode switch; forwards the orientation to the next switch
(the QMP PHY), which has to flip as well."
"0011-asoc-codecs-lpass-macros-drop-core-votes-in-runtime-suspend|sound/soc/codecs/lpass-rx-macro.c sound/soc/codecs/lpass-tx-macro.c sound/soc/codecs/lpass-va-macro.c sound/soc/codecs/lpass-wsa-macro.c|ASoC: codecs: lpass-*-macro: release the macro/dcodec votes in runtime suspend

The LPASS_HW_MACRO/DCODEC votes were held from probe and kept the ADSP's
CX vote up while audio was idle (upstream LPI pinctrl runtime PM covers the
other half)."
"0012-arm64-dts-qcom-add-sm8450-samsung-gts8wifi|arch/arm64/boot/dts/qcom/Makefile arch/arm64/boot/dts/qcom/sm8450-samsung-gts8wifi.dts|arm64: dts: qcom: add the Samsung Galaxy Tab S8 (SM-X700)"
)

case $base in
    6.13) out=$here/patches; series=("${series_6_13[@]}") ;;
    7.2) out=$here/patches-7.2; series=("${series_7_2[@]}") ;;
    *) echo "unknown BASE $base (6.13 or 7.2)" >&2; exit 2 ;;
esac

listed=()
for entry in "${series[@]}"; do
    IFS='|' read -r name files desc <<< "$entry"
    read -ra fl <<< "$files"
    listed+=("${fl[@]}")
    if [ "$desc" = upstream ]; then
        tmp=$(mktemp -d)
        cp -a "$a/." "$tmp/"
        patch -p1 -s -d "$tmp" < "$out/$name.patch"
        for f in "${fl[@]}"; do
            cmp -s "$tmp/$f" "$b/$f" || echo "!! $f differs from upstream backport $name" >&2
        done
        rm -rf "$tmp"
        continue
    fi
    {
        printf '%s\n\n' "$desc"
        for f in "${fl[@]}"; do
            if [ -e "$a/$f" ]; then la=a/$f; fa=$a/$f; else la=/dev/null; fa=/dev/null; fi
            diff -u --label "$la" --label "b/$f" "$fa" "$b/$f" || [ $? -eq 1 ]
        done
    } > "$out/$name.patch"
    echo "wrote $name.patch"
done

# Report changed source files that no patch covers (build output is ignored).
(cd "$b" && find . -type f \( -name '*.[ch]' -o -name '*.dts*' -o -name 'Kconfig*' -o -name Makefile -o -name '*.yaml' \) \
    ! -path './include/generated/*' ! -path './arch/*/include/generated/*' ! -path './scripts/*' \
    ! -path './tools/*' ! -path './usr/*' ! -name '*.mod.c' ! -path '*/generated/*' | sed 's|^\./||') |
while read -r f; do
    if [ -e "$a/$f" ] && cmp -s "$a/$f" "$b/$f"; then continue; fi
    case $f in  # generated by an in-tree build
        .*|*/.*|*.asn1.[ch]|*.dtb.S|*_deftbl.c|*/defkeymap.c|*/scsi_devinfo_tbl.c|*/logo_*_clut224.c|\
        lib/crc*table.h|lib/oid_registry_data.c|net/wireless/shipped-certs.c|init/utsversion-tmp.h|\
        arch/arm64/crypto/*-core.S) continue ;;
    esac
    printf '%s\n' "${listed[@]}" | grep -qxF "$f" || echo "?? not in any patch: $f" >&2
done
