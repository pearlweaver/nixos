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
      Name=Rosé Pine
      font=Monocraft,11,-1,0,400,0,0,0,0,0,0,0,0,0,0,1

      [Icons]
      Theme=reversal

      [Colors:View]
      BackgroundNormal=25,23,36
      ForegroundNormal=224,222,244
      BackgroundAlternate=31,29,46

      [Colors:Window]
      BackgroundNormal=25,23,36
      ForegroundNormal=224,222,244

      [Colors:Button]
      BackgroundNormal=38,35,58
      ForegroundNormal=224,222,244

      [Colors:Selection]
      BackgroundNormal=196,167,231
      ForegroundNormal=25,23,36

      [Colors:Tooltip]
      BackgroundNormal=31,29,46
      ForegroundNormal=144,140,170
    '';
  };

  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_QPA_PLATFORMTHEME = "qt6ct";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    KDE_SESSION_VERSION = "6";
  };
}
