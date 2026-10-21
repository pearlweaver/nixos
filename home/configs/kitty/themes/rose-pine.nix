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
    };

    # Colours are owned by SekaiPop's app theming, not this file. Home Manager
    # makes kitty.conf a read-only /nix/store symlink, so app-theme.sh can
    # write ~/.config/kitty/sekaipop-colors.conf but cannot append the include
    # that loads it -- so we seed both lines here. The marker line is the exact
    # string app-theme.sh's `status` greps for, so keep the two in sync
    # (see scripts/theming/app-theme.sh in the SekaiPop source).
    extraConfig = ''
      # sekaipop: managed block, removed by Settings -> Desktop -> App colours (revert)
      include sekaipop-colors.conf
    '';
  };
}
