{ inputs, pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    docker
    vlc
    mpv
    fastfetch
    kitty
    neovim
    raylib
    gcc
    clang
    clang-tools
    btop
    dotnet-sdk_8
    mesa-demos
    mono
    python3
    zip
    unzip
    unrar
    waydroid
    gnome-system-monitor
    age
    sops
    ssh-to-age

    inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  nixpkgs.config.permittedInsecurePackages = [
     "electron-38.8.4"
  ];

  programs.firefox.enable = true;
  programs.steam.enable = true;
  virtualisation.waydroid.enable = true;
  programs.hyprland.enable = true;
  programs.xwayland.enable = true;
  programs.fish.enable = true;

  programs.bash = {
    interactiveShellInit = ''
      if grep -qv fish /proc/$PPID/comm && [[ $SHLVL == 1 ]]; then
        # Dynamically updates your environment path mapping pointers
        SHELL=${pkgs.fish}/bin/fish
        exec fish
      fi
    '';
  };
}
