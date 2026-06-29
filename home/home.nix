{ config, pkgs, inputs, ... }: {
  imports = [
    ./modules/kitty.nix
    ./modules/git.nix
    ./modules/niri.nix
    ./modules/noctalia.nix
    ./modules/nvim.nix
    ./modules/yt-dlp.nix
    ./modules/prismlauncher.nix
    ./modules/fish.nix
    ./modules/fastfetch.nix
    ./modules/gtk.nix
    ./modules/qt6.nix
  ];

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
    libreoffice
    qbittorrent
    uget
    thunar
    nwg-look
    adw-gtk3
    komikku
    stremio-linux-shell
    stoat-desktop
    foliate
    zathura
    pinta
    blanket
    qimgv
    wine
    nocturne
    proton-vpn
    protontricks

    # Terminal Apps
    yazi
    cava
    ani-cli
    spotdl
    ffmpeg

    # Dev
    godot_4
    unityhub
    lua
    love
    lua-language-server
    clang
    clang-tools
    dotnet-sdk_8
    gimp
    opencode
    nodejs
    obs-studio
    antigravity

    # Important / Others
    xwayland-satellite
    reversal-icon-theme
    libsForQt5.qtstyleplugin-kvantum
    kdePackages.qtstyleplugin-kvantum
    kdePackages.qt6ct
    xdg-desktop-portal
    xdg-desktop-portal-gnome
  ];

  nixpkgs.config.permittedInsecurePackages = [
     "electron-38.8.4"
  ];

  home.sessionVariables = {
    XDG_CURRENT_DESKTOP = "niri";
  };
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      # Images
      "image/avif" = "qimgv.desktop";
      "image/bmp" = "qimgv.desktop";
      "image/gif" = "qimgv.desktop";
      "image/jpeg" = "qimgv.desktop";
      "image/png" = "qimgv.desktop";
      "image/svg+xml" = "qimgv.desktop";
      "image/tiff" = "qimgv.desktop";
      "image/webp" = "qimgv.desktop";
      "image/x-tga" = "qimgv.desktop";

      # Video
      "video/mp4" = "mpv.desktop";
      "video/mpeg" = "mpv.desktop";
      "video/x-matroska" = "mpv.desktop";
      "video/webm" = "mpv.desktop";
      "video/avi" = "mpv.desktop";
      "video/quicktime" = "mpv.desktop";
      "video/x-msvideo" = "mpv.desktop";
      "video/x-flv" = "mpv.desktop";

      # Audio
      "audio/mpeg" = "com.jeffser.Nocturne.desktop";
      "audio/ogg" = "com.jeffser.Nocturne.desktop";
      "audio/flac" = "com.jeffser.Nocturne.desktop";
      "audio/wav" = "com.jeffser.Nocturne.desktop";
      "audio/x-wav" = "com.jeffser.Nocturne.desktop";
      "audio/x-matroska" = "com.jeffser.Nocturne.desktop";
      "audio/webm" = "com.jeffser.Nocturne.desktop";

      # PDF/Documents
      "application/pdf" = "org.pwmt.zathura.desktop";

      # File manager
      "inode/directory" = "thunar.desktop";

      # Browser
      "x-scheme-handler/http" = "app.zen_browser.zen.desktop";
      "x-scheme-handler/https" = "app.zen_browser.zen.desktop";

      # Torrents
      "application/x-bittorrent" = "org.qbittorrent.qBittorrent.desktop";
      "x-scheme-handler/magnet" = "org.qbittorrent.qBittorrent.desktop";

      # Documents (LibreOffice)
      "application/msword" = "writer.desktop";
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = "writer.desktop";
      "application/vnd.oasis.opendocument.text" = "writer.desktop";
      "application/vnd.ms-excel" = "calc.desktop";
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = "calc.desktop";
      "application/vnd.oasis.opendocument.spreadsheet" = "calc.desktop";
      "application/vnd.ms-powerpoint" = "impress.desktop";
      "application/vnd.openxmlformats-officedocument.presentationml.presentation" = "impress.desktop";
      "application/vnd.oasis.opendocument.presentation" = "impress.desktop";
      "application/rtf" = "writer.desktop";

      # Code files
      "text/plain" = "codium.desktop";
      "text/html" = "codium.desktop";
      "text/css" = "codium.desktop";
      "text/javascript" = "codium.desktop";
      "text/x-c" = "codium.desktop";
      "text/x-c++" = "codium.desktop";
      "text/x-csharp" = "codium.desktop";
      "text/x-java" = "codium.desktop";
      "text/x-python" = "codium.desktop";
      "text/x-rust" = "codium.desktop";
      "text/x-typescript" = "codium.desktop";
      "text/x-json" = "codium.desktop";
      "text/xml" = "codium.desktop";
      "text/x-markdown" = "codium.desktop";
      "text/x-shellscript" = "codium.desktop";
      "text/x-yaml" = "codium.desktop";
      "text/x-toml" = "codium.desktop";
      "application/json" = "codium.desktop";
    };
  };

  programs.home-manager.enable = true;
}
