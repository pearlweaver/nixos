{ lib
, stdenv
, autoPatchelfHook
, makeWrapper
, makeDesktopItem
, copyDesktopItems
, libxkbcommon
, libxcb
, libX11
, libXcursor
, libXi
, libXrandr
, libGL
, vulkan-loader
, wayland
}:

let
  desktopItem = makeDesktopItem {
    name = "horizon-launcher";
    exec = "horizon-launcher";
    desktopName = "Horizon Launcher";
    comment = "Horizon game launcher";
    categories = [ "Game" ];
    terminal = false;
  };
in
stdenv.mkDerivation {
  pname = "horizon-launcher";
  version = "latest";

  src = ./horizon-launcher-linux-x86_64.tar.gz;

  sourceRoot = ".";

  nativeBuildInputs = [ autoPatchelfHook makeWrapper copyDesktopItems ];
  buildInputs = [
    libxkbcommon
    libxcb
    libX11
    libXcursor
    libXi
    libXrandr
    libGL
    vulkan-loader
    wayland
    stdenv.cc.cc.lib
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 horizon-launcher $out/bin/.horizon-launcher-unwrapped
    makeWrapper $out/bin/.horizon-launcher-unwrapped $out/bin/horizon-launcher \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [
        libxkbcommon
        libxcb
        libX11
        libXcursor
        libXi
        libXrandr
        libGL
        vulkan-loader
        wayland
        stdenv.cc.cc.lib
      ]}
    runHook postInstall
  '';

  desktopItems = [ desktopItem ];

  meta = with lib; {
    description = "Horizon game launcher";
    platforms = [ "x86_64-linux" ];
    mainProgram = "horizon-launcher";
  };
}
