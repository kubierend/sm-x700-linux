# Samsung Galaxy Tab S8 Wi-Fi (SM-X700, gts8wifi): the NixOS counterpart of the pmOS
# device and kernel packages. See docs/NIXOS.md.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.samsung-gts8wifi;
  gts = pkgs.gts8wifi;

  # The kernel is the one big build; it can be cross-compiled on the build machine while
  # everything else stays native aarch64 (from the binary cache).
  kernelPkgs =
    if cfg.kernelBuildPlatform == null then
      gts
    else
      (import pkgs.path {
        localSystem = cfg.kernelBuildPlatform;
        crossSystem = pkgs.stdenv.hostPlatform.system;
        overlays = [ (import ../overlay.nix) ];
      }).gts8wifi;
  kernel = if cfg.kernelBase == "7.2" then kernelPkgs.linux-7_2 else kernelPkgs.linux;

  # The tree gts8wifi-firmware-setup --firmware-dir wrote (qcom/..., ath11k/...).
  deviceFirmware =
    if cfg.firmware == null then
      null
    else
      pkgs.runCommand "gts8wifi-device-firmware"
        {
          meta = {
            # Ahead of linux-firmware (6): our ath11k WCN6855/hw2.1 files replace its own.
            priority = 4;
            license = lib.licenses.unfree;
          };
        }
        ''
          mkdir -p $out/lib/firmware
          cp -r ${cfg.firmware}/. $out/lib/firmware/
        '';

  # The kernel boots the GPU, ADSP and SLPI before the root filesystem is mounted, so
  # their firmware has to be in the initrd (like the pmOS mkinitfs file lists).
  deviceFirmwareInitrd = lib.optionals (cfg.firmware != null) (
    let
      dir = cfg.firmware + "/qcom/sm8450/gts8wifi";
    in
    map (n: "qcom/sm8450/gts8wifi/${n}") (
      lib.attrNames (lib.filterAttrs (_: t: t == "regular") (builtins.readDir dir))
    )
  );

  ucm = pkgs.symlinkJoin {
    name = "alsa-ucm-conf-gts8wifi";
    paths = [
      gts.device-support
      pkgs.alsa-ucm-conf
    ];
  };
  ucmDir = "${ucm}/share/alsa/ucm2";

  # init= names the system profile instead of one closure, so one boot.img serves every
  # generation built with the same kernel, initrd and command line, and it can live inside
  # the system closure (stage 1 resolves the link inside the new root).
  bootargs = lib.concatStringsSep " " (
    [ "init=/nix/var/nix/profiles/system/init" ] ++ config.boot.kernelParams
  );

  bootImage = gts.mkBootImage {
    inherit kernel bootargs;
    initrd = "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";
    stockRamdisk = cfg.stockRamdisk;
    inherit (cfg.bootImage) ramdiskEntry;
  };

  installHook = pkgs.writeShellScript "gts8wifi-install-boot" ''
    set -eu
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.util-linux
      ]
    }
    img=$1/gts8wifi-boot.img
    part=/dev/disk/by-partlabel/boot
    if [ ! -e "$img" ]; then
      echo "gts8wifi: no boot image (hardware.samsung-gts8wifi.stockRamdisk is unset)" >&2
      exit 0
    fi
    size=$(stat -L -c %s "$img")
    if [ -b "$part" ] && cmp -s -n "$size" "$img" "$part"; then
      exit 0
    fi
    ${
      if cfg.bootImage.flashOnSwitch then
        ''
          [ -b "$part" ] || { echo "gts8wifi: $part not found" >&2; exit 1; }
          [ "$size" -le "$(blockdev --getsize64 "$part")" ] || { echo "gts8wifi: boot.img too big" >&2; exit 1; }
          echo "gts8wifi: writing $img to $part"
          dd if="$img" of="$part" bs=4M conv=fsync status=none
        ''
      else
        ''
          cat >&2 <<EOF
          gts8wifi: this generation needs a new boot image. Until it is flashed, the old
          kernel/initrd boots it, which breaks as soon as the kernel changed. Flash it with
              heimdall flash --BOOT $img
          from Download Mode, or set hardware.samsung-gts8wifi.bootImage.flashOnSwitch.
          EOF
        ''
    }
  '';
in
{
  imports = [ ./userdata-image.nix ];

  options.hardware.samsung-gts8wifi = {
    enable = lib.mkEnableOption "support for the Samsung Galaxy Tab S8 Wi-Fi (SM-X700)";

    kernelBase = lib.mkOption {
      type = lib.types.enum [
        "6.13"
        "7.2"
      ];
      default = "6.13";
      description = ''
        Kernel base (see kernel/BASE.md). "6.13" is the verified sm8450-mainline snapshot,
        "7.2" stable linux-7.2.9 with the forward-ported patches (not yet booted).
      '';
    };

    kernelBuildPlatform = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "x86_64-linux";
      description = ''
        Cross-compile the kernel (and generate its config) on this platform instead of
        natively. Lets an x86_64 machine evaluate and build the system with only a small
        amount of emulated aarch64 work. Out-of-tree kernel modules do not work with a
        cross-compiled kernel.
      '';
    };

    firmware = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression "./gts8wifi-firmware";
      description = ''
        The device-signed firmware tree written by
        `gts8wifi-firmware-setup --firmware-dir DIR` (GPU zap shader, audio and sensor DSP
        images, Samsung's Wi-Fi firmware and board data). Without it the system boots with
        display, touch, 2.4 GHz Wi-Fi, USB and charging, but no GPU acceleration, audio or
        sensors. It is proprietary and specific to this tablet: keep it out of public
        repositories and binary caches.
      '';
    };

    stockRamdisk = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        The ramdisk of Samsung's own boot.img (`unpack_bootimg` from android-tools), which
        ABL insists on. Required for `system.build.bootImage`.
      '';
    };

    bootImage = {
      ramdiskEntry = lib.mkOption {
        type = lib.types.str;
        default = "auto";
        description = ''
          Physical address uniLoader copies the initrd to. "auto" keeps the pmOS address
          (0xb6915000) when the initrd fits below the splash region, else 0x812000000.
        '';
      };

      flashOnSwitch = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Write the generation's boot.img to the BOOT partition on `nixos-rebuild boot`
          and `switch`. Off by default: the tablet has a single BOOT partition, so there
          is no fallback entry if a new kernel does not boot (Download Mode and heimdall
          always work).
        '';
      };
    };

    hexagonfsDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/gts8wifi/hexagonfs";
      description = ''
        Root of the files hexagonrpcd serves the sensor DSP (configs, socinfo and the
        registry the DSP rewrites). Populated by gts8wifi-firmware-setup.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [ (import ../overlay.nix) ];

    boot.kernelPackages = pkgs.linuxPackagesFor kernel;
    # Same command line as the DTS default, minus the pmOS initramfs options.
    boot.kernelParams = [
      "console=tty0"
      "loglevel=4"
      "panic=10"
      # the bootloader leaves the display scanout behind the SMMU
      "arm-smmu.disable_bypass=0"
      # USB host autosuspend hung the SoC
      "usbcore.autosuspend=-1"
    ];
    boot.consoleLogLevel = 4;

    # Root, UFS, ext4 and the display are built in: the initrd needs no modules.
    boot.initrd.systemd.enable = true;
    boot.initrd.includeDefaultModules = false;
    boot.initrd.availableKernelModules = lib.mkForce [ ];
    boot.initrd.extraFirmwarePaths = [
      "qcom/a730_sqe.fw"
      "qcom/gmu_gen70000.bin"
      "qcom/sm8450/Samsung-Galaxy-Tab-S8-tplg.bin"
    ]
    ++ deviceFirmwareInitrd;

    boot.loader.grub.enable = false;
    boot.loader.generic-extlinux-compatible.enable = false;
    boot.loader.external = {
      enable = true;
      inherit installHook;
    };

    system.build.bootImage =
      if cfg.stockRamdisk == null then
        throw "hardware.samsung-gts8wifi.stockRamdisk must be set to build the boot image"
      else
        bootImage;
    system.systemBuilderCommands = lib.optionalString (cfg.stockRamdisk != null) ''
      ln -s ${bootImage}/boot.img $out/gts8wifi-boot.img
    '';

    hardware.firmware = [
      pkgs.linux-firmware
      gts.speaker-topology
    ]
    ++ lib.optional (deviceFirmware != null) deviceFirmware;
    hardware.graphics.enable = lib.mkDefault true;
    hardware.bluetooth.enable = lib.mkDefault true;

    services.udev.packages = [
      gts.device-support
      pkgs.bootmac
    ];
    systemd.packages = [ pkgs.bootmac ];
    services.udev.extraRules = ''
      SUBSYSTEM=="misc", KERNEL=="fastrpc-*", OWNER="fastrpc", GROUP="fastrpc", MODE="0600"
    '';

    # The setup scripts, pointed at this system's HexagonFS directory.
    environment.systemPackages = [
      (pkgs.runCommand "gts8wifi-setup-tools" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
        for p in gts8wifi-firmware-setup gts8wifi-sensors-setup; do
          makeWrapper ${gts.device-support}/bin/$p $out/bin/$p \
            --set-default GTS8WIFI_HEXAGONFS ${cfg.hexagonfsDir}
        done
      '')
      gts.hexagonrpc.tools
    ];

    # Audio: the UCM profile for the four CS35L45 amplifiers, merged into alsa-ucm-conf.
    environment.sessionVariables.ALSA_CONFIG_UCM2 = ucmDir;
    systemd.user.services.pipewire.environment.ALSA_CONFIG_UCM2 = ucmDir;
    systemd.user.services.wireplumber.environment.ALSA_CONFIG_UCM2 = ucmDir;

    # Sensors (auto-rotate): SLPI via hexagonrpcd, read by iio-sensor-proxy through libssc.
    hardware.sensor.iio.enable = lib.mkDefault true;
    users.users.fastrpc = {
      isSystemUser = true;
      group = "fastrpc";
    };
    users.groups.fastrpc = { };
    systemd.tmpfiles.rules = [ "d ${cfg.hexagonfsDir} 0755 fastrpc fastrpc -" ];

    # The sensor rail (pm8350c L2C) is switched on from userspace: declaring it always-on
    # in the DTS hangs the boot.
    systemd.services.sensor-vdd = {
      description = "Power the SLPI sensor rail (pm8350c L2C)";
      unitConfig.ConditionPathExists = "/sys/devices/platform/sensor-vdd/state";
      before = [ "hexagonrpcd-sdsp.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.runtimeShell} -c 'echo enabled > /sys/devices/platform/sensor-vdd/state'";
        ExecStop = "${pkgs.runtimeShell} -c 'echo disabled > /sys/devices/platform/sensor-vdd/state'";
      };
    };
    # Pulled in by 90-gts8wifi-hexagonrpcd-sdsp.rules when /dev/fastrpc-sdsp appears.
    systemd.services.hexagonrpcd-sdsp = {
      description = "Server for FastRPC remote procedure calls from Qualcomm SDSP";
      unitConfig.ConditionPathExists = "/dev/fastrpc-sdsp";
      after = [ "sensor-vdd.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${gts.hexagonrpc}/bin/hexagonrpcd -f /dev/fastrpc-sdsp -d sdsp -s -R ${cfg.hexagonfsDir}";
        Restart = "always";
        RestartSec = 3;
        User = "fastrpc";
        Group = "fastrpc";
      };
    };

    # Wi-Fi across suspend: WCN6855 with Samsung's firmware comes back in MHI SYS_ERR, so
    # ath11k is unloaded before sleep and reloaded after (see the script for the guard).
    powerManagement.enable = lib.mkDefault true;
    powerManagement.powerDownCommands = "${gts.device-support}/libexec/gts8wifi/wcn6855-sleep pre suspend";
    powerManagement.resumeCommands = "${gts.device-support}/libexec/gts8wifi/wcn6855-sleep post suspend";

    zramSwap = {
      enable = lib.mkDefault true;
      algorithm = lib.mkDefault "zstd";
    };
  };
}
