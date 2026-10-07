# The flashable boot.img, as boot/build-boot-img.sh builds it: uniLoader with the kernel
# Image, the DTB (command line in /chosen/bootargs, since uniLoader passes none) and the
# initrd embedded, wrapped in an Android v4 boot image whose ramdisk is Samsung's own
# (ABL insists on it; take it from your firmware, see boot/README.md).
#
# Placement: the pmOS layout puts the initramfs at 0xb6915000, which leaves 22.9 MiB below
# the splash region; a NixOS initrd with the DSP firmware may not fit. ramdiskEntry
# "auto" tries that address first and falls back to 0x812000000 (free RAM after the
# kernel at 0x80ba00000, below 0x83ab00000), keeping the first layout that passes
# boot/audit-boot-layout.py against the DTB. The fallback has not been booted yet.
{
  lib,
  stdenv,
  buildPackages,
  uniloader-src,
}:

{
  kernel, # a kernel package with $kernel/Image and $kernel/dtbs
  dtb ? "qcom/sm8450-samsung-gts8wifi.dtb",
  initrd, # path to the (compressed) initrd
  bootargs, # complete kernel command line; replaces the DTS default
  stockRamdisk, # ramdisk of Samsung's boot.img
  ramdiskEntry ? "auto",
  partitionSize ? 96 * 1024 * 1024, # BOOT (sda25) on the SM-X700
  name ? "gts8wifi-boot.img",
}:

let
  pmosEntry = "0xb6915000";
  highEntry = "0x812000000";
  entries =
    if ramdiskEntry == "auto" then
      [
        pmosEntry
        highEntry
      ]
    else
      [ ramdiskEntry ];
in
stdenv.mkDerivation {
  inherit name;
  src = uniloader-src;

  depsBuildBuild = [ buildPackages.stdenv.cc ];
  nativeBuildInputs = with buildPackages; [
    bison
    flex
    dtc
    python3
    android-tools
  ];

  dontConfigure = true;
  dontFixup = true;

  # uniLoader stamps "(git-hash) - date" into its banner; keep it reproducible.
  GIT_VERSION_TAG = "a3933a2";
  BUILD_DATE = "1970-01-01 00:00:01";

  buildPhase = ''
    runHook preBuild
    export CROSS_COMPILE=${stdenv.cc.targetPrefix}
    export HOSTCC=${buildPackages.stdenv.cc.targetPrefix}cc
    export NM=${stdenv.cc.targetPrefix}nm

    cp ${kernel}/Image blob/Image
    cp ${kernel}/dtbs/${dtb} blob/dtb
    chmod u+w blob/dtb
    fdtput -t s blob/dtb /chosen bootargs ${lib.escapeShellArg bootargs}
    cp ${initrd} blob/ramdisk

    built=
    for entry in ${lib.concatStringsSep " " entries}; do
      make ARCH=aarch64 clean >/dev/null 2>&1 || true
      sed -i "s/^CONFIG_RAMDISK_ENTRY=.*/CONFIG_RAMDISK_ENTRY=$entry/" configs/gts8wifi_defconfig
      make ARCH=aarch64 gts8wifi_defconfig >/dev/null
      grep -qx "CONFIG_RAMDISK_ENTRY=$entry" .config
      make ARCH=aarch64 -j$NIX_BUILD_CORES >/dev/null
      if python3 ${../../boot/audit-boot-layout.py} \
          --kernel blob/Image --ramdisk blob/ramdisk --dtb blob/dtb \
          --loader-config .config --loader-elf uniLoader.o > layout-audit.txt; then
        built=$entry
        break
      fi
      echo "initramfs at $entry does not fit:"; cat layout-audit.txt
    done
    [ -n "$built" ] || { echo "no initramfs placement passed the layout audit" >&2; exit 1; }
    echo "initramfs placed at $built"

    mkbootimg --header_version 4 --os_version 12.0.0 --os_patch_level 2025-09 \
      --kernel uniLoader --ramdisk ${stockRamdisk} --cmdline "" -o boot.img
    size=$(stat -c %s boot.img)
    if [ "$size" -gt ${toString partitionSize} ]; then
      echo "boot.img is $size bytes, BOOT holds ${toString partitionSize}" >&2
      exit 1
    fi
    runHook postBuild
  '';

  installPhase = ''
    install -Dm644 boot.img $out/boot.img
    install -Dm644 layout-audit.txt $out/layout-audit.txt
    install -Dm644 .config $out/uniloader.config
    install -Dm644 blob/dtb $out/sm8450-samsung-gts8wifi.dtb
    fdtget -t s blob/dtb /chosen bootargs > $out/bootargs.txt
  '';

  meta = {
    description = "Flashable boot.img (uniLoader + kernel + initrd) for the Galaxy Tab S8";
    platforms = [ "aarch64-linux" ];
  };
}
