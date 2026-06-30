{ lib, stdenv, fetchurl, dpkg, xdg-utils, coreutils
, alsa-lib, at-spi2-atk, at-spi2-core, atk, cairo, cups, dbus, expat
, fontconfig, freetype, gdk-pixbuf, glib, adwaita-icon-theme
, gsettings-desktop-schemas, gtk3, gtk4, libdrm, libx11, libGL
, libxkbcommon, libxscrnsaver, libxcomposite, libxcursor, libxdamage
, libxext, libxfixes, libxi, libxrandr, libxrender, libxshmfence
, libxtst, libuuid, libgbm, nspr, nss, pango, pipewire, udev, wayland
, libxcb, zlib, snappy, libkrb5, libpulseaudio, libva, qt6
, wrapGAppsHook3, buildPackages
}:

let
  rpath = lib.makeLibraryPath deps + ":" + lib.makeSearchPathOutput "lib" "lib64" deps;

  deps = [
    alsa-lib at-spi2-atk at-spi2-core atk cairo cups dbus expat
    fontconfig freetype gdk-pixbuf glib gtk3 gtk4 libdrm
    libx11 libGL libxkbcommon libxscrnsaver libxcomposite libxcursor
    libxdamage libxext libxfixes libxi libxrandr libxrender
    libxshmfence libxtst libuuid libgbm nspr nss pango pipewire
    udev wayland libxcb zlib snappy libkrb5
    libpulseaudio libva
    qt6.qtbase
  ];
in
stdenv.mkDerivation {
  pname = "brave-origin";
  version = "1.92.132";

  src = fetchurl {
    url = "https://github.com/brave/brave-browser/releases/download/v1.92.132/brave-origin_1.92.132_amd64.deb";
    hash = "sha256-AcBmHOE2op3Jh+DdgO59tCJygazoo5jwJJAK8la/mZM=";
  };

  dontConfigure = true;
  dontBuild = true;
  dontPatchELF = true;

  nativeBuildInputs = [ dpkg (wrapGAppsHook3.override { makeWrapper = buildPackages.makeShellWrapper; }) ];

  buildInputs = [ glib gsettings-desktop-schemas gtk3 gtk4 adwaita-icon-theme ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out $out/bin

    cp -R usr/share $out
    cp -R opt $out/opt

    export BINARYWRAPPER=$out/opt/brave.com/brave-origin/brave-origin

    substituteInPlace $BINARYWRAPPER \
        --replace-fail /bin/bash ${stdenv.shell}

    ln -sf $BINARYWRAPPER $out/bin/brave-origin

    for exe in $out/opt/brave.com/brave-origin/{brave,chrome_crashpad_handler}; do
        patchelf \
            --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
            --set-rpath "${rpath}" $exe
    done

    substituteInPlace $out/share/applications/brave-origin.desktop \
        --replace-fail /usr/bin/brave-origin-stable $out/bin/brave-origin
    substituteInPlace $out/share/applications/com.brave.Origin.desktop \
        --replace-fail /usr/bin/brave-origin-stable $out/bin/brave-origin

    icon_sizes=("16" "24" "32" "48" "64" "128" "256")
    for icon in ''${icon_sizes[*]}; do
        mkdir -p $out/share/icons/hicolor/$icon\x$icon/apps
        ln -sf $out/opt/brave.com/brave-origin/product_logo_$icon.png \
              $out/share/icons/hicolor/$icon\x$icon/apps/brave-origin.png 2>/dev/null || true
    done

    ln -sf ${xdg-utils}/bin/xdg-settings $out/opt/brave.com/brave-origin/xdg-settings
    ln -sf ${xdg-utils}/bin/xdg-mime $out/opt/brave.com/brave-origin/xdg-mime

    runHook postInstall
  '';

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix LD_LIBRARY_PATH : ${rpath}
      --prefix PATH : ${lib.makeBinPath [ xdg-utils coreutils ]}
      --set CHROME_WRAPPER brave-origin
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto}}"
      --add-flags "--disable-features=OutdatedBuildDetector"
    )
  '';

  meta = {
    homepage = "https://brave.com/";
    description = "Privacy-oriented browser for Desktop and Laptop computers (Origin variant)";
    longDescription = ''
      Brave Origin is the minimalist variant of Brave Browser without
      crypto/wallet features. Free on Linux.
    '';
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    license = lib.licenses.mpl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "brave-origin";
  };
}
