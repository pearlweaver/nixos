{ config, pkgs, lib, inputs, ... }: {
  xdg.configFile."noctalia/templates/kitty.conf".text = ''
    color0 {{colors.terminal_normal_black.default.hex}}
    color1 {{colors.terminal_normal_red.default.hex}}
    color2 {{colors.terminal_normal_green.default.hex}}
    color3 {{colors.terminal_normal_yellow.default.hex}}
    color4 {{colors.terminal_normal_blue.default.hex}}
    color5 {{colors.terminal_normal_magenta.default.hex}}
    color6 {{colors.terminal_normal_cyan.default.hex}}
    color7 {{colors.terminal_normal_white.default.hex}}
    color8 {{colors.terminal_bright_black.default.hex}}
    color9 {{colors.terminal_bright_red.default.hex}}
    color10 {{colors.terminal_bright_green.default.hex}}
    color11 {{colors.terminal_bright_yellow.default.hex}}
    color12 {{colors.terminal_bright_blue.default.hex}}
    color13 {{colors.terminal_bright_magenta.default.hex}}
    color14 {{colors.terminal_bright_cyan.default.hex}}
    color15 {{colors.terminal_bright_white.default.hex}}

    cursor                {{colors.terminal_cursor.default.hex}}
    cursor_text_color     {{colors.terminal_cursor_text.default.hex}}
    background            {{colors.terminal_background.default.hex}}
    foreground            {{colors.terminal_foreground.default.hex}}
    selection_foreground  {{colors.terminal_selection_fg.default.hex}}
    selection_background  {{colors.terminal_selection_bg.default.hex}}
    active_border_color   {{colors.primary.default.hex}}
    inactive_border_color {{colors.surface_variant.default.hex}}
    url_color             {{colors.primary.default.hex}}

    active_tab_foreground   {{colors.on_primary.default.hex}}
    active_tab_background   {{colors.primary.default.hex}}
    inactive_tab_foreground {{colors.on_surface_variant.default.hex}}
    inactive_tab_background {{colors.surface_variant.default.hex}}
    cursor_trail_color      {{colors.on_surface_variant.default.hex}}
  '';

  xdg.configFile."noctalia/templates/niri.kdl".text = ''
    layout {

        focus-ring {
            active-color   "{{colors.primary.default.hex}}"
            inactive-color "{{colors.surface.default.hex}}"
            urgent-color   "{{colors.error.default.hex}}"
        }

        border {
            active-color   "{{colors.primary.default.hex}}"
            inactive-color "{{colors.surface.default.hex}}"
            urgent-color   "{{colors.error.default.hex}}"
        }

        tab-indicator {
            active-color   "{{colors.primary.default.hex}}"
            inactive-color "{{colors.primary_container.default.hex}}"
            urgent-color   "{{colors.error.default.hex}}"
        }

        insert-hint {
            color "{{colors.primary.default.hex}}80"
        }
    }

    recent-windows {
        highlight {
            active-color "{{colors.primary.default.hex}}"
            urgent-color "{{colors.error.default.hex}}"
        }
    }
  '';

  home.activation.noctaliaThemeFixup = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    _break_store_symlink() {
      local path="$1"
      if [ -L "$path" ]; then
        local target
        target=$(readlink -f "$path")
        cp --remove-destination "$target" "$path"
      fi
      if [ -f "$path" ]; then
        chmod u+rw "$path"
      else
        mkdir -p "$(dirname "$path")"
        : >"$path"
      fi
    }

    _break_store_symlink "$HOME/.config/niri/config.kdl"
    _break_store_symlink "$HOME/.config/starship.toml"

    niri_cfg="$HOME/.config/niri/config.kdl"
    if [ -f "$niri_cfg" ] && ! grep -q 'include "noctalia.kdl"' "$niri_cfg"; then
      printf '\n%s\n' 'include "noctalia.kdl"' >>"$niri_cfg"
    fi
  '';

  programs.noctalia = {
    enable = true;
    settings = {

      shell = {
        font_family = "Monocraft";
        telemetry_enabled = false;
        avatar_path = "/home/thedreamdev/Pictures/Random/pic.jpg";

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
        source = "wallpaper";
        wallpaper_scheme = "m3-content";

        templates = {
          enable_builtin_templates = true;
          builtin_ids = [ "gtk3" "gtk4" "qt" "niri" "starship" ];
          enable_community_templates = true;
          community_ids = [ "vscode" ];
          user.kitty = {
            input_path = "$XDG_CONFIG_HOME/noctalia/templates/kitty.conf";
            output_path = "$XDG_CONFIG_HOME/kitty/themes/noctalia.conf";
            post_hook = "pkill -USR1 kitty || true";
          };
          user.niri = {
            input_path = "$XDG_CONFIG_HOME/noctalia/templates/niri.kdl";
            output_path = "$XDG_CONFIG_HOME/niri/noctalia.kdl";
          };
        };
      };

      bar.default = {
        style = "floating";
        position = "top";
        background_opacity = 0.55;
        margin_vertical = 4;
        margin_horizontal = 4;
        frame_radius = 12;
        outer_corners = true;
        auto_hide = false;
        corner_radius = 80;

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
        reserve_space = false;
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

      idle = {
        pre_action_fade_seconds = 2.0;
        behavior = {
          screen-off = {
            timeout = 300;
            action = "screen_off";
            enable = true;
          };
          lock = {
            timeout = 360;
            action = "lock";
            enable = true;
          };
          # Commented out because I want my tailscale and adguard setup to work when sleeping as well
          # suspend = {
          #   timeout = 600;
          #   action = "lock_and_suspend";
          #   enable = true;
          # };
        };
      };

      plugins = {
        enabled = [ "noctalia/mpvpaper" ];
        settings."noctalia/mpvpaper" = {
          video_directory = "/home/thedreamdev/Pictures/Wallpapers";
          mute = true;
          hardware_decode = true;
          auto_pause = true;
          mpv_options = "vf=scale=1920:1080:flags=lanczos hwdec=vaapi";
        };
      };
    };
  };
}
