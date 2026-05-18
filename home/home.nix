{ config, pkgs, ... }: {
  imports = [
    ./modules/kitty.nix
    ./modules/git.nix
    ./modules/niri.nix
    ./modules/noctalia.nix
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

    # Terminal Apps
    yazi

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
  ];

  programs.home-manager.enable = true;
}
