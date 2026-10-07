# nixpkgs' hexagonrpc at the git snapshot the pmOS package uses, with the seven patches
# that let the SM8450 sensor core rewrite its registry (queued upstream:
# https://github.com/linux-msm/hexagonrpc/issues/19). Same reasons as
# device/pmaports/hexagonrpcd/APKBUILD; drop this once a release carries them.
{
  lib,
  fetchFromGitHub,
  hexagonrpc,
}:

let
  patchDir = ../../device/pmaports/hexagonrpcd;
in
hexagonrpc.overrideAttrs (old: {
  version = "0.5.0-unstable-2026-08-24";
  src = fetchFromGitHub {
    owner = "linux-msm";
    repo = "hexagonrpc";
    rev = "598b591ae9da6a6cfe2ca5ea78998019ca6395ea";
    hash = "sha256-wr5x5NR/QVY/dMqpykNAc+iXYjUePmUEI+kMhqllzIU=";
  };
  patches = (old.patches or [ ]) ++ map (n: patchDir + "/${n}") (
    lib.sort lib.lessThan (
      lib.filter (lib.hasSuffix ".patch") (lib.attrNames (builtins.readDir patchDir))
    )
  );
})
