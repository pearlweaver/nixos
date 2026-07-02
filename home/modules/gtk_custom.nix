{ config, pkgs, ... }:
{
  xdg.configFile."gtk-3.0/settings.ini".force = true;
  xdg.configFile."gtk-4.0/settings.ini".force = true;

  xdg.configFile."gtk-3.0/gtk.css".text = ''
    @define-color theme_bg_color #141516;
    @define-color bg_color #141516;
    @define-color base_color #141516;
    @define-color theme_base_color #141516;
  '';

  xdg.configFile."gtk-4.0/gtk.css".text = ''
    @define-color theme_bg_color #141516;
    @define-color bg_color #141516;
    @define-color base_color #141516;
    @define-color theme_base_color #141516;
  '';

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
    autoEnable = true;
    enable = true;
    flavor = "mocha";
    gtk.icon.enable = false;
  };
}
