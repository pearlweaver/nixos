{ config, pkgs, lib, ... }: {
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;
}
