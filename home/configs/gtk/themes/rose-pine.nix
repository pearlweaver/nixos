{ config, pkgs, ... }: {
  catppuccin.gtk.icon.enable = false;

  xdg.configFile."gtk-3.0/settings.ini".force = true;
  xdg.configFile."gtk-4.0/settings.ini".force = true;

  xdg.configFile."gtk-3.0/gtk.css".force = true;
  xdg.configFile."gtk-3.0/gtk.css".text = ''
    @define-color base_color #191724;
    @define-color bg_color #191724;
    @define-color theme_bg_color #191724;
    @define-color theme_base_color #191724;
    @define-color theme_fg_color #e0def4;
    @define-color theme_text_color #e0def4;
    @define-color theme_selected_bg_color #c4a7e7;
    @define-color theme_selected_fg_color #191724;
    @define-color theme_unfocused_bg_color #191724;
    @define-color theme_unfocused_fg_color #908caa;
    @define-color theme_unfocused_base_color #191724;
    @define-color theme_unfocused_text_color #908caa;
    @define-color theme_unfocused_selected_bg_color #c4a7e7;
    @define-color theme_unfocused_selected_fg_color #191724;
    @define-color borders #403d52;
    @define-color unfocused_borders #403d52;
    @define-color warning_color #f6c177;
    @define-color error_color #eb6f92;
    @define-color success_color #31748f;
    @define-color insensitive_bg_color #1f1d2e;
    @define-color insensitive_fg_color #6e6a86;
    @define-color insensitive_base_color #191724;
    @define-color dark_bg_color #191724;
    @define-color tooltip_bg_color #1f1d2e;
    @define-color tooltip_fg_color #908caa;
    @define-color menu_bg_color #191724;
    @define-color menu_fg_color #e0def4;
    @define-color scrollbar_bg_color #191724;
    @define-color scrollbar_slider_color #403d52;
    @define-color link_color #9ccfd8;
    @define-color link_visited_color #c4a7e7;
  '';

  xdg.configFile."gtk-4.0/gtk.css".force = true;
  xdg.configFile."gtk-4.0/gtk.css".text = ''
    @define-color base_color #191724;
    @define-color bg_color #191724;
    @define-color theme_bg_color #191724;
    @define-color theme_base_color #191724;
    @define-color theme_fg_color #e0def4;
    @define-color theme_text_color #e0def4;
    @define-color theme_selected_bg_color #c4a7e7;
    @define-color theme_selected_fg_color #191724;
    @define-color theme_unfocused_bg_color #191724;
    @define-color theme_unfocused_fg_color #908caa;
    @define-color theme_unfocused_base_color #191724;
    @define-color theme_unfocused_text_color #908caa;
    @define-color theme_unfocused_selected_bg_color #c4a7e7;
    @define-color theme_unfocused_selected_fg_color #191724;
    @define-color borders #403d52;
    @define-color unfocused_borders #403d52;
    @define-color warning_color #f6c177;
    @define-color error_color #eb6f92;
    @define-color success_color #31748f;
    @define-color insensitive_bg_color #1f1d2e;
    @define-color insensitive_fg_color #6e6a86;
    @define-color insensitive_base_color #191724;
    @define-color dark_bg_color #191724;
    @define-color tooltip_bg_color #1f1d2e;
    @define-color tooltip_fg_color #908caa;
    @define-color menu_bg_color #191724;
    @define-color menu_fg_color #e0def4;
    @define-color scrollbar_bg_color #191724;
    @define-color scrollbar_slider_color #403d52;
    @define-color link_color #9ccfd8;
    @define-color link_visited_color #c4a7e7;
  '';

  gtk = {
    enable = true;
    gtk2.enable = false;
    theme = {
      name = "rose-pine";
      package = pkgs.rose-pine-gtk-theme;
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
