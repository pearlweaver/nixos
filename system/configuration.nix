{ config, pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./modules/boot.nix
    ./modules/networking.nix
    ./modules/services.nix
    ./modules/audio.nix
    ./modules/locale.nix
    ./modules/users.nix
    ./modules/packages.nix
    ./modules/fonts.nix
    ./modules/flatpak.nix
    # ./modules/shell.nix
    ./modules/compatibility.nix
    ./modules/bluetooth.nix
  ];

  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "25.11";
}
