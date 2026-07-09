{ config, pkgs, ... }: {
  qt = {
    enable = true;
    platformTheme.name = "qt6ct";
    style = {
      name = "qt6ct";
      package = pkgs.kdePackages.breeze;
    };
  };

  xdg.configFile = {
    "kdeglobals".force = true;
    "kdeglobals".text = ''
      [General]
      Name=Void
      font=Monocraft Regular,11,-1,0,400,0,0,0,0,0,0,0,0,0,0,1

      [Icons]
      Theme=Adwaita

      [KDE]
      LookAndFeelPackage=org.kde.breezedark.desktop

      [UiSettings]
      ColorScheme=Void

      [Colors:View]
      BackgroundNormal=0,0,0
      ForegroundNormal=255,255,255
      BackgroundAlternate=10,10,10

      [Colors:Window]
      BackgroundNormal=0,0,0
      ForegroundNormal=255,255,255

      [Colors:Button]
      BackgroundNormal=17,17,17
      ForegroundNormal=255,255,255

      [Colors:Selection]
      BackgroundNormal=255,255,255
      ForegroundNormal=0,0,0

      [Colors:Tooltip]
      BackgroundNormal=17,17,17
      ForegroundNormal=204,204,204
    '';
  };

  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_STYLE_OVERRIDE = "qt6ct";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    KDE_SESSION_VERSION = "6";
  };
}
