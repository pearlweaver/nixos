{ config, pkgs, inputs, ... }:

let
  noctalia = cmd: [
    "noctalia-shell" "ipc" "call"
  ] ++ (pkgs.lib.splitString " " cmd);
in {
  programs.niri = {
    settings = {
      spawn-at-startup = [
        { command = [ "noctalia-shell" ]; }
      ];

      binds = with config.lib.niri.actions; {
        "Mod+T".action.spawn = [ "kitty" ];
        "Alt+Space".action.spawn = noctalia "launcher toggle";
        "Mod+Q".action.close-window = {};
        "Mod+P".action.spawn = noctalia "lockScreen lock";

        # Volume
        "XF86AudioRaiseVolume".action.spawn = noctalia "volume increase";
        "XF86AudioLowerVolume".action.spawn = noctalia "volume decrease";
        "XF86AudioMute".action.spawn = noctalia "volume muteOutput";

        # Brightness
        "XF86MonBrightnessUp".action.spawn = noctalia "brightness increase";
        "XF86MonBrightnessDown".action.spawn = noctalia "brightness decrease";

        # Workspaces
        "Mod+1".action.focus-workspace = 1;
        "Mod+2".action.focus-workspace = 2;
        "Mod+3".action.focus-workspace = 3;
        "Mod+4".action.focus-workspace = 4;
        "Mod+5".action.focus-workspace = 5;

        "Mod+Shift+1".action.move-column-to-workspace = 1;
        "Mod+Shift+2".action.move-column-to-workspace = 2;
        "Mod+Shift+3".action.move-column-to-workspace = 3;
        "Mod+Shift+4".action.move-column-to-workspace = 4;
        "Mod+Shift+5".action.move-column-to-workspace = 5;

        # Navigation
        "Mod+H".action.focus-column-left = {};
        "Mod+L".action.focus-column-right = {};
        "Mod+J".action.focus-window-down = {};
        "Mod+K".action.focus-window-up = {};

        "Mod+Shift+H".action.move-column-left = {};
        "Mod+Shift+L".action.move-column-right = {};

        # Session
        "Mod+Shift+E".action.spawn = noctalia "sessionMenu toggle";
      };

      input = {
        keyboard.xkb.layout = "us";
        touchpad = {
          tap = true;
          natural-scroll = true;
        };
      };

      outputs."eDP-1" = {
        scale = 1.0;
      };
    };
  };
}
