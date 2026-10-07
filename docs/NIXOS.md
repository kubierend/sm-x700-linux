# NixOS (work in progress)

The flake at the repository root provides NixOS support for the tablet, as a counterpart of
the pmOS packages: the same kernel overlay, the same device scripts and data, the same
uniLoader boot path. **Status: it evaluates and its packages build; it has not been booted
on the tablet yet.** Expect to need the debugging notes in `INSTALL.md` for the first boot.

## What is where

| Path | What |
|---|---|
| `flake.nix` | `nixosModules.default`, `overlays.default`, the example `nixosConfigurations`, packages |
| `nixos/modules/samsung-gts8wifi.nix` | the hardware module (`hardware.samsung-gts8wifi.*`) |
| `nixos/modules/userdata-image.nix` | `system.build.userdataImage`: ext4 root for USERDATA |
| `nixos/pkgs/linux.nix` | the kernel: `kernel/patches*` + the config fragments + `nixos.config` |
| `nixos/pkgs/boot-image.nix` | `boot.img`: uniLoader{Image, DTB, initrd} + Samsung's ramdisk |
| `nixos/pkgs/hexagonrpc.nix` | nixpkgs' hexagonrpc at the pmOS snapshot + the registry-write patches |
| `nixos/pkgs/device-support.nix` | firmware/sensor setup scripts, Wi-Fi sleep hook, udev rules, UCM |
| `nixos/pkgs/speaker-topology.nix` | the CS35L45 speaker topology, derived from linux-firmware |
| `nixos/example/configuration.nix` | Plasma 6 tablet example |

## How it maps from pmOS

| pmOS | NixOS |
|---|---|
| `linux-postmarketos-qcom-sm8450` | `pkgs.gts8wifi.linux` (`kernelBase = "6.13"`) or `linux-7_2` |
| `device-samsung-gts8wifi` | the module: firmware, udev, UCM via `ALSA_CONFIG_UCM2`, sensor-vdd, sleep hook, zram |
| `hexagonrpcd` (patched) | `pkgs.gts8wifi.hexagonrpc`, `hexagonrpcd-sdsp.service` with `-R /var/lib/gts8wifi/hexagonfs` |
| libssc, iio-sensor-proxy, bootmac | straight from nixpkgs (iio-sensor-proxy is built with SSC support) |
| mkinitfs + firmware file lists | systemd stage 1 + `boot.initrd.extraFirmwarePaths` |
| `gts8wifi-firmware-setup` into `/usr/lib/firmware` | `gts8wifi-firmware-setup --firmware-dir DIR`, then `hardware.samsung-gts8wifi.firmware = ./DIR` |
| `boot/build-from-pmos.sh` on a PC | `system.build.bootImage`, also linked into every generation as `gts8wifi-boot.img` |
| pmOS_boot + pmOS_root inside USERDATA | one ext4 filesystem (`NIXOS_GTS8`) directly on USERDATA |

Booting: the image's command line says `init=/nix/var/nix/profiles/system/init`, not a single
generation, so one boot.img keeps working for every generation with the same kernel, initrd
and command line. `nixos-rebuild` warns when a generation needs a new boot.img (and writes it
to the BOOT partition itself with `bootImage.flashOnSwitch = true`). There is only one BOOT
partition: no boot menu, no automatic fallback; Download Mode + heimdall always works.

## Things that differ from the pmOS image and need checking on the first boot

- The initramfs placement. A NixOS initrd with the DSP firmware may not fit the 22.9 MiB the
  pmOS layout leaves at 0xb6915000; `bootImage.ramdiskEntry = "auto"` then moves it to
  0x812000000 (free RAM after the kernel). The build runs `boot/audit-boot-layout.py` against
  the DTB and refuses a layout that overlaps a reservation or exceeds the 96 MiB BOOT
  partition. `layout-audit.txt` in the boot image output says which address was used.
- systemd stage 1 instead of the pmOS initramfs (root by filesystem label, no modules needed:
  UFS, ext4 and the display are built in).

## Install

You need Nix with flakes on a Linux PC, heimdall, `img2simg` (android-tools), the stock boot
ramdisk (see `INSTALL.md`: `unpack_bootimg` on Samsung's `boot.img`), and either an aarch64
machine, or binfmt emulation for aarch64 on your PC (`boot.binfmt.emulatedSystems` on NixOS;
qemu-user-static + binfmt on other distributions, with `extra-platforms = aarch64-linux` in
`nix.conf`). Almost everything comes from cache.nixos.org; the kernel is the only big build,
and `gts8wifi-x86-kernel` cross-compiles it on the PC instead of emulating it.

1. Make your own flake that imports `nixosModules.default` (or edit
   `nixos/example/configuration.nix`), and set `hardware.samsung-gts8wifi.stockRamdisk` to the
   stock ramdisk. Keep that file and the firmware out of public repositories.
2. Build both images:

   ```
   nix build .#nixosConfigurations.gts8wifi-x86-kernel.config.system.build.userdataImage -o userdata
   nix build .#nixosConfigurations.gts8wifi-x86-kernel.config.system.build.bootImage -o bootimg
   ```

3. Flash (Download Mode, see `INSTALL.md`; each flash needs a fresh session):

   ```
   zstd -d userdata/*.img.zst -o nixos.img && img2simg nixos.img userdata-sparse.img
   heimdall flash --USERDATA userdata-sparse.img
   heimdall flash --BOOT bootimg/boot.img
   ```

4. First boot: the root filesystem grows to the whole partition and registers its store
   paths. As on pmOS it has display, touch, 2.4 GHz Wi-Fi, USB and charging, but no GPU
   acceleration, audio or sensors until the device firmware is installed:

   ```
   sudo gts8wifi-firmware-setup --firmware-dir /etc/nixos/gts8wifi-firmware
   ```

   It also populates `/var/lib/gts8wifi/hexagonfs` for the sensor DSP. Then set
   `hardware.samsung-gts8wifi.firmware = ./gts8wifi-firmware;` (relative to your flake; for a
   flake in git, `git add` it locally, never push it) and rebuild. The firmware goes into the
   initrd, so the boot image changes: flash the new one (or enable `flashOnSwitch`).

## Kernel choice

`hardware.samsung-gts8wifi.kernelBase` selects `6.13` (the hardware-verified pmOS kernel,
default) or `7.2` (stable 7.2.9 with the forward-ported patches; builds, not booted yet). See
`kernel/BASE.md`.

## Open

- First boot on hardware (everything above is build- and evaluation-tested only).
- Booting the 7.2 kernel base; the Wacom/PS5169/charger drivers still have no DT bindings.
- Upstreaming the hexagonrpc patches would let the module use nixpkgs' package unchanged.
- Not yet built here: hexagonrpc, device-support and speaker-topology packages (cross build was interrupted), the initrd and the full system (need an aarch64 builder).
