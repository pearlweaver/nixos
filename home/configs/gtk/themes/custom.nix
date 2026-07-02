{ config, pkgs, ... }:
let
  themePkg = pkgs.catppuccin-gtk.override {
    variant = "mocha"; # mocha / macchiato / frappe / latte
    accents = [ "lavender" ]; # blue / lavender / mauve / peach / pink / red / etc
  };
in {
  catppuccin.gtk.icon.enable = false;

  xdg.configFile."gtk-3.0/settings.ini".force = true;
  xdg.configFile."gtk-4.0/settings.ini".force = true;

  # GTK3 overrides, takes precedence over the theme package
  xdg.configFile."gtk-3.0/gtk.css".text = ''
    @define-color base_color #141516; # main background for entries and lists
    @define-color bg_color #141516; # generic background
    @define-color theme_bg_color #141516; # window and dialog background
    @define-color theme_base_color #141516; # text entry background
    @define-color theme_fg_color #cdd6f4; # default text color
    @define-color theme_text_color #cdd6f4; # text inside entries
    @define-color theme_selected_bg_color #b4befe; # highlight background
    @define-color theme_selected_fg_color #141516; # text on highlighted items
    @define-color theme_unfocused_bg_color #141516; # inactive window background
    @define-color theme_unfocused_fg_color #cdd6f4; # inactive window text
    @define-color theme_unfocused_base_color #141516;
    @define-color theme_unfocused_text_color #cdd6f4;
    @define-color theme_unfocused_selected_bg_color #b4befe;
    @define-color theme_unfocused_selected_fg_color #141516;
    @define-color borders #45475a; # widget borders
    @define-color unfocused_borders #585b70; # border on inactive widgets
    @define-color warning_color #fab387;
    @define-color error_color #f38ba8;
    @define-color success_color #a6e3a1;
    @define-color insensitive_bg_color #181825; # disabled widget background
    @define-color insensitive_fg_color #585b70; # disabled widget text
    @define-color insensitive_base_color #141516;
    @define-color dark_bg_color #11111b; # very dark areas, menu bars and such
    @define-color tooltip_bg_color #181825;
    @define-color tooltip_fg_color #cdd6f4;
    @define-color menu_bg_color #141516;
    @define-color menu_fg_color #cdd6f4;
    @define-color scrollbar_bg_color #141516;
    @define-color scrollbar_slider_color #585b70;
    @define-color link_color #89b4fa; # unvisited link color
    @define-color link_visited_color #cba6f7;
  '';

  # GTK4 overrides (same values as GTK3)
  xdg.configFile."gtk-4.0/gtk.css".text = ''
    @define-color base_color #141516;
    @define-color bg_color #141516;
    @define-color theme_bg_color #141516;
    @define-color theme_base_color #141516;
    @define-color theme_fg_color #cdd6f4;
    @define-color theme_text_color #cdd6f4;
    @define-color theme_selected_bg_color #b4befe;
    @define-color theme_selected_fg_color #141516;
    @define-color theme_unfocused_bg_color #141516;
    @define-color theme_unfocused_fg_color #cdd6f4;
    @define-color theme_unfocused_base_color #141516;
    @define-color theme_unfocused_text_color #cdd6f4;
    @define-color theme_unfocused_selected_bg_color #b4befe;
    @define-color theme_unfocused_selected_fg_color #141516;
    @define-color borders #45475a;
    @define-color unfocused_borders #585b70;
    @define-color warning_color #fab387;
    @define-color error_color #f38ba8;
    @define-color success_color #a6e3a1;
    @define-color insensitive_bg_color #181825;
    @define-color insensitive_fg_color #585b70;
    @define-color dark_bg_color #11111b;
    @define-color insensitive_base_color #141516;
    @define-color tooltip_bg_color #181825;
    @define-color tooltip_fg_color #cdd6f4;
    @define-color menu_bg_color #141516;
    @define-color menu_fg_color #cdd6f4;
    @define-color scrollbar_bg_color #141516;
    @define-color scrollbar_slider_color #585b70;
    @define-color link_color #89b4fa;
    @define-color link_visited_color #cba6f7;
  '';

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
}
