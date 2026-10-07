{
  description = "NixOS on the Samsung Galaxy Tab S8 (SM-X700, gts8wifi)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      buildSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      # aarch64 packages for this device, natively or cross-compiled from the build machine
      pkgsFor =
        system:
        import nixpkgs (
          {
            overlays = [ self.overlays.default ];
          }
          // (
            if system == "aarch64-linux" then
              { system = "aarch64-linux"; }
            else
              {
                localSystem = system;
                crossSystem = "aarch64-linux";
              }
          )
        );
    in
    {
      overlays.default = import ./nixos/overlay.nix;

      nixosModules = {
        samsung-gts8wifi = import ./nixos/modules/samsung-gts8wifi.nix;
        default = self.nixosModules.samsung-gts8wifi;
      };

      # An example system: Plasma 6 for the tablet. Build its images with
      #   nix build .#nixosConfigurations.gts8wifi.config.system.build.userdataImage
      #   nix build .#nixosConfigurations.gts8wifi.config.system.build.bootImage
      # (or gts8wifi-x86-kernel from an x86_64 machine, see docs/NIXOS.md)
      nixosConfigurations =
        let
          example =
            extra:
            lib.nixosSystem {
              modules = [
                self.nixosModules.default
                ./nixos/example/configuration.nix
                { nixpkgs.hostPlatform = "aarch64-linux"; }
                extra
              ];
            };
        in
        {
          gts8wifi = example { };
          # The same, with the kernel cross-compiled on an x86_64 build machine.
          gts8wifi-x86-kernel = example {
            hardware.samsung-gts8wifi.kernelBuildPlatform = "x86_64-linux";
          };
        };

      packages = lib.genAttrs buildSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          inherit (pkgs.gts8wifi)
            linux
            linux-7_2
            hexagonrpc
            device-support
            uniloader-src
            ;
          kernel-config = pkgs.gts8wifi.linux.configfile;
          kernel-config-7_2 = pkgs.gts8wifi.linux-7_2.configfile;
        }
      );
    };
}
