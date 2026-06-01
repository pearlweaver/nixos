{ config, pkgs, ... }: {
  xdg.desktopEntries.prismlauncher-cracked = {
    name = "Prism Launcher Cracked";
    exec = "/home/thedreamdev/.local/bin/prismlauncher-cracked";
    icon = "prismlauncher";
    categories = [ "Game" ];
  };
}