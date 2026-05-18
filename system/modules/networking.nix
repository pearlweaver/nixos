{ config, pkgs, ... }: {
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
  networking.nftables.enable = false;
  networking.firewall.enable = false;
}
