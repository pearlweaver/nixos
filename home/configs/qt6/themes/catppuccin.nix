{ config, pkgs, ... }:
{
  qt = {
    enable = true;
    platformTheme.name = "qt6ct";
    style = {
      name = "kvantum";
      package = pkgs.kdePackages.qtstyleplugin-kvantum;
    };
  };

  catppuccin.kvantum.enable = true;
  catppuccin.kvantum.flavor = "mocha";
  catppuccin.kvantum.accent = "lavender";

  xdg.configFile = {
    "qt5ct/qt5ct.conf".text = ''
      [Appearance]
      custom_palette=false
      style=kvantum

      [Fonts]
      fixed="Monocraft,11,-1,0,400,0,0,0,0,0,0,0,0,0,0,1,Regular"
      general="Monocraft,11,-1,0,400,0,0,0,0,0,0,0,0,0,0,1,Regular"
    '';
    "qt6ct/qt6ct.conf".text = ''
      [Appearance]
      custom_palette=false
      style=kvantum
      standard_dialogs=default

      [Fonts]
      fixed="Monocraft,11,-1,0,400,0,0,0,0,0,0,0,0,0,0,1,Regular"
      general="Monocraft,11,-1,0,400,0,0,0,0,0,0,0,0,0,0,1,Regular"
    '';
    "kdeglobals".force = true;
    "kdeglobals".text = ''
      [General]
      Name=Catppuccin Mocha Lavender
      font=Monocraft,11,-1,0,400,0,0,0,0,0,0,0,0,0,0,1

      [Icons]
      Theme=reversal

      [Colors:View]
      BackgroundNormal=30,30,46
      ForegroundNormal=205,214,244
      BackgroundAlternate=24,24,37

      [Colors:Window]
      BackgroundNormal=24,24,37
      ForegroundNormal=205,214,244

      [Colors:Button]
      BackgroundNormal=54,58,79
      ForegroundNormal=205,214,244

      [Colors:Selection]
      BackgroundNormal=180,190,254
      ForegroundNormal=30,30,46

      [Colors:Tooltip]
      BackgroundNormal=24,24,37
      ForegroundNormal=205,214,244
    '';
  };

  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_QPA_PLATFORMTHEME = "qt6ct";
    QT_STYLE_OVERRIDE = "kvantum";
    KVANTUM_THEME = "catppuccin-mocha-lavender";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    KDE_SESSION_VERSION = "6";
  };
}
