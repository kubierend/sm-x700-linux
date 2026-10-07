# The X700 kernel: the same base, patches and config fragments as kernel/build.sh, plus
# nixos.config for what NixOS needs on top. base = "6.13" (verified on hardware) or "7.2".
{
  lib,
  stdenv,
  buildPackages,
  fetchurl,
  linuxManualConfig,
  bison,
  flex,
  perl,
  base ? "6.13",
  debug ? false,
  # Passed by NixOS (boot.kernelPatches, boot.kernel.features) through kernel.override.
  kernelPatches ? [ ],
  features ? { },
  randstructSeed ? "",
}:

let
  kernelDir = ../../kernel;

  bases = {
    "6.13" = {
      version = "6.13.0-rc3";
      # linux-next's localversion-next, then CONFIG_LOCALVERSION from sm8450.config
      modDirVersion = "6.13.0-rc3-next-20241220-sm8450";
      src = fetchurl {
        url = "https://github.com/sm8450-mainline/linux/archive/bf1d29fced6e156dd6090a9b6600a8c44259c114.tar.gz";
        hash = "sha256-1REzAKKlEXCI3tMINHYWAKN8C1YOSEUkII0bnf++19o=";
      };
      patchDir = kernelDir + "/patches";
      defconfigs = [ "defconfig" "sm8450.config" ];
      fragments = [ ];
    };
    "7.2" = {
      version = "7.2.9";
      modDirVersion = "7.2.9-sm8450";
      src = fetchurl {
        url = "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.9.tar.xz";
        hash = "sha256-tMXfvlGjZKbH8DhpIA+IyOH3dANTkAXxS3/GvJG42Lo=";
      };
      patchDir = kernelDir + "/patches-7.2";
      defconfigs = [ "defconfig" ];
      fragments = [ (kernelDir + "/config/sm8450.config") ];
    };
  };

  b = bases.${base} or (throw "linux-gts8wifi: unknown base ${base} (6.13 or 7.2)");

  patchNames = lib.sort lib.lessThan (
    lib.filter (n: lib.hasSuffix ".patch" n) (lib.attrNames (builtins.readDir b.patchDir))
  );
  overlayPatches = map (n: {
    name = lib.removeSuffix ".patch" n;
    patch = b.patchDir + "/${n}";
  }) patchNames;

  fragments =
    b.fragments
    ++ [
      (kernelDir + "/config/x700.config")
      ./nixos.config
    ]
    ++ lib.optional debug (kernelDir + "/config/x700-debug.config");

  # Generated exactly like kernel/build.sh does, with the toolchain that builds the
  # kernel (Kconfig probes the compiler).
  configfile = stdenv.mkDerivation {
    pname = "linux-gts8wifi-config";
    version = b.version;
    inherit (b) src;
    patches = map (p: p.patch) overlayPatches;
    depsBuildBuild = [ buildPackages.stdenv.cc ];
    nativeBuildInputs = [
      bison
      flex
      perl
    ];
    makeFlags = [
      "ARCH=arm64"
      "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
      "HOSTCC=${buildPackages.stdenv.cc.targetPrefix}cc"
    ];
    postPatch = "patchShebangs scripts";
    buildPhase = ''
      runHook preBuild
      make $makeFlags ${lib.concatStringsSep " " b.defconfigs}
      bash scripts/kconfig/merge_config.sh -m .config ${lib.escapeShellArgs fragments}
      make $makeFlags olddefconfig
      runHook postBuild
    '';
    installPhase = ''
      cp .config $out
    '';
  };
in
linuxManualConfig {
  inherit (b) version modDirVersion src;
  inherit configfile features randstructSeed;
  kernelPatches = overlayPatches ++ kernelPatches;
  # Read the generated .config so NixOS can check its kernel requirements.
  allowImportFromDerivation = true;
  extraMeta = {
    platforms = [ "aarch64-linux" ];
    description = "Linux for the Samsung Galaxy Tab S8 (SM-X700), ${base} base";
  };
}
