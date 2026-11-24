{ lib, hyprlandSession ? false, matugenTheme ? false, ... }: {
  imports = [
    ../configs/kitty/kitty.nix
    ../configs/git/git.nix
    ../configs/nvim/nvim.nix
    ../configs/yt-dlp/yt-dlp.nix
    ../configs/prismlauncher/prismlauncher.nix
    ../configs/fish/fish.nix
    ../configs/fastfetch/fastfetch.nix
  ] ++ lib.optionals (!hyprlandSession && !matugenTheme) [
    # Rose Pine GTK/Qt theming is only applied on the normal Niri session.
    # On the Hyprland session, SekaiPop themes GTK/Qt via matugen; on the
    # ChillPill Niri session, home/configs/matugen does the same. Skip these
    # to avoid conflicting `xdg.configFile`/`gtk.theme`/`qt.style` definitions.
    ../configs/gtk/gtk.nix
    ../configs/qt6/qt6.nix
  ] ++ lib.optionals matugenTheme [
    # apps.nix is the only aggregator that imports home/configs/*.
    ../configs/matugen/matugen.nix
  ];
}
