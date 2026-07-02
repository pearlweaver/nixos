{ config, pkgs, ... }: {
  programs.kitty = {
    enable = true;
    settings = {
      font_family = "Monocraft";
      font_size = 12;

      cursor_shape = "beam"; # beam / block / underline
      cursor_trail = 1;

      scrollback_lines = -1; # -1 = infinite

      enable_audio_bell = false;

      window_margin_width = 21;
      confirm_os_window_close = 0; # 0 = don't ask when closing window

      tab_bar_edge = "top";

      foreground = "#cdd6f4";
      background = "#141516";

      selection_foreground = "#141516";
      selection_background = "#f5e0dc";

      cursor = "#f5e0dc";
      cursor_text_color = "#141516"; # text behind the cursor

      # URL color when hovering
      url_color = "#f5e0dc";

      # Window border colors (when using kitty as a window)
      active_border_color = "#cdd6f4"; # focused window border
      inactive_border_color = "#6c7086"; # unfocused window border
      bell_border_color = "#f9e2af"; # border flash on bell

      # Tab bar colors
      active_tab_foreground = "#11111b";
      active_tab_background = "#cba6f7";
      inactive_tab_foreground = "#cdd6f4";
      inactive_tab_background = "#181825";
      tab_bar_background = "#11111b";

      # Text mark colors (used by kitty's mark/kitten system)
      mark1_foreground = "#141516";
      mark1_background = "#b4befe";
      mark2_foreground = "#141516";
      mark2_background = "#cba6f7";
      mark3_foreground = "#141516";
      mark3_background = "#74c7ec";

      # terminal colors
      color0 = "#45475a";
      color8 = "#585b70";
      color1 = "#f38ba8";
      color9 = "#f38ba8";
      color2 = "#a6e3a1";
      color10 = "#a6e3a1";
      color3 = "#f9e2af";
      color11 = "#f9e2af";
      color4 = "#89b4fa";
      color12 = "#89b4fa";
      color5 = "#f5c2e7";
      color13 = "#f5c2e7";
      color6 = "#94e2d5";
      color14 = "#94e2d5";
      color7 = "#bac2de";
      color15 = "#a6adc8";
    };
  };
}
