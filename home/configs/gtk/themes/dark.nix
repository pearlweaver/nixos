{ config, pkgs, ... }: {
  catppuccin.gtk.icon.enable = false;

  xdg.configFile."gtk-3.0/settings.ini".force = true;
  xdg.configFile."gtk-4.0/settings.ini".force = true;

  xdg.configFile."gtk-3.0/gtk.css".force = true;
  xdg.configFile."gtk-3.0/gtk.css".text = ''
    @define-color base_color #1e1e1e;
    @define-color bg_color #1e1e1e;
    @define-color theme_bg_color #1e1e1e;
    @define-color theme_base_color #1e1e1e;
    @define-color theme_fg_color #cccccc;
    @define-color theme_text_color #cccccc;
    @define-color theme_selected_bg_color #bb86fc;
    @define-color theme_selected_fg_color #1e1e1e;
    @define-color theme_unfocused_bg_color #1e1e1e;
    @define-color theme_unfocused_fg_color #cccccc;
    @define-color theme_unfocused_base_color #1e1e1e;
    @define-color theme_unfocused_text_color #cccccc;
    @define-color theme_unfocused_selected_bg_color #bb86fc;
    @define-color theme_unfocused_selected_fg_color #1e1e1e;
    @define-color borders #3c3c3c;
    @define-color unfocused_borders #555555;
    @define-color warning_color #dcdcaa;
    @define-color error_color #f44747;
    @define-color success_color #6a9955;
    @define-color insensitive_bg_color #252526;
    @define-color insensitive_fg_color #555555;
    @define-color insensitive_base_color #1e1e1e;
    @define-color dark_bg_color #1a1a1a;
    @define-color tooltip_bg_color #252526;
    @define-color tooltip_fg_color #cccccc;
    @define-color menu_bg_color #1e1e1e;
    @define-color menu_fg_color #cccccc;
    @define-color scrollbar_bg_color #1e1e1e;
    @define-color scrollbar_slider_color #555555;
    @define-color link_color #bb86fc;
    @define-color link_visited_color #9a5bd6;
  '';

  xdg.configFile."gtk-4.0/gtk.css".force = true;
  xdg.configFile."gtk-4.0/gtk.css".text = ''
    @define-color base_color #1e1e1e;
    @define-color bg_color #1e1e1e;
    @define-color theme_bg_color #1e1e1e;
    @define-color theme_base_color #1e1e1e;
    @define-color theme_fg_color #cccccc;
    @define-color theme_text_color #cccccc;
    @define-color theme_selected_bg_color #bb86fc;
    @define-color theme_selected_fg_color #1e1e1e;
    @define-color theme_unfocused_bg_color #1e1e1e;
    @define-color theme_unfocused_fg_color #cccccc;
    @define-color theme_unfocused_base_color #1e1e1e;
    @define-color theme_unfocused_text_color #cccccc;
    @define-color theme_unfocused_selected_bg_color #bb86fc;
    @define-color theme_unfocused_selected_fg_color #1e1e1e;
    @define-color borders #3c3c3c;
    @define-color unfocused_borders #555555;
    @define-color warning_color #dcdcaa;
    @define-color error_color #f44747;
    @define-color success_color #6a9955;
    @define-color insensitive_bg_color #252526;
    @define-color insensitive_fg_color #555555;
    @define-color insensitive_base_color #1e1e1e;
    @define-color dark_bg_color #1a1a1a;
    @define-color tooltip_bg_color #252526;
    @define-color tooltip_fg_color #cccccc;
    @define-color menu_bg_color #1e1e1e;
    @define-color menu_fg_color #cccccc;
    @define-color scrollbar_bg_color #1e1e1e;
    @define-color scrollbar_slider_color #555555;
    @define-color link_color #bb86fc;
    @define-color link_visited_color #9a5bd6;
  '';

  gtk = {
    enable = true;
    gtk2.enable = false;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
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
