{ config, pkgs, ... }: {
  home.username = "thedreamdev";
  home.homeDirectory = "/home/thedreamdev";
  home.stateVersion = "25.11";

  nixpkgs.config.allowUnfree = true;

  home.packages = with pkgs; [
    # Apps
    discord
    vscodium
    obsidian
    spotify
    vesktop
    heroic
    godot_4
    libreoffice
    qbittorrent
    uget

    # Gaming
    unityhub

    # Dev
    lua
    love
    lua-language-server
    clang
    clang-tools
    dotnet-sdk_8

    # Hyprland
    hyprland
    hyprpicker
    eww
    awww
    grim
    slurp
    wl-clipboard
    wofi
    dunst
    hyprlock
    libnotify
  ];

  # Git
  programs.git = {
    enable = true;
    settings = {
      user.name = "pearlweaver";
      user.email = "37861423-pearlweaver@users.noreply.gitlab.com";
      push.autoSetupRemote = true;
      init.defaultBranch = "main";
    };
  };

  # Shell (Bash)
  programs.bash = {
    enable = true;
    shellAliases = {
      rebuild-system = "cd ~/nixos-config && sudo nixos-rebuild switch --flake .#nixos";
      rebuild-home = "cd ~/nixos-config && home-manager switch --flake .#thedreamdev";
      rebuild = "rebuild-system && rebuild-home";
      ll = "ls -la";
      ".." = "cd ..";
      "..." = "cd ../..";
      gs = "git status";
      gp = "git push";
      gc = "git commit -m";
      ga = "git add .";
    };
    bashrcExtra = ''
      export PATH=$HOME/.local/bin:$PATH
      export EDITOR=nvim
    '';
  };

  # Kitty
  programs.kitty = {
    enable = true;
    settings = {
      font_family = "Monocraft";
      font_size = 12;
      cursor_shape = "beam";
      cursor_trail = 1;
      background = "#1e1e2e";
      scrollback_lines = -1;
      enable_audio_bell = false;
      window_margin_width = 21;
      confirm_os_window_close = 0;
      tab_bar_edge = "top";
    };
  };

  # Hyprland
  wayland.windowManager.hyprland = {
    enable = true;
    extraConfig = builtins.readFile ./configs/hypr/hyprland.conf;
  };

  # EWW
  xdg.configFile = {
    "eww".source = ./configs/eww;
    "hypr".source = ./configs/hypr;
    "fastfetch".source = ./configs/fastfetch;
  };

  # Firefox
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

  # Neovim
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    withRuby = false;
    withPython3 = false;
  };

  programs.home-manager.enable = true;
}
