{ config, pkgs, ... }: {
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_6_6;

  boot.kernelModules = [
    "binder_linux"
    "ashmem_linux"
    "br_netfilter"
    "ip_tables"
    "iptable_filter"
    "iptable_nat"
    "iptable_mangle"
  ];
}
