{ config, pkgs, ... }: {
  nixpkgs.config.allowUnfree = true;

  home.packages = with pkgs; [
    # Apps
    brave-origin
    discord
    vscodium
    obsidian
    spotify
    vesktop
    heroic
    libreoffice
    qbittorrent
    uget
    thunar
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
    blender
    krita
    nautilus
    kdePackages.dolphin
    kdePackages.ark

    # Terminal Apps
    yazi
    cava
    ani-cli
    spotdl
    ffmpeg

    # Dev
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
    antigravity

    # Important / Others
    playerctl
    xwayland-satellite
    reversal-icon-theme
    libsForQt5.qtstyleplugin-kvantum
    kdePackages.qtstyleplugin-kvantum
    kdePackages.qt6ct
    xdg-desktop-portal
    xdg-desktop-portal-gnome
  ];

  nixpkgs.config.permittedInsecurePackages = [
     "electron-38.8.4"
     "pnpm-10.29.2"
  ];
}
