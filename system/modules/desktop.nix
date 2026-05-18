{ config, pkgs, ... }: {
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

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
    options = "--delete-older-than-than 5";
  };
}
