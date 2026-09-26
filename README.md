# Linux on the Samsung Galaxy Tab S8 (SM-X700 / gts8wifi)

Mainline-based Linux (postmarketOS + KDE Plasma) running natively on the Snapdragon 8 Gen 1
Galaxy Tab S8 Wi-Fi. This repository is an **overlay**: kernel patches and config against a
pinned upstream commit, the pmOS packages, and the boot-image tooling. It contains no kernel
fork and no proprietary files; the device firmware is read from your own tablet.

Sibling project (Tab S8+ / SM-X800): https://github.com/aaronsb/sm-x800-linux. The audio and
sensor work here follows its recipes.

## Hardware status

| Function | State |
|---|---|
| Display (NT36523, dual-DSI C-PHY, 1600x2560@120), backlight | works |
| GPU (Adreno 730, freedreno) | works |
| Touch (NT36523 TDDI) | works |
| S Pen (Wacom WEZ01) | works: position, pressure, tilt, hover |
| Wi-Fi (WCN6855, ath11k) | works, 2.4 + 5 GHz with Samsung's firmware set (see `docs/INSTALL.md`) |
| Bluetooth | works (address set by `bootmac`) |
| USB-C: device mode, host mode (OTG power), USB 3 SuperSpeed | works, both orientations |
| DisplayPort alt mode | works, 2 lanes (up to 3440x1440@60 tested) |
| Battery gauge, charging | works; PD PPS direct charging via the SM5440 charge pump, ~30 W measured |
| Speakers (4x CS35L45) | works (no speaker-protection firmware: volume is capped in UCM) |
| Microphones | capture streams, but records silence (same on the Tab S8+) |
| Auto-rotate (accelerometer via the SLPI sensor DSP) | works |
| Power / volume keys, RTC wake | works |
| Suspend (s2idle) | works; the SoC reaches CX collapse, sleep drain still ~140 mA |
| Camera, gyroscope, keyboard cover, fingerprint | not supported |

## Layout

```
kernel/
  BASE.md            pinned upstream + how patches and config combine
  patches/           17 patches vs sm8450-mainline/linux @ bf1d29fc
  config/            x700.config (functional) + x700-debug.config (opt-in)
  build.sh           fetch, patch, configure, build Image + DTB
  regen-patches.sh   regenerate patches/ from an edited kernel tree
boot/                boot.img assembly: uniLoader port, initramfs/firmware staging,
                     layout audit (see boot/README.md)
device/pmaports/     pmOS packages: kernel, device package, patched hexagonrpcd
tools/               PC-side firmware extraction, ath11k board-file tool,
                     sys-pm-vx suspend debug module
docs/                INSTALL.md (start here), CHARGING.md, HACK-AUDIT.md
```

## Quick start

```
kernel/build.sh                    # -> kernel/work/out/{Image,sm8450-samsung-gts8wifi.dtb}
```

A full install (pmbootstrap image, boot image, firmware setup, flashing) is in
[docs/INSTALL.md](docs/INSTALL.md).

## Kernel patches

| Patch | What | Upstream? |
|---|---|---|
| 0001-0002 | msm DPU/DSI: one ACTIVE CTL for bonded DSI, PHY setup order, error-irq storm | likely, needs split |
| 0003 | NT36523 panel variant for this tablet | yes |
| 0004 | simpledrm holds an interconnect vote until msm takes over | discussed upstream |
| 0005 | interconnect sm8450: two wrong link IDs | yes |
| 0006 | novatek-nvt-ts: Samsung NT36523 firmware | yes |
| 0007 | spmi-adc5: expose ADC7 raw codes | maybe |
| 0008-0009 | MAX77705 battery compatible; MAX77705 + SM5440 charger drivers (~5k lines) | large, experimental |
| 0010 | userspace-consumer: tolerate an unknown regulator state | yes |
| 0011 | ASoC qcom: MI2S format/clock, I2S lpaif type | review |
| 0012 | Wacom WEZ01 S Pen driver | new driver, needs a binding |
| 0013 | dwc3: SUSPENDENABLE after PHY init | upstream backport (cc5bfc4e16fc) |
| 0014 | Parade PS5169 USB3/DP redriver | new driver, needs a binding |
| 0015-0016 | LPASS LPI pinctrl + codec macros: runtime PM for the LPASS clock votes (lets the SoC reach CX collapse) | yes |
| 0017 | the board DTS | yes |

## Firmware and legal

Samsung/Qualcomm firmware (GPU zap shader, audio and sensor DSP images, Wi-Fi firmware and
board data, sensor configuration) is copied from the tablet's own partitions by
`gts8wifi-firmware-setup`, or extracted from your firmware download by
`tools/extract-firmware.sh`. Nothing proprietary is committed. See `LICENSE.md`.
