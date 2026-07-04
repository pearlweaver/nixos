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

      foreground = "#cccccc";
      background = "#1e1e1e";

      selection_foreground = "#1e1e1e";
      selection_background = "#bb86fc";

      cursor = "#bb86fc";
      cursor_text_color = "#1e1e1e";

      url_color = "#bb86fc";

      active_border_color = "#cccccc";
      inactive_border_color = "#555555";
      bell_border_color = "#dcdcaa";

      active_tab_foreground = "#1e1e1e";
      active_tab_background = "#bb86fc";
      inactive_tab_foreground = "#cccccc";
      inactive_tab_background = "#252526";
      tab_bar_background = "#1a1a1a";

      mark1_foreground = "#1e1e1e";
      mark1_background = "#bb86fc";
      mark2_foreground = "#1e1e1e";
      mark2_background = "#9a5bd6";
      mark3_foreground = "#1e1e1e";
      mark3_background = "#569cd6";

      color0 = "#2d2d2d";
      color8 = "#3c3c3c";
      color1 = "#f44747";
      color9 = "#f44747";
      color2 = "#6a9955";
      color10 = "#6a9955";
      color3 = "#dcdcaa";
      color11 = "#dcdcaa";
      color4 = "#569cd6";
      color12 = "#569cd6";
      color5 = "#bb86fc";
      color13 = "#bb86fc";
      color6 = "#4ec9b0";
      color14 = "#4ec9b0";
      color7 = "#cccccc";
      color15 = "#999999";
    };
  };
}
