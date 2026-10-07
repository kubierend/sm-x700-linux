# system.build.userdataImage: an ext4 root filesystem holding the system closure, written
# straight to the USERDATA partition (no partition table inside it, unlike pmOS's
# pmOS_boot/pmOS_root image). It is as small as the closure allows and grows to the whole
# partition on first boot.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  cfg = config.hardware.samsung-gts8wifi;
  label = "NIXOS_GTS8";
in
{
  config = lib.mkIf cfg.enable {
    fileSystems."/" = {
      device = "/dev/disk/by-label/${label}";
      fsType = "ext4";
    };

    system.build.userdataImage = pkgs.callPackage "${modulesPath}/../lib/make-ext4-fs.nix" {
      storePaths = [ config.system.build.toplevel ];
      volumeLabel = label;
      compressImage = true;
      # The boot image boots init=/nix/var/nix/profiles/system/init, so the profile has
      # to exist before the first boot.
      populateImageCommands = ''
        mkdir -p ./files/nix/var/nix/profiles ./files/etc
        ln -s ${config.system.build.toplevel} ./files/nix/var/nix/profiles/system-1-link
        ln -s system-1-link ./files/nix/var/nix/profiles/system
        touch ./files/etc/NIXOS
      '';
    };

    # First boot: register the image's store paths with Nix and grow the filesystem.
    systemd.services.gts8wifi-first-boot = {
      description = "Register Nix store paths and grow the root filesystem";
      unitConfig = {
        DefaultDependencies = false;
        ConditionPathExists = "/nix-path-registration";
      };
      wantedBy = [ "sysinit.target" ];
      before = [
        "sysinit.target"
        "shutdown.target"
        "nix-daemon.socket"
        "nix-daemon.service"
      ];
      after = [ "local-fs.target" ];
      conflicts = [ "shutdown.target" ];
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${lib.getExe' pkgs.e2fsprogs "resize2fs"} /dev/disk/by-label/${label}
        ${lib.getExe' config.nix.package.out "nix-store"} --load-db < /nix-path-registration
        ${lib.getExe' config.nix.package.out "nix-env"} -p /nix/var/nix/profiles/system \
          --set /run/current-system
        rm /nix-path-registration
      '';
    };
  };
}
