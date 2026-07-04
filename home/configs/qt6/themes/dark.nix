{ config, pkgs, ... }: {
  qt = {
    enable = true;
    platformTheme.name = "qt6ct";
    style = {
      name = "kvantum";
      package = pkgs.kdePackages.breeze;
    };
  };

  xdg.configFile = {
    "qt5ct/qt5ct.conf".text = ''
      [Appearance]
      custom_palette=false
      style=breeze
    '';
    "qt6ct/qt6ct.conf".text = ''
      [Appearance]
      custom_palette=false
      style=breeze
      standard_dialogs=default
    '';

    "kdeglobals".force = true;
    "kdeglobals".text = ''
      [General]
      Name=Custom Dark
      font=Monocraft,11,-1,0,400,0,0,0,0,0,0,0,0,0,0,1

      [Icons]
      Theme=reversal

      [Colors:View]
      BackgroundNormal=30,30,30
      ForegroundNormal=204,204,204
      BackgroundAlternate=37,37,38

      [Colors:Window]
      BackgroundNormal=30,30,30
      ForegroundNormal=204,204,204

      [Colors:Button]
      BackgroundNormal=45,45,45
      ForegroundNormal=204,204,204

      [Colors:Selection]
      BackgroundNormal=187,134,252
      ForegroundNormal=30,30,30

      [Colors:Tooltip]
      BackgroundNormal=37,37,38
      ForegroundNormal=204,204,204
    '';
  };

  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_QPA_PLATFORMTHEME = "qt6ct";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    KDE_SESSION_VERSION = "6";
  };
}
