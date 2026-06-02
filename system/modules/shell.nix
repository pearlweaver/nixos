let
  pkgs = import (builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/64c08a7ca051951c8eae34e3e3cb1e202fe36786.tar.gz";
    sha256 = "sha256:tpyBcxPpcQb8ukyNF7DoCwfSY3VPsxHoYwj00Cayv5o=";
  }) {};
in
pkgs.mkShell {
  packages = [
    (pkgs.python3.withPackages (python-pkgs: with python-pkgs; [
      pandas
      requests
      numpy
      matplotlib
      scipy
      scikit-image
      scikit-learn
    ]))
  ];
}