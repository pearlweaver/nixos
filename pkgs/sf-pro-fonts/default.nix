{ lib, stdenvNoCC, fetchzip }:

stdenvNoCC.mkDerivation {
  pname = "sf-pro-fonts";
  version = "1.0";

  src = fetchzip {
    url = "https://github.com/sahibjotsaggu/San-Francisco-Pro-Fonts/archive/refs/heads/master.zip";
    sha256 = "0k2g7bi714x28xpy5fhqbs2ay9z0accw69x7yrvmyz4awyfk2zjs";
  };

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/fonts/opentype $out/share/fonts/truetype

    find . -name '*.otf' -exec install -Dm644 {} -t $out/share/fonts/opentype \;
    find . -name '*.ttf' -exec install -Dm644 {} -t $out/share/fonts/truetype \;

    runHook postInstall
  '';

  meta = {
    description = "Apple SF Pro font family (Display, Text, Rounded)";
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    license = lib.licenses.unfree;
    platforms = lib.platforms.all;
  };
}