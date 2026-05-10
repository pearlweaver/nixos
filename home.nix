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
    lua
    love #love2d lua
    godot
    libreoffice
  ];

  programs.git = {
    enable = true;
    settings.user.name = "pearlweaver";
    settings.user.email = "37861423-pearlweaver@users.noreply.gitlab.com";
  };

  programs.kitty = {
    enable = true;
    settings = {
      font_family = "Monocraft";
      font_size = 12.0;
      cursor_shape = "beam";
      cursor_trail = 1;
      background = "#1e1e2e";
      scrollback_lines = -1; # Unlimited
      enable_audio_bell = false;
      window_margin_width = 21.75;
      confirm_os_window_close = 0;
      tab_bar_edge = "top";
    };
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
