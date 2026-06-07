{ config, pkgs, inputs, ... }: {
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  programs.niri.enable = true;

  nix.settings.experimental-features = [
    "flakes"
    "nix-command"
  ];

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
}
