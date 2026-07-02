{ config, pkgs, ... }: {
  imports = [
    ./services/tailscale.nix
    ./services/adguard-home.nix
    ./services/navidrome.nix
    ./services/avahi.nix
    ./services/nginx.nix
    # ./services/minecraft.nix
  ];

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
  networking.nftables.enable = false;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 80 443 3000 25565 ];
    allowedUDPPorts = [ 53 ];
    trustedInterfaces = [ "tailscale0" ];
  };

  networking.hosts = {
    "127.0.0.1" = [
      "notebook.local"
      "immich.local"
      "adguard.local"
      "navidrome.local"
    ];
  };
}
