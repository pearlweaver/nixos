{ config, pkgs, ... }:
{
  qt = {
    enable = true;
    platformTheme.name = "kde";
    style = {
      name = "kvantum";
      package = pkgs.kdePackages.qtstyleplugin-kvantum;
    };
  };

  catppuccin.kvantum.enable = true;
  catppuccin.kvantum.flavor = "mocha";
  catppuccin.kvantum.accent = "lavender";

  xdg.configFile = {
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
    QT_STYLE_OVERRIDE = "kvantum";
    KVANTUM_THEME = "catppuccin-mocha-lavender";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    KDE_SESSION_VERSION = "6";
  };
}
