
{ config, pkgs, ... }:
{
  xdg.configFile."gtk-3.0/settings.ini".force = true;
  xdg.configFile."gtk-4.0/settings.ini".force = true;
  
  gtk = {
    enable = true;

    gtk2.enable = false;
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
    enable = true;
    flavor = "mocha";
    gtk.icon.enable = false;
  };
}