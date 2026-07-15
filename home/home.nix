{ config, pkgs, inputs, ... }: {
  imports = [
    ./modules/niri.nix
    ./modules/noctalia.nix
    ./modules/apps.nix
    ./modules/packages.nix
    ./modules/xdg.nix
    ./modules/session.nix
    ./modules/perla.nix
  ];

  home.username = "thedreamdev";
  home.homeDirectory = "/home/thedreamdev";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
}
