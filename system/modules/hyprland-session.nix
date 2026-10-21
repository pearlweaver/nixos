{ config, pkgs, lib, ... }: {
  # NixOS-side glue for the SekaiPop Hyprland generation.
  #
  # Deliberately NOT set here, because system/modules/packages.nix already sets
  # them for every output including this one:
  #   programs.hyprland.enable  (line 46)
  #   programs.xwayland.enable   (line 47)
  # Those bring the Hyprland package, the Lua stub (pathsToLink /share/hypr),
  # the cap_sys_nice wrapper, xdg-desktop-portal-hyprland and the display
  # manager session entry.

  # hypr/hyprland/execs.lua starts gnome-keyring-daemon, and check-deps.sh lists
  # it as a desktop-layer dependency. No other module in this config enables it.
  services.gnome.gnome-keyring.enable = true;

  # xdg-desktop-portal's unit carries `Requisite=graphical-session.target`.
  # With withUWSM = false, nothing in a hand-rolled Hyprland session ever
  # activates that target, so the portal fails with "result 'dependency'" and
  # the shell logs "Failed to register with host portal". The target refuses
  # *manual* starts but honours dependency ones, so pulling it into
  # default.target is enough. This costs nothing on the Niri generation, which
  # gets its graphical session from the display manager instead.
  systemd.user.targets.graphical-session.wantedBy = [ "default.target" ];

  # The shell is its own notification daemon and polkit agent. It claims those
  # D-Bus names at startup, so if a second one were active it would lose the
  # fight. Noctalia is the Niri-session equivalent and must not run here --
  # the generation has no noctalia module imported at all.
  assertions = [
    {
      assertion = !config.programs.niri.enable;
      message = "The sekaipop generation runs Hyprland; programs.niri.enable must be false (forced in flake.nix).";
    }
  ];
}