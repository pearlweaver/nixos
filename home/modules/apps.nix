{ lib, hyprlandSession ? false, ... }: {
  imports = [
    ../configs/kitty/kitty.nix
    ../configs/git/git.nix
    ../configs/nvim/nvim.nix
    ../configs/yt-dlp/yt-dlp.nix
    ../configs/prismlauncher/prismlauncher.nix
    ../configs/fish/fish.nix
    ../configs/fastfetch/fastfetch.nix
  ] ++ lib.optionals (!hyprlandSession) [
    # Rose Pine GTK/Qt theming is only applied on the normal Niri session.
    # On the Hyprland session, SekaiPop themes GTK/Qt via matugen
    # instead, so we skip importing these to avoid conflicting
    # `xdg.configFile`/`gtk.theme`/`qt.style` definitions.
    ../configs/gtk/gtk.nix
    ../configs/qt6/qt6.nix
  ];
}
