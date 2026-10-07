# The device package's userland bits (device/pmaports/device-samsung-gts8wifi), laid out
# for NixOS: firmware/sensor setup scripts, the WCN6855 sleep hook, udev rules, UCM.
{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  coreutils,
  util-linux,
  lvm2,
  android-tools,
  zstd,
  xz,
  gawk,
  gnugrep,
  gnused,
  findutils,
  kmod,
}:

let
  repo = ../..;
  dev = repo + "/device/pmaports/device-samsung-gts8wifi";
in
stdenvNoCC.mkDerivation {
  pname = "gts8wifi-device-support";
  version = "1.0";

  src = lib.fileset.toSource {
    root = repo;
    fileset = lib.fileset.unions [
      dev
      (repo + "/tools/mk-ath11k-board2.py")
      (repo + "/tools/f2fs_extract.py")
    ];
  };

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ python3 ];

  installPhase = ''
    runHook preInstall
    d=device/pmaports/device-samsung-gts8wifi

    install -Dm755 $d/gts8wifi-firmware-setup $out/bin/gts8wifi-firmware-setup
    install -Dm755 $d/gts8wifi-sensors-setup $out/bin/gts8wifi-sensors-setup
    install -Dm755 $d/50-wcn6855-wifi $out/libexec/gts8wifi/wcn6855-sleep
    install -Dm644 tools/mk-ath11k-board2.py $out/libexec/gts8wifi/mk-ath11k-board2.py
    install -Dm644 tools/f2fs_extract.py $out/libexec/gts8wifi/f2fs_extract.py

    install -Dm644 $d/81-libssc-samsung-gts8wifi.rules -t $out/lib/udev/rules.d
    install -Dm644 $d/90-gts8wifi-hexagonrpcd-sdsp.rules -t $out/lib/udev/rules.d

    # The card driver is "sm8450", so UCM looks in conf.d/sm8450/<card name>.conf.
    install -Dm644 $d/ucm2/Samsung-Galaxy-Tab-S8.conf \
      $out/share/alsa/ucm2/conf.d/sm8450/Samsung-Galaxy-Tab-S8.conf
    install -Dm644 $d/ucm2/HiFi.conf $out/share/alsa/ucm2/Qualcomm/sm8450/gts8wifi/HiFi.conf
    runHook postInstall
  '';

  postFixup = ''
    patchShebangs $out/bin $out/libexec
    wrapProgram $out/bin/gts8wifi-firmware-setup \
      --set GTS8WIFI_LIBEXEC $out/libexec/gts8wifi \
      --prefix PATH : $out/bin:${
        lib.makeBinPath [
          python3
          coreutils
          util-linux
          lvm2
          android-tools
          zstd
          xz
          gawk
          gnugrep
          gnused
          kmod
        ]
      }
    wrapProgram $out/bin/gts8wifi-sensors-setup \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          util-linux
          gnused
          gnugrep
          findutils
        ]
      }
    wrapProgram $out/libexec/gts8wifi/wcn6855-sleep \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          util-linux
          gawk
          gnugrep
          kmod
        ]
      }
  '';

  meta = {
    description = "Galaxy Tab S8 (SM-X700) device support: firmware setup, sleep hook, udev, UCM";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
