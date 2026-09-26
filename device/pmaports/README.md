# pmaports packages

| Package | What |
|---|---|
| `linux-postmarketos-qcom-sm8450` | `sm8450-mainline/linux` @ `bf1d29fc` + `kernel/patches/*` + `kernel/config/x700.config` |
| `device-samsung-gts8wifi` | deviceinfo and the device's userland, see below |
| `device-samsung-gts8wifi-plasma` | metapackage, auto-installed with Plasma: on-screen keyboard (plasma-keyboard + KWin setting), Dolphin, Ark, Konsole, Kate, Okular, Gwenview, Spectacle, Chromium, Discover + Flatpak, ... |
| `device-samsung-gts8wifi-tools` | metapackage: i2c-tools, libgpiod, evtest, iw, alsa-utils, kmscube, ... |
| `hexagonrpcd` | sensor-DSP daemon, upstream `598b591` + 7 patches (from the sm-x800-linux port); a higher version than Alpine's so apk prefers it |

`./install-to-pmaports.sh "$(pmbootstrap config aports)"` copies them into the pmaports
checkout pmbootstrap uses and stages the kernel patches/config and the two Python tools next
to their APKBUILDs. Then `pmbootstrap checksum <pkg>` (the local packages carry
`sha512sums="SKIP"`) and continue with `docs/INSTALL.md`.

## device-samsung-gts8wifi

| File | Installed as | Why |
|---|---|---|
| `mkinitfs-mdev.files` | `/usr/share/mkinitfs/files/50-gts8wifi-mdev.files` | stage-1 mdev needs `/lib/mdev/persistent-storage`, or `/dev/disk/by-*` stays empty on UFS |
| `mkinitfs-firmware.files` | `.../60-gts8wifi-firmware.files` | GPU/DSP firmware and the topology into the initramfs (built-in consumers load it before the rootfs) |
| `gts8wifi-firmware-setup` | `/usr/bin/` | copies device-signed firmware, Samsung's Wi-Fi set and the sensor config from the tablet's own partitions |
| `gts8wifi-sensors-setup` | `/usr/bin/` | sensor tree for hexagonrpcd: configs, `sns_reg.conf`, socinfo, registry seeded from `persist` |
| `mk-ath11k-board2.py` (from `tools/`) | `/usr/libexec/gts8wifi/` | board-2.bin with Samsung's BDF for the 5 GHz fix |
| `mk-tplg.py` (from `boot/tools/`) | build time only | speaker topology derived from linux-firmware's SM8450-HDK one (I2S SD1) |
| `ucm2/*.conf` | `/usr/share/alsa/ucm2/...` | speaker routing, per-amp volume cap (no speaker protection firmware) |
| `50-wcn6855-wifi` | `/usr/lib/systemd/system-sleep/` | unload/reload ath11k around suspend (WCN6855 loses state) |
| `sensor-vdd.service` | enabled | switches the SLPI sensor rail on after boot |
| `81-libssc-*.rules`, `90-*-hexagonrpcd-sdsp.rules` | udev | accelerometer mount matrix; start hexagonrpcd when the SLPI appears |

Dependencies pulled in: the linux-firmware parts for Qualcomm GPU/Wi-Fi/Bluetooth,
`alsa-ucm-conf`, `bootmac` (stable Wi-Fi/Bluetooth addresses; the Bluetooth controller has
none and stays unconfigured without one), `hexagonrpcd`, `libssc`, `iio-sensor-proxy`, and
`android-tools` (boot-deploy), `android-tools-lpdump`, `device-mapper`, `python3`, `zstd` for the firmware setup.

The UI is chosen at `pmbootstrap init` (tested: `plasma-desktop`).

Compared with the hand-provisioned bring-up tablet (survey 2026-09-26), the package replaces:
the static `/usr/local/bin/hexagonrpcd` + unit override (now the patched package),
`bt-setaddr.py` (now `bootmac`; the Bluetooth address changes once, so re-pair devices),
the hand-copied UCM, sensor tree, firmware, udev rules, `sensor-vdd.service` and sleep hook.
Personal extras on the tablet (fastfetch, vim, speedtest-cli, ...) and on-device build tools
(build-base, meson, headers: only needed to build hexagonrpcd by hand) and a Wi-Fi-only sshd
helper are left out.

**Status:** built with pmbootstrap 3.11 and installed from scratch (Plasma), then
`gts8wifi-firmware-setup` on the device: working (2026-09-26).
