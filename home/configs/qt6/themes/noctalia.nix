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
    "qt6ct/qt6ct.conf".text = ''
      [Appearance]
      custom_palette=true
      color_scheme_path=~/.config/qt6ct/colors/noctalia.conf
      icon_theme=Papirus-Dark
      standard_dialogs=default
      style=Fusion

      [Fonts]
      fixed=@Variant(\0\0\0\x87\0Latos-Regular,10,-1,5,50,0,0,0,0,0)General=@Variant(\0\0\0\x87\0Space Grotesk,11,-1,5,50,0,0,0,0,0)
    '';
  };

  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_STYLE_OVERRIDE = "qt6ct";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    KDE_SESSION_VERSION = "6";
  };
}
