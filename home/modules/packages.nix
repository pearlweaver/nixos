{ config, pkgs, ... }: {
  nixpkgs.config.allowUnfree = true;

  home.packages = with pkgs; [
    # Apps
    brave-origin
    discord
    obsidian
    spotify
    vesktop
    heroic
    libreoffice
    qbittorrent
    uget
    vscodium
    prismlauncher
    nwg-look
    adw-gtk3
    komikku
    stremio-linux-shell
    foliate
    zathura
    pinta
    blanket
    qimgv
    wine
    nocturne
    proton-vpn
    protontricks
    nautilus
    # KDE apps take their QPalette from KColorScheme via the KDE platform theme
    # (plasma-integration); without it they fall back to BreezeLight and ignore
    # both qt6ct and kdeglobals. Route the KDE apps to that platform theme so
    # they read the noctalia scheme, and keep qt6ct for the non-KDE Qt apps.
    kdePackages.plasma-integration
    (pkgs.symlinkJoin {
      name = "dolphin";
      paths = [ kdePackages.dolphin ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/dolphin \
          --unset QT_STYLE_OVERRIDE \
          --set QT_QPA_PLATFORMTHEME kde
      '';
    })
    (pkgs.symlinkJoin {
      name = "ark";
      paths = [ kdePackages.ark ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/ark \
          --unset QT_STYLE_OVERRIDE \
          --set QT_QPA_PLATFORMTHEME kde
      '';
    })
    (pkgs.symlinkJoin {
      name = "krita";
      paths = [ krita ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/krita \
          --unset QT_STYLE_OVERRIDE \
          --set QT_QPA_PLATFORMTHEME kde
      '';
    })
    stoat-desktop
    lsfg-vk
    lsfg-vk-ui

    # Terminal Apps
    yazi
    cava
    ani-cli
    spotdl
    ffmpeg

    # Dev
    blender
    aseprite
    godot_4
    unityhub
    lua
    love
    lua-language-server
    clang
    clang-tools
    dotnet-sdk_8
    gimp
    opencode
    nodejs
    obs-studio
    flutter
    android-studio
    android-tools
    cmake
    ninja

    # Important / Others
    playerctl
    xwayland-satellite
    reversal-icon-theme
    monocraft
    kdePackages.breeze
    libsForQt5.qtstyleplugin-kvantum
    kdePackages.qtstyleplugin-kvantum
    kdePackages.qt6ct
    catppuccin-qt5ct
    libsForQt5.qt5ct
    xdg-desktop-portal
    xdg-desktop-portal-gnome
    mpvpaper
    vulkan-tools
    qpdf
    papirus-folders
    papirus-icon-theme
    dxvk
    winetricks
    # wine64
  ];

  xdg.dataFile."vulkan/implicit_layer.d/VkLayer_LS_frame_generation.json".source =
    "${pkgs.lsfg-vk}/share/vulkan/implicit_layer.d/VkLayer_LS_frame_generation.json";

  nixpkgs.config.permittedInsecurePackages = [
     "electron-38.8.4"
     "pnpm-10.29.2"
  ];
}
