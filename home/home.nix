{ config, pkgs, ... }: {
  imports = [
    ./modules/kitty.nix
    ./modules/git.nix
    ./modules/niri.nix
    ./modules/noctalia.nix
    ./modules/nvim.nix
    ./modules/yt-dlp.nix
    ./modules/prismlauncher.nix
    ./modules/fish.nix
    ./modules/fastfetch.nix
    ./modules/gtk.nix
    ./modules/qt6.nix
  ];

  home.username = "thedreamdev";
  home.homeDirectory = "/home/thedreamdev";
  home.stateVersion = "25.11";

  nixpkgs.config.allowUnfree = true;

  home.packages = with pkgs; [
    # Apps
    discord
    vscodium
    obsidian
    spotify
    vesktop
    heroic
    libreoffice
    qbittorrent
    uget
    nemo
    nwg-look
    adw-gtk3
    mousai
    komikku
    stremio-linux-shell

    # Terminal Apps
    yazi
    cava
    ani-cli

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

    # Important / Others
    xwayland-satellite
    reversal-icon-theme
    libsForQt5.qtstyleplugin-kvantum
    kdePackages.qtstyleplugin-kvantum
    kdePackages.qt6ct
  ];

  programs.home-manager.enable = true;
}
