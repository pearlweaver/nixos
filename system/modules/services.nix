{ config, pkgs, ... }: {
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.printing.enable = true;
  services.flatpak.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  nix.settings.experimental-features = [
    "flakes"
    "nix-command"
  ];

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  services.nginx = {
    enable = true;
    virtualHosts."notebook.local" = {
      locations."/" = {
        proxyPass = "http://127.0.0.1:8502";
        proxyWebsockets = true;
      };
    };
  };
}

