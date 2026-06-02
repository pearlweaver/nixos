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
  ];

  home.username = "thedreamdev";
  home.homeDirectory = "/home/thedreamdev";
  home.stateVersion = "25.11";

  home.sessionVariables = {
    QT_QPA_PLATFORMTHEME = "gtk3";
  };

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

    # Terminal Apps
    yazi
    cava
    ani-cli

    # Important
    xwayland-satellite

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
  ];

  programs.home-manager.enable = true;
}
