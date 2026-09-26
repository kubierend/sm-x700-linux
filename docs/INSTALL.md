# Installing

The tablet boots Samsung's bootloader (ABL) -> **uniLoader** in the BOOT partition (carrying
our kernel, DTB and initramfs) -> postmarketOS on the USERDATA partition. Android, recovery
and the stock firmware partitions are not touched; flashing stock firmware with Odin brings
Android back.

**Warning:** writing USERDATA erases all Android data. The bootloader must be unlocked
(OEM unlock), which also wipes the device.

## What you need

- A Linux PC with `pmbootstrap`, `heimdall`, an aarch64 cross compiler
  (`aarch64-linux-gnu-gcc`), `git`, `python3`, `mtools`, `lz4`, `dtc`/`fdtput`, AOSP
  `mkbootimg.py`, and `img2simg` (android-tools).
- Samsung's firmware for your tablet (the `AP`/`BL` tarballs, e.g. from samfw.com), for the
  stock boot ramdisk that ABL insists on:
  `tar -xOf AP_*.tar.md5 boot.img.lz4 | lz4 -dc > boot.img; unpack_bootimg.py --boot_img boot.img --out stock-boot`
  gives `stock-boot/ramdisk`.

## 1. Build the packages and the rootfs

```
pmbootstrap init                                  # channel edge; any device for now
device/pmaports/install-to-pmaports.sh "$(pmbootstrap config aports)"
pmbootstrap checksum hexagonrpcd linux-postmarketos-qcom-sm8450 device-samsung-gts8wifi
pmbootstrap init                                  # vendor samsung, device gts8wifi,
                                                  # init systemd, UI plasma-desktop
pmbootstrap install --password <pw>               # NOT --split: pmOS_boot and pmOS_root
                                                  # both live inside USERDATA
pmbootstrap export                                # -> /tmp/postmarketOS-export/
```

With the Plasma UI, `device-samsung-gts8wifi-plasma` comes along automatically: on-screen
keyboard (Plasma Keyboard, enabled in `/etc/xdg/kwinrc`), Dolphin, Ark, Konsole, Kate, Okular, Gwenview, Spectacle, KCalc, Haruna,
Elisa, Chromium, Discover + Flatpak, System Monitor, Filelight, Partition Manager, KDE
Connect, file thumbnailers, exFAT/NTFS tools. To drop them, run
`sudo apk del device-samsung-gts8wifi-plasma` on the tablet (apps you also added
yourself stay).

## 2. Build the boot image

```
boot/build-from-pmos.sh \
    --boot "$(pmbootstrap config work)/chroot_rootfs_samsung-gts8wifi/boot" \
    --stock-ramdisk stock-boot/ramdisk --out work/boot
```

The DTS finds the root filesystem by its `pmOS_root` label. To pin this install's UUIDs
instead, add `--append-bootargs "pmos_boot_uuid=... pmos_root_uuid=..."`.

## 3. Flash

Enter Download Mode (power off; hold Volume Up + Volume Down while plugging in USB), then:

```
img2simg /tmp/postmarketOS-export/samsung-gts8wifi.img userdata-sparse.img  # heimdall needs sparse
heimdall flash --USERDATA userdata-sparse.img
# re-enter Download Mode, then
heimdall flash --BOOT work/boot/boot.img
```

If heimdall fails to authenticate, reset the USB device first (`usbreset 04e8:685d`) or
re-enter Download Mode; each flash needs a fresh session.

## 4. First boot: device firmware

The first boot has display, touch, Wi-Fi (2.4 GHz), USB and charging, but no GPU
acceleration, audio or sensors: those need firmware signed for this device. Connect to Wi-Fi,
then on the tablet:

```
sudo gts8wifi-firmware-setup
```

It copies the GPU zap shader and the audio/sensor DSP images from the `apnhlos` partition,
Samsung's Wi-Fi firmware and board data (5 GHz) and the sensor configuration from `vendor`
(inside `super`: mapped read-only with device-mapper and read by `f2fs_extract.py`, since
Samsung's F2FS uses compression), seeds the sensor registry from `persist`, and rebuilds the
initramfs. Nothing on those partitions is modified.

The initramfs lives inside the boot image, so rebuild it from the tablet's `/boot` and flash
it once more:

```
scp -r user@<tablet>:/boot tablet-boot
boot/build-from-pmos.sh --boot tablet-boot --stock-ramdisk stock-boot/ramdisk --out work/boot
heimdall flash --BOOT work/boot/boot.img
```

Alternative without the round trip: extract the firmware on the PC
(`tools/extract-firmware.sh FIRMWARE_DIR fw`, `boot/stage-firmware.sh --modem-image
fw/apnhlos/image --linux-firmware <linux-firmware checkout> --out fw/stage`) and pass
`--firmware fw/stage` to `build-from-pmos.sh` in step 2. Wi-Fi 5 GHz and sensors still
need `gts8wifi-firmware-setup --apnhlos fw/apnhlos --vendor fw/vendor` on the tablet.

## Updating

A kernel or initramfs update through `apk` lands in the tablet's `/boot` but not in the BOOT
partition: rebuild `boot.img` from `/boot` as in step 4 and flash it. (Building uniLoader on
the device, so that this happens on its own, is not done yet.)

## pmbootstrap: "umount: ... target is busy"

Sandboxed desktop apps (browsers, Discord, Signal, Flatpak) copy pmbootstrap's chroot mounts
into their own namespaces when they start, so pmbootstrap's unmount fails. Close them during
pmbootstrap runs, or detach everything and retry:

```
grep -o " $(pmbootstrap config work)[^ ]*" /proc/mounts | sort -r | xargs -r -n1 sudo umount -l
pmbootstrap shutdown
```

## Debugging

- `--append-bootargs "earlycon=qcom_geni,0x0099c000 loglevel=7 ignore_loglevel"` for a verbose
  boot, plus `oops=panic panic=0 nokaslr` to freeze on the first oops with a decodable trace.
- `DEBUG=1 kernel/build.sh` adds hung-task/lockup detectors and the DRM panic screen.
- `boot/initramfs-extras/usb-debug-tree`: USB network + sshd inside the initramfs
  (`user@172.16.42.1`), for when the rootfs does not come up.
- `tools/sys-pm-vx`: names the RPMh voters that keep the SoC out of CX collapse in suspend.
