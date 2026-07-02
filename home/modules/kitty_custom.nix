{ config, pkgs, ... }: {
  programs.kitty = {
    enable = true;
    settings = {
      font_family = "Monocraft";
      font_size = 12;
      cursor_shape = "beam";
      cursor_trail = 1;
      background = "#141516";
      selection_foreground = "#141516";
      cursor_text_color = "#141516";
      scrollback_lines = -1;
      enable_audio_bell = false;
      window_margin_width = 21;
      confirm_os_window_close = 0;
      tab_bar_edge = "top";
    };
  };
}
