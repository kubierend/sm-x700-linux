# Speaker topology: linux-firmware's SM8450-HDK one with the I2S data line moved from SD0
# to SD1, where the CS35L45 amplifiers listen (boot/tools/mk-tplg.py). The card loads it
# as qcom/sm8450/<card model>-tplg.bin.
{
  lib,
  runCommand,
  python3,
  linux-firmware,
}:

runCommand "gts8wifi-speaker-topology"
  {
    nativeBuildInputs = [ python3 ];
    meta.license = lib.licenses.unfreeRedistributableFirmware;
  }
  ''
    install -d $out/lib/firmware/qcom/sm8450
    python3 ${../../boot/tools/mk-tplg.py} \
      ${linux-firmware}/lib/firmware/qcom/sm8450/SM8450-HDK-tplg.bin \
      $out/lib/firmware/qcom/sm8450/Samsung-Galaxy-Tab-S8-tplg.bin
  ''
