{ config, pkgs, inputs, ... }: {
  imports = [
    ./modules/apps.nix
    ./modules/packages.nix
    ./modules/xdg.nix
    ./modules/perla.nix
    ./modules/flutter.nix
  ];

  home.username = "thedreamdev";
  home.homeDirectory = "/home/thedreamdev";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
}