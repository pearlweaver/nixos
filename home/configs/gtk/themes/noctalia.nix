{ config, pkgs, ... }: {
  catppuccin.gtk.icon.enable = false;

  gtk = {
    enable = true;
    gtk2.enable = false;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    iconTheme = {
      name = "rose-pine";
      package = pkgs.rose-pine-icon-theme;
    };
    font = {
      name = "Monocraft";
      size = 11;
    };
  };
}
