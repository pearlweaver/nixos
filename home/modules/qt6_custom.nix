{ config, pkgs, ... }:
let
  kvantumTheme = pkgs.catppuccin-kvantum.override {
    variant = "mocha"; # mocha / macchiato / frappe / latte
    accent = "lavender"; # blue / lavender / mauve / peach / pink / red / etc
  };
in {
  home.packages = [ kvantumTheme ]; # provides .kvconfig + .svg files

  qt = {
    enable = true;
    platformTheme.name = "qt6ct"; # tool to configure Qt theming
    style = {
      name = "kvantum"; # Qt widget renderer (svg-based)
      package = pkgs.kdePackages.qtstyleplugin-kvantum;
    };
  };

  # Symlink into ~/.local/share/Kvantum/ so Kvantum finds the theme files
  xdg.dataFile."Kvantum/catppuccin-mocha-lavender".source =
    "${kvantumTheme}/share/Kvantum/catppuccin-mocha-lavender";

  xdg.configFile = {
    "qt5ct/qt5ct.conf".text = ''
      [Appearance]
      custom_palette=false
      style=kvantum
    '';
    "qt6ct/qt6ct.conf".text = ''
      [Appearance]
      custom_palette=false
      style=kvantum
      standard_dialogs=default
    '';

    "kdeglobals".force = true;
    "kdeglobals".text = ''
      [General]
      Name=Custom Dark

      [Icons]
      Theme=reversal # Reversal purple-dark icon theme

      [Colors:View]
      BackgroundNormal=20,21,22 # #141516 file list / tree view background
      ForegroundNormal=205,214,244 # #cdd6f4 file list / tree view text
      BackgroundAlternate=24,24,37 # #181825 alternating row background

      [Colors:Window]
      BackgroundNormal=20,21,22 # #141516 window background
      ForegroundNormal=205,214,244 # #cdd6f4 window text

      [Colors:Button]
      BackgroundNormal=54,58,79 # #363a4f button background
      ForegroundNormal=205,214,244 # #cdd6f4 button text

      [Colors:Selection]
      BackgroundNormal=180,190,254 # #b4befe selection highlight
      ForegroundNormal=20,21,22 # #141516 text on selection

      [Colors:Tooltip]
      BackgroundNormal=24,24,37 # #181825 tooltip background
      ForegroundNormal=205,214,244 # #cdd6f4 tooltip text
    '';
  };

  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland;xcb"; # prefer Wayland, fallback X11
    QT_QPA_PLATFORMTHEME = "qt6ct"; # use qt6ct for Qt settings
    QT_STYLE_OVERRIDE = "kvantum"; # force Kvantum style
    KVANTUM_THEME = "catppuccin-mocha-lavender"; # active Kvantum theme
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1"; # compositor handles decorations
    KDE_SESSION_VERSION = "6"; # tell apps we're on KF6
  };
}
