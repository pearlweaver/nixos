{ config, pkgs, inputs, ... }: {
  programs.noctalia = {
    enable = true;
    settings = {

      shell = {
        font_family = "Monocraft";
        telemetry_enabled = false;
        avatar_path = "/home/thedreamdev/Pictures/Random/stardust.jpg";

        shadow = {
            direction = "center";
            alpha = 0.00; # No Shadow
        };

        animation = {
          enabled = true;
          speed = 1.66;
        };

        panel = {
          transparency_mode = "soft";
          launcher_categories = true;
        };
      };

      theme = {
        mode = "dark";
        source = "builtin";
        builtin = "Catppuccin";
      };

      bar.default = {
        style = "floating";
        position = "top";
        background_opacity = 0.93;
        margin_vertical = 4;
        margin_horizontal = 4;
        frame_radius = 12;
        outer_corners = true;
        auto_hide = false;

        start = [ 
            "launcher" 
            "workspaces" 
            "audio_visualizer"
        ];
        
        center = [ 
            "media"
            "clock"
        ];

        end = [ 
            "tray" 
            "notifications" 
            "clipboard" 
            "network" 
            "bluetooth" 
            "volume" 
            "brightness" 
            "battery" 
            "control-center"
            "session" 
        ];
        
      };
      
      widget = {
        media = {
            hide_when_no_media = true;
            title_scroll = "on_hover";
        };

        workspaces = {
            hide_when_empty = true;
        };

        volume = {
            show_label = false;
        };

        audio_visualizer = {
            low_color  = "primary";
            high_color = "secondary";
        };

        battery = {
            display_mode = "graphic";
            show_label = false;
        };

        brightness = {
            show_label = false;
        };

        tray = {
            drawer = true;
        };

        audio = {
            enable_overdrive = true;
        };

        notifications.hide_when_no_unread = true;
        network.show_label = false;
      };

      dock = {
        enabled = true;
        position = "bottom";
        auto_hide = true;
        icon_size = 32;
      };

      launcher = {
        terminal_command = "kitty -e";
        position = "center";
        sort_by_most_used = true;
        view_mode = "list";
      };

      wallpaper = {
        enabled = true;
        fill_mode = "crop";
        transition = ["fade" "wipe" "disc" "stripes" "zoom" "honeycomb"];
        transition_duration = 1500;
        edge_smoothness = 0.3;
        transition_on_startup = true;
        directory = "/home/thedreamdev/Pictures/Wallpapers";
        default.path = "/home/thedreamdev/Pictures/Wallpapers/01.png";
      };

      location = {
        address = "Lahore, PK";
        auto_locate = false;
      };

      notifications = {
        enable_daemon = true;
        position = "top_right";
        layer = "top"; # use 'overlay' if you want them to appear in fullscreen mode
        duration_low = 3;
        duration_normal = 8;
        duration_critical = 15;
      };

      audio = {
        volume_step = 5;
        enable_overdrive = false;
      };

      brightness = {
        brightness_step = 5;
        enforce_minimum = true;
        enable_ddc = false;
      };

    };
  };
}
