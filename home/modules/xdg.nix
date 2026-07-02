{ config, pkgs, ... }: {
  xdg.configFile."gtk-3.0/gtk.css".force = true;
  xdg.configFile."gtk-4.0/gtk.css".force = true;
  xdg.configFile."mimeapps.list".force = true;
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
}
