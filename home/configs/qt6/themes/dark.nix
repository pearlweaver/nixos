{ config, pkgs, ... }: {
  qt = {
    enable = true;
    platformTheme.name = "qtct";
    style.name = "kvantum";
  };

  home.packages = with pkgs; [
    qt6Packages.qt6kvantum
    libsForQt5.qtstyleplugin-kvantum
  ];

  xdg.configFile = {
    "qt5ct/qt5ct.conf".text = ''
      [Appearance]
      custom_palette=false
      icon_theme=Reversal-purple-dark
      style=kvantum
    '';

    "qt6ct/qt6ct.conf".text = ''
      [Appearance]
      custom_palette=false
      icon_theme=Reversal-dark
      standard_dialogs=default
      style=kvantum
    '';

    "Kvantum/kvantum.kvconfig".text = ''
      [General]
      theme=rose-pine
    '';
  };

  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
  };
}