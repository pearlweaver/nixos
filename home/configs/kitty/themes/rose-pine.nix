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

      foreground = "#e0def4";
      background = "#191724";

      selection_foreground = "#191724";
      selection_background = "#c4a7e7";

      cursor = "#c4a7e7";
      cursor_text_color = "#191724";

      url_color = "#9ccfd8";

      active_border_color = "#e0def4";
      inactive_border_color = "#524f67";
      bell_border_color = "#f6c177";

      active_tab_foreground = "#191724";
      active_tab_background = "#c4a7e7";
      inactive_tab_foreground = "#908caa";
      inactive_tab_background = "#1f1d2e";
      tab_bar_background = "#191724";

      mark1_foreground = "#191724";
      mark1_background = "#c4a7e7";
      mark2_foreground = "#191724";
      mark2_background = "#9ccfd8";
      mark3_foreground = "#191724";
      mark3_background = "#eb6f92";

      color0 = "#26233a";
      color8 = "#403d52";
      color1 = "#eb6f92";
      color9 = "#eb6f92";
      color2 = "#31748f";
      color10 = "#31748f";
      color3 = "#f6c177";
      color11 = "#f6c177";
      color4 = "#9ccfd8";
      color12 = "#9ccfd8";
      color5 = "#c4a7e7";
      color13 = "#c4a7e7";
      color6 = "#ebbcba";
      color14 = "#ebbcba";
      color7 = "#e0def4";
      color15 = "#908caa";
    };
  };
}
