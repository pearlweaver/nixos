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
      Name=Rose Pine
      font=Monocraft Regular,11,-1,0,400,0,0,0,0,0,0,0,0,0,0,1

      [Icons]
      Theme=Reversal-purple-dark

      [KDE]
      LookAndFeelPackage=org.kde.breezedark.desktop

      [UiSettings]
      ColorScheme=Rose Pine

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
    QT_STYLE_OVERRIDE = "qt6ct";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    KDE_SESSION_VERSION = "6";
  };
}