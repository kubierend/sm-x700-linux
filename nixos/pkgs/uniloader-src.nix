# uniLoader (GPL-2.0) at the commit boot/build-boot-img.sh uses, with the gts8wifi board.
{ fetchFromGitHub, applyPatches }:

applyPatches {
  name = "uniloader-gts8wifi-src";
  src = fetchFromGitHub {
    owner = "ivoszbg";
    repo = "uniLoader";
    rev = "a3933a280624b6f3cf4f60afb3766fdf34a4d78a";
    hash = "sha256-HFAFGl2YGrJp3B/oqnQm6E675/XcqbdFHU2SiqESrhc=";
  };
  patches = [ ../../boot/uniloader/0001-add-samsung-gts8wifi.patch ];
}
