{ config, pkgs, ... }: {
  programs.kitty = {
    enable = true;
    settings = {
      font_family = "Monocraft";
      font_size = 12;
      cursor_shape = "beam";
      cursor_trail = 1;
      background = "#1e1e2e";
      scrollback_lines = -1;
      enable_audio_bell = false;
      window_margin_width = 21;
      confirm_os_window_close = 0;
      tab_bar_edge = "top";
    };
  };
}
