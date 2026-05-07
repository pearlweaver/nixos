{ config, pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    docker
    discord
    vscodium
    obsidian
    spotify
    vlc
    mpv
    fastfetch
    vesktop
    kitty
    neovim
    gcc
    antigravity
    raylib
    steam
    unityhub
    heroic
  ];

  programs.firefox.enable = true;
  programs.steam.enable = true;
}
