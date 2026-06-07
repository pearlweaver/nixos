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
      ColorScheme=CatppuccinMochaLavender
      Name=Catppuccin Mocha Lavender

      [Background:Normal]
      BackgroundNormal=30,30,46

      [Colors:View]
      BackgroundNormal=30,30,46
      ForegroundNormal=205,214,244

      [Colors:Window]
      BackgroundNormal=17,17,27
      ForegroundNormal=205,214,244

      [Colors:Button]
      BackgroundNormal=43,44,66
      ForegroundNormal=205,214,244

      [Colors:Selection]
      BackgroundNormal=180,190,254
      ForegroundNormal=17,17,27
    '';
  };

  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_QPA_PLATFORMTHEME = "qt6ct";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
  };
}
