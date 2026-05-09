{ config, pkgs, ... }: {
  home.username = "thedreamdev";
  home.homeDirectory = "/home/thedreamdev";
  home.stateVersion = "25.11";

  home.packages = with pkgs; [
    discord
    vscodium
    obsidian
    spotify
    vesktop
    antigravity
    steam
    unityhub
    heroic
    opencode
    love #love2d lua
  ];

  programs.git = {
    enable = true;
    settings.user.name = "pearlweaver";
    settings.user.email = "37861423-pearlweaver@users.noreply.gitlab.com";
  };

  programs.firefox = {
    enable = true;
    configPath = "${config.xdg.configHome}/mozilla/firefox";
    package = pkgs.firefox.override {
      extraPrefsFiles = [(builtins.fetchurl {
        url = "https://raw.githubusercontent.com/MrOtherGuy/fx-autoconfig/master/program/config.js";
        sha256 = "1mx679fbc4d9x4bnqajqx5a95y1lfasvf90pbqkh9sm3ch945p40";
      })];
    };
  };

  programs.home-manager.enable = true;
  nixpkgs.config.allowUnfree = true;
}
