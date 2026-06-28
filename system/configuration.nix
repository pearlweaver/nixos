{ config, pkgs, inputs, lib, ... }: {
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
    ./modules/desktop.nix
    ./modules/appimage.nix
    ./modules/docker.nix
    ./modules/sops.nix
    ./modules/immich.nix
    ./modules/security.nix
    inputs.home-manager.nixosModules.home-manager
];

  systemd.services.navidrome.serviceConfig.ProtectHome = lib.mkForce false;
  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "25.11";
  nix.settings.auto-optimise-store = true;
  home-manager.backupFileExtension = "bak";

  # steam black screen fix
  nixpkgs.overlays = [
    inputs.niri-flake.overlays.niri
    (final: prev: {
      steam = prev.steam.override {
        extraArgs = "-cef-disable-gpu-compositing";
      };
    })
  ];

  # waydroid
  virtualisation.waydroid.enable = true;
  virtualisation.waydroid.package = pkgs.waydroid-nftables;
}
