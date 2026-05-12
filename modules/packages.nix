{ config, pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    docker
    vlc
    mpv
    fastfetch
    kitty
    neovim
    raylib
    gcc
    clang
    clang-tools
    btop
    dotnet-sdk_8
    mesa-demos
    mono
    python3
    zip
    unzip
    unrar
  ];

  programs.firefox.enable = true;
  programs.steam.enable = true;
}
