{ config, pkgs, ... }: {
  catppuccin.gtk.icon.enable = false;

  xdg.configFile."gtk-3.0/settings.ini".force = true;
  xdg.configFile."gtk-4.0/settings.ini".force = true;

  gtk = {
    enable = true;
    gtk2.enable = false;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    iconTheme = {
      name = "noctalia-folders";
      package = pkgs.papirus-icon-theme;
    };
    font = {
      name = "Monocraft";
      size = 11;
    };
  };
}
