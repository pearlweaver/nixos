{ config, pkgs, ... }: {
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
  networking.nftables.enable = false;
  networking.firewall.enable = false;
  networking.hosts = {
    "127.0.0.1" = [ 
      "notebook.local"
      "immich.local" 
    ];
  };
}
