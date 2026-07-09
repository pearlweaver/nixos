{ config, pkgs, ... }: {
  xdg.configFile."gtk-3.0/settings.ini".force = true;
  xdg.configFile."gtk-4.0/settings.ini".force = true;

  xdg.configFile."gtk-3.0/gtk.css".force = true;
  xdg.configFile."gtk-3.0/gtk.css".text = ''
    @define-color base_color #000000;
    @define-color bg_color #000000;
    @define-color theme_bg_color #000000;
    @define-color theme_base_color #000000;
    @define-color theme_fg_color #ffffff;
    @define-color theme_text_color #ffffff;
    @define-color theme_selected_bg_color #ffffff;
    @define-color theme_selected_fg_color #000000;
    @define-color theme_unfocused_bg_color #0a0a0a;
    @define-color theme_unfocused_fg_color #888888;
    @define-color theme_unfocused_base_color #0a0a0a;
    @define-color theme_unfocused_text_color #888888;
    @define-color theme_unfocused_selected_bg_color #888888;
    @define-color theme_unfocused_selected_fg_color #000000;
    @define-color borders #333333;
    @define-color unfocused_borders #222222;
    @define-color warning_color #888888;
    @define-color error_color #555555;
    @define-color success_color #777777;
    @define-color insensitive_bg_color #111111;
    @define-color insensitive_fg_color #444444;
    @define-color insensitive_base_color #0a0a0a;
    @define-color dark_bg_color #000000;
    @define-color tooltip_bg_color #111111;
    @define-color tooltip_fg_color #cccccc;
    @define-color menu_bg_color #0a0a0a;
    @define-color menu_fg_color #ffffff;
    @define-color scrollbar_bg_color #000000;
    @define-color scrollbar_slider_color #444444;
    @define-color link_color #ffffff;
    @define-color link_visited_color #aaaaaa;
  '';

  xdg.configFile."gtk-4.0/gtk.css".force = true;
  xdg.configFile."gtk-4.0/gtk.css".text = ''
    @define-color base_color #000000;
    @define-color bg_color #000000;
    @define-color theme_bg_color #000000;
    @define-color theme_base_color #000000;
    @define-color theme_fg_color #ffffff;
    @define-color theme_text_color #ffffff;
    @define-color theme_selected_bg_color #ffffff;
    @define-color theme_selected_fg_color #000000;
    @define-color theme_unfocused_bg_color #0a0a0a;
    @define-color theme_unfocused_fg_color #888888;
    @define-color theme_unfocused_base_color #0a0a0a;
    @define-color theme_unfocused_text_color #888888;
    @define-color theme_unfocused_selected_bg_color #888888;
    @define-color theme_unfocused_selected_fg_color #000000;
    @define-color borders #333333;
    @define-color unfocused_borders #222222;
    @define-color warning_color #888888;
    @define-color error_color #555555;
    @define-color success_color #777777;
    @define-color insensitive_bg_color #111111;
    @define-color insensitive_fg_color #444444;
    @define-color insensitive_base_color #0a0a0a;
    @define-color dark_bg_color #000000;
    @define-color tooltip_bg_color #111111;
    @define-color tooltip_fg_color #cccccc;
    @define-color menu_bg_color #0a0a0a;
    @define-color menu_fg_color #ffffff;
    @define-color scrollbar_bg_color #000000;
    @define-color scrollbar_slider_color #444444;
    @define-color link_color #ffffff;
    @define-color link_visited_color #aaaaaa;
  '';

  gtk = {
    enable = true;
    gtk2.enable = false;
    gtk4.theme = config.gtk.theme;
    theme = {
      name = "rose-pine";
      package = pkgs.rose-pine-gtk-theme;
    };
    iconTheme = {
      name = "Adwaita";
    };
    font = {
      name = "Monocraft";
      size = 11;
    };
  };
}
