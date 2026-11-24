{ config, pkgs, inputs, ... }: {
  imports = [
    ./modules/apps.nix
    ./modules/packages.nix
    ./modules/xdg.nix
    ./modules/perla.nix
    ./modules/flutter.nix
    ./modules/cod-clients.nix
  ];

  home.username = "thedreamdev";
  home.homeDirectory = "/home/thedreamdev";
  home.stateVersion = "25.11";

  # Noctalia owns the bar in the other profile. Here the option tree only
  # exists so perla.nix's dmenu entry type-checks; the daemon must stay off or
  # it would fight ChillPill for org.freedesktop.Notifications.
  programs.noctalia.enable = false;

  xdg.configFile.niri-config.force = true;
  xdg.configFile."gtk-4.0/gtk.css".force = true;
  home.file."${config.xdg.configHome}/starship.toml".force = true;
}
