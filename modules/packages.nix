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
    floorp-bin
  ];

  programs.firefox.enable = true;
  services.printing.enable = true;
  services.flatpak.enable = true;
}
