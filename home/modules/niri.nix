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

      input = {
        keyboard.xkb.layout = "us";
        touchpad = {
          tap = true;
          natural-scroll = false;
        };
        focus-follows-mouse = {
          enable = true;
          max-scroll-amount = "100%";
        };
      };

      outputs."eDP-1" = {
        scale = 1.0;
      };

      # Rounded corners + focus border
      layout = {
        gaps = 5;
        background-color = "transparent";
        border = {
          enable = false;
          width = 2;
          active.color = "#00000000";
          inactive.color = "#00000000";
        };
        shadow = {
          enable = false;
          softness = 40;
          offset = { x = 0; y = 3; };
          color = "#1a1a1aee";
        };
        focus-ring = {
          enable = true;
          width = 2;
          active.color = "#e8b8fc";
          inactive.color = "#00000000";
        };
      };

      prefer-no-csd = true;

      window-rules = [
          {
            geometry-corner-radius = {
                top-left = 10.0;
                top-right = 10.0;
                bottom-left = 10.0;
                bottom-right = 10.0;
            };
            clip-to-geometry = true;
          }
          {
            matches = [{ is-focused = false; }];
            opacity = 0.95;
          }
      ];

      layer-rules = [
        {
          matches = [
            {
              namespace = "noctalia-wallpaper-eDP-1";
            }
          ];
          place-within-backdrop = true;
        }
      ];

      overview = {
        backdrop-color = "#181825";
      };

      gestures = {
        hot-corners.enable = false;
      };

      binds = with config.lib.niri.actions; {
        # Apps
        "Mod+T".action.spawn = [ "kitty" ];
        "Mod+E".action.spawn = [ "kitty" "-e" "yazi" ];
        "Mod+B".action.spawn = [ "firefox" ];

        # Window management
        "Mod+Q".action.close-window = {};
        "Mod+V".action.toggle-window-floating = {};
        "Mod+F".action.maximize-column = {};

        # Noctalia
        "Alt+Space".action.spawn = noctalia "launcher toggle";
        "Mod+L".action.spawn = noctalia "lockScreen lock";
        "Ctrl+Alt+Delete".action.spawn = noctalia "sessionMenu toggle";
        "Mod+Shift+S".action = { screenshot = {}; };

        # Focus with arrow keys
        "Mod+Left".action.focus-column-left = {};
        "Mod+Right".action.focus-column-right = {};
        "Mod+Up".action.focus-window-up = {};
        "Mod+Down".action.focus-window-down = {};

        # Move windows
        "Mod+Shift+Left".action.move-column-left = {};
        "Mod+Shift+Right".action.move-column-right = {};
        "Mod+Shift+H".action.move-column-left = {};
        "Mod+Shift+L".action.move-column-right = {};

        # Workspaces
        "Mod+1".action.focus-workspace = 1;
        "Mod+2".action.focus-workspace = 2;
        "Mod+3".action.focus-workspace = 3;
        "Mod+4".action.focus-workspace = 4;
        "Mod+5".action.focus-workspace = 5;
        "Mod+6".action.focus-workspace = 6;

        "Mod+Shift+1".action.move-column-to-workspace = 1;
        "Mod+Shift+2".action.move-column-to-workspace = 2;
        "Mod+Shift+3".action.move-column-to-workspace = 3;
        "Mod+Shift+4".action.move-column-to-workspace = 4;
        "Mod+Shift+5".action.move-column-to-workspace = 5;
        "Mod+Shift+6".action.move-column-to-workspace = 6;

        # Volume
        "XF86AudioRaiseVolume".action.spawn = noctalia "volume increase";
        "XF86AudioLowerVolume".action.spawn = noctalia "volume decrease";
        "XF86AudioMute".action.spawn = noctalia "volume muteOutput";
        "XF86AudioMicMute".action.spawn = noctalia "volume muteInput";

        # Brightness
        "XF86MonBrightnessUp".action.spawn = noctalia "brightness increase";
        "XF86MonBrightnessDown".action.spawn = noctalia "brightness decrease";

        # Media
        "XF86AudioNext".action.spawn = [ "playerctl" "next" ];
        "XF86AudioPrev".action.spawn = [ "playerctl" "previous" ];
        "XF86AudioPlay".action.spawn = [ "playerctl" "play-pause" ];
        "XF86AudioPause".action.spawn = [ "playerctl" "play-pause" ];
      };
    };
  };
}
