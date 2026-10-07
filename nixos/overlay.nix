final: prev: {
  gts8wifi = final.lib.makeScope final.newScope (self: {
    linux = self.callPackage ./pkgs/linux.nix { kernelPatches = [ ]; };
    linux-7_2 = self.callPackage ./pkgs/linux.nix {
      base = "7.2";
      kernelPatches = [ ];
    };

    hexagonrpc = self.callPackage ./pkgs/hexagonrpc.nix { inherit (prev) hexagonrpc; };

    # Scripts, udev rules, UCM profile and the speaker topology (built from linux-firmware).
    device-support = self.callPackage ./pkgs/device-support.nix { };
    speaker-topology = self.callPackage ./pkgs/speaker-topology.nix { };

    uniloader-src = self.callPackage ./pkgs/uniloader-src.nix { };

    # boot.img: uniLoader{Image, DTB, initrd} in an Android v4 image with Samsung's ramdisk.
    mkBootImage = self.callPackage ./pkgs/boot-image.nix { };
  });
}
