{ config, pkgs, inputs, ... }: {
  imports = [
    ./modules/apps.nix
    ./modules/packages.nix
    ./modules/xdg.nix
    ./modules/perla.nix
    ./modules/flutter.nix
    ./modules/sekaipop.nix
  ];

  home.username = "thedreamdev";
  home.homeDirectory = "/home/thedreamdev";
  home.stateVersion = "25.11";

  # Required because home/modules/noctalia.nix breaks the starship.toml store
  # symlink on the Niri session, leaving a real file behind. Without this the
  # sekaipop activation aborts on a clobber check and NOTHING links -- the
  # hyprland.lua below would never be created and Hyprland would boot its
  # default config. home/home.nix has carried this line for the same reason;
  # note it must be the home.file absolute-path form, not
  # xdg.configFile."starship.toml".force, which has no .source and fails to
  # evaluate.
  home.file."${config.xdg.configHome}/starship.toml".force = true;
}