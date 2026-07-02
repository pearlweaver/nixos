
{ config, pkgs, ... }: let
  themePkg = pkgs.catppuccin-gtk.override {
    variant = "mocha";
    accents = [ "lavender" ];
  };
in {
  xdg.configFile."gtk-3.0/settings.ini".force = true;
  xdg.configFile."gtk-4.0/settings.ini".force = true;

  gtk = {
    enable = true;
    gtk2.enable = false;
    theme = {
      name = "catppuccin-mocha-lavender-standard";
      package = themePkg;
    };
    iconTheme = {
      name = "Reversal-purple-dark";
      package = pkgs.reversal-icon-theme;
    };
    font = {
      name = "Monocraft";
      size = 11;
    };
  };

  catppuccin = {
    autoEnable = true;
    enable = true;
    flavor = "mocha";
    gtk.icon.enable = false;
  };
}
