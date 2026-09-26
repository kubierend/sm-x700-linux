# Boot image assembly

How the pieces become a flashable `boot.img`:

```
build-from-pmos.sh     -> boot.img from a pmOS /boot (vmlinuz, DTB, initramfs); the normal path,
                          see ../docs/INSTALL.md. It wraps the scripts below.

kernel/build.sh        -> Image + sm8450-samsung-gts8wifi.dtb        (kernel development)
stage-firmware.sh      -> gpu/ audio/ sensors/ firmware trees         (from YOUR firmware)
assemble-initramfs.sh  -> initramfs.cpio.gz   (pmOS initramfs + firmware archives)
build-boot-img.sh      -> boot.img            (uniLoader{Image,DTB,initramfs} + stock ramdisk)
```

`build-boot-img.sh --append-bootargs "..."` adds to the DTB's command line (uniLoader passes
none): an install's `pmos_*_uuid=`, or debug options.

## Why uniLoader

Samsung's ABL overlays the DTB it hands to a kernel and corrupts it. So the image's "kernel"
is **uniLoader** (https://github.com/ivoszbg/uniLoader, GPL-2.0) with our Image, DTB and
initramfs embedded. It copies itself to a safe RAM address, sets up a framebuffer console
and starts Linux. `uniloader/0001-add-samsung-gts8wifi.patch` adds the board and config.

Placement (`gts8wifi_defconfig`): the loader relocates to `0xb2400000`; the kernel entry is
`0x80ba00000`; the initramfs is at `0xb6915000`. `audit-boot-layout.py` (run by
`build-boot-img.sh --stock-fdt`) checks these against the reservations in the stock Android
runtime FDT (`/sys/firmware/fdt` from the stock system) before you flash.

The Android boot-image wrapper only has to satisfy ABL, so it carries **Samsung's own boot
ramdisk**. It is not shipped here: unpack it from your firmware's `boot.img`
(`unpack_bootimg.py` from AOSP `mkbootimg`).

## Inputs (nothing proprietary is in this repo)

| Input | From |
|---|---|
| pmOS initramfs | `pmbootstrap install` output (`boot/initramfs`) of the device package |
| `--modem-image` | `apnhlos/image` from `tools/extract-firmware.sh` (NON-HLOS.bin in the BL tarball) |
| `--linux-firmware` | a linux-firmware checkout (a730_sqe.fw, gmu_gen70000.bin, SM8450-HDK-tplg.bin) |
| `--stock-ramdisk` | ramdisk of Samsung's `boot.img` |
| `--stock-fdt` (optional) | stock Android `/sys/firmware/fdt` |

## Example

```
kernel/build.sh
boot/stage-firmware.sh --modem-image ~/fw/apnhlos/image --linux-firmware ~/linux-firmware --out work/fw
boot/assemble-initramfs.sh --base pmos-initramfs --out work/initramfs.cpio.gz \
    work/fw/gpu work/fw/audio work/fw/sensors
MKBOOTIMG="python3 /path/to/mkbootimg.py" boot/build-boot-img.sh \
    --image kernel/work/out/Image --dtb kernel/work/out/sm8450-samsung-gts8wifi.dtb \
    --initramfs work/initramfs.cpio.gz --stock-ramdisk ~/fw/stock-boot-ramdisk \
    --stock-fdt ~/fw/runtime.dtb --out work/boot
```

`initramfs-extras/usb-debug-tree` is an optional debug hook (USB network + sshd inside the
initramfs). Append it as one more tree to `assemble-initramfs.sh` while bringing up.

## Flashing

Power off, enter Samsung Download Mode (volume keys + USB cable), then flash **only** the
BOOT partition with Heimdall, resetting the USB device first:

```
usbreset <bus>/<dev>            # the Samsung 04e8:685d device shown by lsusb
heimdall flash --BOOT work/boot/boot.img
```

Heimdall (not Odin) is what has been used successfully on this unit for every flash.

## Reproducibility

- `build-boot-img.sh` rebuilt a flashed bring-up image byte-for-byte from its own
  Image/DTB/initramfs, with `BUILD_DATE` set to the date in the original (uniLoader stamps
  `(git-hash) - date ...` into its banner).
- `assemble-initramfs.sh` is deterministic (timestamps and inode numbers are normalised) and
  verifies that every extra file landed byte-for-byte.
