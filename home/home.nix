{ config, pkgs, inputs, ... }: {
  imports = [
    ./modules/niri.nix
    ./modules/noctalia.nix
    ./modules/apps.nix
    ./modules/packages.nix
    ./modules/xdg.nix
    ./modules/perla.nix
    ./modules/flutter.nix
  ];

  home.username = "thedreamdev";
  home.homeDirectory = "/home/thedreamdev";
  home.stateVersion = "25.11";

  xdg.configFile.niri-config.force = true;
  xdg.configFile."gtk-4.0/gtk.css".force = true;
  home.file."${config.xdg.configHome}/starship.toml".force = true;

  programs.home-manager.enable = true;
}
