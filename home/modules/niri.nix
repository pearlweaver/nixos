{ config, pkgs, inputs, lib, ... }:

let
  noctalia = cmd: [ "noctalia" "msg" ] ++ (pkgs.lib.splitString " " cmd);
in {
  programs.niri = {
    settings = {
      spawn-at-startup = [
        { command = [ "noctalia" ]; }
        { command = [ "xwayland-satellite" ]; }
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

      outputs = {
        "eDP-1" = {
            scale = 1.0;
            position = { x = 0; y = 0; };
        };
        "HDMI-A-1" = {
            scale = 1.0;
            position = { x = 0; y = 0; };
        };
      };

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

      # blur = {
      #   passes = 2;
      #   offset = 3.0;
      #   noise = 0.03;
      #   saturation = 1.0;
      # };

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
              namespace = "noctalia-wallpaper";
            }
          ];
          place-within-backdrop = true;
        }
        {
          matches = [
            {
              namespace = "mpvpaper";
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
        "Mod+E".action.spawn = [ "nautilus" ];
        "Mod+Shift+E".action.spawn = [ "kitty" "-e" "yazi" ];
        "Mod+B".action.spawn = [ "app.zen_browser.zen" ];
        "Mod+D".action.spawn = [ "vesktop" ];
        "Mod+M".action.spawn = [ "nocturne" ];
        "Mod+C".action.spawn = [ "codium" ];
        "Mod+W".action.spawn = [ "libreoffice" ];
        "Mod+A".action.spawn = [ "noctalia" "msg" "panel-toggle" "wallpaper" ];
        "Mod+Shift+A".action.spawn = [ "noctalia" "msg" "panel-toggle" "noctalia/mpvpaper:picker" ];

				# Window Management
        "Mod+Q".action.close-window = {};
        "Mod+X".action.toggle-window-floating = {};
        "Mod+F".action.maximize-column = {};
        "Mod+F11".action.fullscreen-window = {};

        "Mod+R".action.switch-preset-column-width = {};
        "Mod+Shift+R".action.switch-preset-window-height = {};
        "Mod+Ctrl+Left".action.set-column-width = "-10%";
        "Mod+Ctrl+Right".action.set-column-width = "+10%";
        "Mod+Ctrl+Up".action.set-window-height = "-10%";
        "Mod+Ctrl+Down".action.set-window-height = "+10%";

        "Alt+Space".action.spawn = noctalia "panel-toggle launcher";
        "Mod+L".action.spawn = noctalia "session lock";
        "Ctrl+Alt+Delete".action.spawn = noctalia "panel-toggle session";
        "Mod+Shift+S".action = { screenshot = {}; };
        "Mod+V".action.spawn = noctalia "panel-toggle clipboard";

        # Focus
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
        "XF86AudioRaiseVolume".action.spawn  = noctalia "volume-up";
        "XF86AudioLowerVolume".action.spawn  = noctalia "volume-down";
        "XF86AudioMute".action.spawn = noctalia "volume-mute";
        "XF86AudioMicMute".action.spawn = noctalia "mic-mute";

        # Brightness
        "XF86MonBrightnessUp".action.spawn   = noctalia "brightness-up";
        "XF86MonBrightnessDown".action.spawn = noctalia "brightness-down";

        # Media
        "Mod+Shift+P".action.spawn = [ "playerctl" "play-pause" ];
        "Mod+Shift+N".action.spawn = [ "playerctl" "next" ];
        "Mod+Shift+B".action.spawn = [ "playerctl" "previous" ];
        "XF86AudioNext".action.spawn = [ "playerctl" "next" ];
        "XF86AudioPrev".action.spawn = [ "playerctl" "previous" ];
        "XF86AudioPlay".action.spawn = [ "playerctl" "play-pause" ];
        "XF86AudioPause".action.spawn = [ "playerctl" "play-pause" ];
        
        "Mod+Shift+Space".action.spawn = [ "perla" "hotkey" ];
      };
    };
  };
}
