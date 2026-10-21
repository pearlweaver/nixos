{ lib, stdenvNoCC, fetchFromGitHub }:

# Tier 1 requirement in SekaiPop's check-deps.sh, which marks it manual because
# it is not packaged in Arch. Not in nixpkgs either. The repo is a single
# variable TTF with no build system, so installing the file is the whole build.
stdenvNoCC.mkDerivation {
  pname = "google-sans-flex";
  version = "unstable-2024-08-27";

  src = fetchFromGitHub {
    owner = "end-4";
    repo = "google-sans-flex";
    rev = "main";
    hash = "sha256-HMAS0L/Tsqyl1xI16cyIzg9LEb6Dyq91JY4wqFQV9Vs=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/fonts
    cp GoogleSansFlex-VariableFont_GRAD\,ROND\,opsz\,slnt\,wdth\,wght.ttf \
       $out/share/fonts/

    runHook postInstall
  '';

  meta = {
    homepage = "https://github.com/end-4/google-sans-flex";
    description = "Google Sans Flex variable font";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
  };
}