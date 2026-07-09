{ config, pkgs, ... }: {
  programs.kitty = {
    enable = true;
    settings = {
      font_family = "Monocraft";
      font_size = 12;

      cursor_shape = "beam";
      cursor_trail = 1;

      scrollback_lines = -1;

      enable_audio_bell = false;

      window_margin_width = 21;
      confirm_os_window_close = 0;

      tab_bar_edge = "top";

      foreground = "#ffffff";
      background = "#000000";

      selection_foreground = "#000000";
      selection_background = "#ffffff";

      cursor = "#ffffff";
      cursor_text_color = "#000000";

      url_color = "#ffffff";

      active_border_color = "#ffffff";
      inactive_border_color = "#444444";
      bell_border_color = "#888888";

      active_tab_foreground = "#000000";
      active_tab_background = "#ffffff";
      inactive_tab_foreground = "#888888";
      inactive_tab_background = "#111111";
      tab_bar_background = "#000000";

      mark1_foreground = "#000000";
      mark1_background = "#ffffff";
      mark2_foreground = "#000000";
      mark2_background = "#cccccc";
      mark3_foreground = "#000000";
      mark3_background = "#888888";

      color0 = "#000000";
      color8 = "#333333";
      color1 = "#555555";
      color9 = "#555555";
      color2 = "#666666";
      color10 = "#666666";
      color3 = "#888888";
      color11 = "#888888";
      color4 = "#999999";
      color12 = "#999999";
      color5 = "#bbbbbb";
      color13 = "#bbbbbb";
      color6 = "#dddddd";
      color14 = "#dddddd";
      color7 = "#ffffff";
      color15 = "#ffffff";
    };
  };
}
