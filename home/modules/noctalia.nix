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

    window-rule {
        match app-id="^codium$"
        opacity 0.95
        background-effect {
            blur true
        }
    }

    window-rule {
        match app-id="^org.gnome.Nautilus$"
        opacity 0.95
        background-effect {
            blur true
        }
    }
  '';

  xdg.configFile."noctalia/templates/zen-userchrome.css".text = ''
    /* Matugen Zen Browser Theme */
    :root {
      --zen-primary-color: {{colors.primary_container.default.hex}} !important;
      --toolbarbutton-icon-fill: {{colors.primary.default.hex}} !important;
      --toolbar-field-color: {{colors.on_background.default.hex}} !important;
      --tab-selected-textcolor: {{colors.primary.default.hex}} !important;
      --toolbar-color: {{colors.on_background.default.hex}} !important;
      --arrowpanel-color: {{colors.on_background.default.hex}} !important;
      --arrowpanel-background: {{colors.surface_container.default.hex}} !important;
      --sidebar-text-color: {{colors.on_background.default.hex}} !important;
      --zen-main-browser-background: {{colors.background.default.hex}} !important;
      --zen-main-browser-background-toolbar: {{colors.background.default.hex}} !important;
    }

    #zen-browser-background {
      --zen-main-browser-background: {{colors.background.default.hex}} !important;
      --zen-background-opacity: 1 !important;
    }

    #zen-toolbar-background {
      --zen-main-browser-background-toolbar: {{colors.background.default.hex}} !important;
      --zen-background-opacity: 1 !important;
    }

    .sidebar-placesTree {
      background-color: {{colors.surface_container.default.hex}} !important;
    }

    #zen-workspaces-button {
      background-color: {{colors.surface_container.default.hex}} !important;
    }

    #TabsToolbar {
      background-color: {{colors.background.default.hex}} !important;
    }

    .urlbar-background {
      background-color: {{colors.surface_container.default.hex}} !important;
    }

    .urlbar-input::selection {
      color: {{colors.on_primary.default.hex}} !important;
      background-color: {{colors.primary.default.hex}} !important;
    }

    .urlbarView-url {
      color: {{colors.on_surface_variant.default.hex}} !important;
    }

    toolbar .toolbarbutton-1 {
      &:not([disabled]) {
        &:is([open], [checked])
          > :is(
            .toolbarbutton-icon,
            .toolbarbutton-text,
            .toolbarbutton-badge-stack
          ) {
          fill: {{colors.primary.default.hex}}
        }
      }
    }

    #zen-appcontent-navbar-container {
      background-color: {{colors.background.default.hex}} !important;
    }

    #PanelUI-menu-button .toolbarbutton-icon,
    #downloads-button .toolbarbutton-icon,
    #unified-extensions-button .toolbarbutton-icon {
      fill: {{colors.primary.default.hex}} !important;
      color: {{colors.primary.default.hex}} !important;
    }

    #PanelUI-menu-button .toolbarbutton-badge-stack,
    #downloads-button .toolbarbutton-badge-stack,
    #unified-extensions-button .toolbarbutton-badge-stack {
      fill: {{colors.primary.default.hex}} !important;
      color: {{colors.primary.default.hex}} !important;
    }

    toolbar .toolbarbutton-1 > .toolbarbutton-icon {
      fill: {{colors.primary.default.hex}} !important;
    }
  '';

  xdg.configFile."noctalia/templates/zen-usercontent.css".text = ''
    /* Matugen Zen Browser - about: pages theme */

    /* Override Firefox's built-in in-content CSS variables */
    :root {
      /* NEW design tokens (Firefox 130+) */
      --text-color: {{colors.on_surface.default.hex}} !important;
      --background-color-canvas: {{colors.surface.default.hex}} !important;
      --background-color-box: {{colors.surface_dim.default.hex}} !important;
      --text-color-secondary: {{colors.on_surface_variant.default.hex}} !important;
      --border-color: {{colors.surface.default.hex}} !important;

      /* Accent / Links */
      --in-content-link-color: {{colors.primary.default.hex}} !important;
      --in-content-link-color-hover: {{colors.primary.default.hex}} !important;
      --in-content-focus-outline-color: {{colors.primary.default.hex}} !important;

      /* Primary button */
      --in-content-primary-button-background: {{colors.primary.default.hex}} !important;
      --in-content-primary-button-text-color: {{colors.on_primary.default.hex}} !important;
      --in-content-button-background: {{colors.surface_container.default.hex}} !important;
      --in-content-button-background-hover: {{colors.surface_container_high.default.hex}} !important;
      --in-content-button-background-active: {{colors.surface_container_highest.default.hex}} !important;
      --in-content-button-text-color: {{colors.on_surface.default.hex}} !important;
      --in-content-button-border-color: {{colors.surface.default.hex}} !important;

      /* Backgrounds & surfaces */
      --in-content-bg: {{colors.surface.default.hex}} !important;
      --in-content-bg-hover: {{colors.surface_container.default.hex}} !important;
      --in-content-bg-active: {{colors.surface_container_high.default.hex}} !important;
      --in-content-border: {{colors.surface.default.hex}} !important;
      --in-content-deemphasized-text: {{colors.on_surface_variant.default.hex}} !important;
      --in-content-text: {{colors.on_surface.default.hex}} !important;
      --in-content-text-disabled: {{colors.on_surface_variant.default.hex}} !important;

      /* Headers */
      --in-content-heading-color: {{colors.on_surface.default.hex}} !important;

      /* Input fields */
      --in-content-input-bg: {{colors.surface_dim.default.hex}} !important;
      --in-content-input-border-color: {{colors.surface.default.hex}} !important;
      --in-content-input-border-color-focus: {{colors.primary.default.hex}} !important;

      /* Checkboxes */
      --checkbox-checked-bgcolor: {{colors.primary.default.hex}} !important;
      --checkbox-checked-border-color: {{colors.primary.default.hex}} !important;
      --checkbox-unchecked-border-color: {{colors.surface.default.hex}} !important;

      /* Radios */
      --radio-checked-bgcolor: {{colors.primary.default.hex}} !important;
      --radio-checked-border-color: {{colors.primary.default.hex}} !important;

      /* Menus / Arrow panels */
      --arrowpanel-background: {{colors.surface_container.default.hex}} !important;
      --arrowpanel-color: {{colors.on_surface.default.hex}} !important;
      --arrowpanel-border-color: {{colors.surface.default.hex}} !important;
    }

    /* Selection highlight */
    ::selection {
      color: {{colors.on_primary.default.hex}} !important;
      background: {{colors.primary.default.hex}} !important;
    }

    /* === Global body/html for about: pages === */
    @-moz-document url-prefix("about:preferences"),
                   url-prefix("about:addons"),
                   url-prefix("about:config"),
                   url-prefix("about:profiles"),
                   url-prefix("about:logins"),
                   url-prefix("about:performance"),
                   url-prefix("about:rights"),
                   url-prefix("about:support"),
                   url-prefix("about:translation"),
                   url-prefix("chrome://mozapps/content/extensions/") {

      body,
      html {
        background-color: var(--background-color-canvas) !important;
        color: var(--text-color) !important;
      }

      /* === Links === */
      a,
      a.link {
        color: var(--in-content-link-color) !important;
      }
      a:hover,
      a.link:hover {
        color: var(--in-content-link-color-hover) !important;
      }

      /* === Headings (uses --text-color in modern Firefox) === */
      h1, h2, h3, h4, h5, h6,
      moz-page-header,
      groupbox > label > h2,
      groupbox h2 {
        color: var(--text-color) !important;
      }

      /* === Buttons === */
      button {
        background-color: var(--in-content-button-background) !important;
        color: var(--text-color) !important;
        border-color: var(--in-content-button-border-color) !important;
      }
      button:hover {
        background-color: var(--in-content-button-background-hover) !important;
      }
      button:active {
        background-color: var(--in-content-button-background-active) !important;
      }
      button[primary],
      button.primary,
      .primary-button {
        background-color: var(--in-content-primary-button-background) !important;
        color: var(--in-content-primary-button-text-color) !important;
      }
      button[primary]:hover,
      button.primary:hover,
      .primary-button:hover {
        opacity: 0.9;
      }

      /* === Inputs === */
      input[type="text"],
      input[type="password"],
      input[type="email"],
      input[type="url"],
      input[type="search"],
      input[type="number"],
      textarea,
      select {
        background-color: var(--in-content-input-bg) !important;
        color: var(--text-color) !important;
        border-color: var(--in-content-input-border-color) !important;
      }
      input[type="text"]:focus,
      input[type="password"]:focus,
      input[type="email"]:focus,
      input[type="url"]:focus,
      input[type="search"]:focus,
      input[type="number"]:focus,
      textarea:focus,
      select:focus {
        border-color: var(--in-content-input-border-color-focus) !important;
        box-shadow: 0 0 0 1px var(--in-content-focus-outline-color) !important;
      }

      /* === Checkboxes & Radios === */
      input[type="checkbox"],
      input[type="radio"] {
        accent-color: var(--in-content-focus-outline-color) !important;
      }

      /* === Tables === */
      table {
        border-color: var(--border-color) !important;
      }
      th, td {
        border-color: var(--border-color) !important;
        color: var(--text-color) !important;
      }
      th {
        background-color: var(--background-color-box) !important;
      }

      /* === Groups & sections === */
      .group,
      .section,
      .subcategory,
      setting-group,
      groupbox {
        border-color: var(--border-color) !important;
      }

      /* === Highlighted / selected items === */
      .selected,
      [selected="true"],
      .highlight {
        background-color: var(--background-color-box) !important;
        color: var(--text-color) !important;
      }

      /* === Cards & panels === */
      .card,
      .panel,
      .subview-body,
      .category,
      [role="tab"] {
        background-color: var(--background-color-box) !important;
        color: var(--text-color) !important;
        border-color: var(--border-color) !important;
      }
      .card:hover,
      .panel:hover {
        background-color: var(--in-content-bg-active) !important;
      }

      /* === Scrollbar === */
      scrollbar {
        background-color: var(--background-color-canvas) !important;
      }
      scrollbar thumb {
        background-color: var(--border-color) !important;
      }

      /* === About:preferences sidebar === */
      #categories {
        background-color: var(--background-color-canvas) !important;
      }
      .category-label {
        color: var(--text-color) !important;
      }

      /* === About:addons specific === */
      .addon-name,
      .addon-version,
      .addon-description,
      .addon-detail {
        color: var(--text-color) !important;
      }
    }
  '';

  xdg.configFile."noctalia/templates/midnight-discord.css".text = ''
    /**
     * @name midnight
     * @description A dark, rounded discord theme.
     * @author refact0r
     * @version 1.6.2
     * @invite nz87hXyvcy
     * @website https://github.com/refact0r/midnight-discord
     * @source https://github.com/refact0r/midnight-discord/blob/master/midnight.theme.css
     * @authorId 508863359777505290
     * @authorLink https://www.refact0r.dev
    */

    /* IMPORTANT: make sure to enable dark mode in discord settings for the theme to apply properly!!! */

    @import url('https://refact0r.github.io/midnight-discord/build/midnight.css');

    /* customize things here */
    :root {
      /* font, change to 'gg sans' for default discord font*/
      --font: 'figtree';

      /* top left corner text */
      --corner-text: 'Midnight';

      /* color of status indicators and window controls */
        --online-indicator: {{colors.inverse_primary.default.hex}};     /* change to #23a55a for default green */
      --dnd-indicator: {{colors.error.default.hex}};                  /* change to #f13f43 for default red */
      --idle-indicator: {{colors.tertiary_container.default.hex}};    /* change to #f0b232 for default yellow */
      --streaming-indicator: {{colors.on_primary.default.hex}};       /* change to #593695 for default purple */

      /* accent colors */
        --accent-1: {{colors.tertiary.default.hex}};            /* links */
      --accent-2: {{colors.primary.default.hex}};             /* general unread/mention elements, some icons when active */
      --accent-3: {{colors.primary.default.hex}};             /* accent buttons */
      --accent-4: {{colors.surface_bright.default.hex}};      /* accent buttons when hovered */
      --accent-5: {{colors.primary_fixed_dim.default.hex}};   /* accent buttons when clicked */
        --accent-new: {{colors.inverse_primary.default.hex}};   /* user panel mute & deafen buttons */
      --mention:  {{colors.surface.default.hex}};             /* mentions & mention messages */
      --mention-hover: {{colors.surface_bright.default.hex}}; /* mentions & mention messages when hovered */

      /* text colors */
      --text-0: {{colors.surface.default.hex}};               /* text on colored elements */
      --text-1: {{colors.on_surface.default.hex}};            /* other normally white text */
      --text-2: {{colors.on_surface.default.hex}};            /* headings and important text */
      --text-3: {{colors.on_surface_variant.default.hex}};    /* normal text */
      --text-4: {{colors.on_surface_variant.default.hex}};    /* icon buttons and channels */
      --text-5: {{colors.outline.default.hex}};               /* muted channels/chats and timestamps */

      /* background and dark colors */
        --bg-1: {{colors.surface_variant.default.hex}};                             /* dark buttons when clicked */
      --bg-2: {{colors.surface_container_high.default.hex}};              /* dark buttons */
      --bg-3: {{colors.surface_container_low.default.hex}};               /* spacing, secondary elements */
      --bg-4: {{colors.surface.default.hex}};                             /* main background color */
      --hover: {{colors.surface_bright.default.hex}};                     /* channels and buttons when hovered */
      --active: {{colors.surface_bright.default.hex}};                    /* channels and buttons when clicked or selected */
      --message-hover: {{colors.surface_bright.default.hex}};             /* messages when hovered */

      /* amount of spacing and padding */
      --spacing: 12px;

      /* animations */
      /* ALL ANIMATIONS CAN BE DISABLED WITH REDUCED MOTION IN DISCORD SETTINGS */
      --list-item-transition: 0.2s ease;  /* channels/members/settings hover transition */
      --unread-bar-transition: 0.2s ease; /* unread bar moving into view transition */
      --moon-spin-transition: 0.4s ease;  /* moon icon spin */
      --icon-spin-transition: 1s ease;    /* round icon button spin (settings, emoji, etc.) */

      /* corner roundness (border-radius) */
      --roundness-xl: 22px; /* roundness of big panel outer corners */
      --roundness-l: 20px; /* popout panels */
      --roundness-m: 16px; /* smaller panels, images, embeds */
      --roundness-s: 12px; /* members, settings inputs */
      --roundness-xs: 10px; /* channels, buttons */
      --roundness-xxs: 8px; /* searchbar, small elements */

      /* direct messages moon icon */
      /* change to block to show, none to hide */
      --discord-icon: none; /* discord icon */
      --moon-icon: block; /* moon icon */
      --moon-icon-url: url('https://upload.wikimedia.org/wikipedia/commons/c/c4/Font_Awesome_5_solid_moon.svg'); /* custom icon url */
      --moon-icon-size: auto;

      /* filter uncolorable elements to fit theme */
      /* (just set to none, they're too much work to configure) */
      --login-bg-filter: saturate(0.3) hue-rotate(-15deg) brightness(0.4); /* login background artwork */
      --green-to-accent-3-filter: hue-rotate(56deg) saturate(1.43); /* add friend page explore icon */
      --blurple-to-accent-3-filter: hue-rotate(304deg) saturate(0.84) brightness(1.2); /* add friend page school icon */
    }

    /* Selected chat/friend text */
    .selected_f5eb4b,
    .selected_f6f816 .link_d8bfb3 {
      color: var(--text-0) !important;
      background: var(--accent-3) !important;
    }

    .selected_f6f816 .link_d8bfb3 * {
      color: var(--text-0) !important;
      fill: var(--text-0) !important;
    }
  '';

  xdg.configFile."noctalia/templates/zen-colors.css".text = ''
    :root {
    <* for name, value in colors *>
        --{{name}}: {{value.default.hex}};
    <* endfor *>

    <* for name, value in colors *>
        --{{name}}_rgb: {{value.default.red}} {{value.default.green}} {{value.default.blue}};
    <* endfor *>
    }
  '';

  xdg.configFile."noctalia/templates/zen-github.css".text = ''
    @-moz-document domain("github.com") {
        :root {
            --bgColor-default: var(--background) !important;
            --bgColor-muted: var(--surface_container_low) !important;
            --bgColor-inset: var(--surface_container_lowest) !important;
            --bgColor-emphasis: var(--surface_bright) !important;

            /* Borders */
            --borderColor-default: var(--outline_variant) !important;
            --borderColor-muted: var(--outline_variant) !important;
            --borderColor-emphasis: var(--outline) !important;

            /* Text Colors */
            --fgColor-default: var(--on_surface) !important;
            --fgColor-muted: var(--on_surface_variant) !important;
            --fgColor-accent: var(--primary) !important;

            /* Buttons */
            --button-primary-bgColor-rest: var(--primary) !important;
            --button-primary-fgColor-rest: var(--on_primary) !important;
            --button-primary-bgColor-hover: var(--primary_fixed_dim) !important;
            --button-primary-bgColor-active: var(--primary_fixed) !important;
            --button-primary-borderColor-rest: var(--outline_variant) !important;

            --button-default-bgColor-rest: var(--surface_container_high) !important;
            --button-default-fgColor-rest: var(--on_surface) !important;
            --button-default-bgColor-hover: var(--surface_bright) !important;
            --buttonCounter-default-bgColor-rest: var(--surface_container_highest) !important;

            --bgColor-accent-emphasis: var(--primary) !important;
            --borderColor-accent-emphasis: var(--primary) !important;
            --bgColor-accent-muted: var(--primary_container) !important;
            --borderColor-accent-muted: var(--primary_container) !important;

            /* Looks kinda bad in issues but here if you want it */
            /* --bgColor-success-emphasis: var(--tertiary) !important; */
            /* --fgColor-success: var(--tertiary) !important; */

            --bgColor-danger-emphasis: var(--error) !important;
            --fgColor-danger: var(--error) !important;
            --button-danger-fgColor-rest: var(--error) !important;
            --button-danger-bgColor-hover: var(--error_container) !important;

            --bgColor-attention-emphasis: var(--secondary) !important;
            --borderColor-attention-muted: var(--secondary_container) !important;

            --control-checked-bgColor-rest: var(--primary) !important;
            --control-checked-bgColor-hover: var(--primary_fixed_dim) !important;
            --control-checked-bgColor-active: var(--primary_fixed) !important;

            /* Star button */
            --button-star-iconColor: var(--primary) !important;

            /* Hovered button color */
            --control-bgColor-active: var(--surface_container_highest) !important;

            /* Profile popout color */
            --overlay-bgColor: var(--surface_container) !important;
        }
    }
  '';

  xdg.configFile."noctalia/templates/zen-youtube.css".text = ''
    @-moz-document domain("youtube.com") {

        :root, [dark], [light] {
            --yt-spec-base-background: var(--background) !important;
            --yt-spec-raised-background: var(--surface_container) !important;
            --yt-spec-general-background-a: var(--background) !important;
            --yt-spec-general-background-b: var(--surface_container_low) !important;
            --yt-spec-general-background-c: var(--surface_container_lowest) !important;
            --yt-spec-menu-background: var(--surface_container) !important;
            --yt-spec-text-primary: var(--on_surface) !important;
            --yt-spec-text-secondary: var(--on_surface_variant) !important;
            --yt-icon-color: var(--on_surface) !important;
            --yt-spec-icon-active-other: var(--primary) !important;
            --yt-spec-red-indicator: var(--primary) !important;
            --yt-spec-icon-inactive: var(--outline) !important;
            --yt-spec-brand-background-solid: var(--primary) !important;
            --yt-spec-brand-icon-active: var(--primary) !important;
            --yt-spec-static-brand-red: var(--primary) !important;
            --yt-spec-call-to-action: var(--primary) !important;
            --yt-spec-10-percent-layer: var(--surface_variant) !important;
            --yt-spec-badge-chip-background: var(--surface_container_high) !important;
            --yt-spec-button-chip-background-hover: var(--surface_bright) !important;
            --yt-saturated-raised-background: var(--surface_container) !important;
            --t3e41d7b17b187f69: var(--background) !important; /* General background */
            --t518e925f61bdcb91: var(--surface_container) !important;
            --t2d807bb79e75606d: var(--primary) !important;
            --t6216186c28b3834b: var(--on_primary) !important;
            --t617db776af0de196: var(--primary) !important;
            --t08a7c6c176cbc5c2: var(--surface_container) !important;
        }

        /* Sidebar / Navigation */
        #guide-content.ytd-app,
        ytd-guide-renderer,
        #contentContainer.app-drawer,
        .style-scope ytd-two-column-browse-results-renderer,
        .style-scope ytd-rich-grid-renderer,
        .style-scope ytd-feed-filter-chip-bar-renderer {
            background-color: var(--background) !important;
        }

        /* Progress bar */
        .ytp-play-progress.ytp-swatch-background-color,
        .ytp-play-progress,
        .yt-play-progress {
            background-image: linear-gradient(to right, var(--primary) 80%, var(--primary) 100%) !important;
            background-color: transparent !important;
        }

        .ytp-scrubber-button.ytp-swatch-background-color {
            background-color: var(--secondary) !important;
        }

        /* YouTube Logo Color */
        #logo-icon svg g path[fill^="#ff"],
        #logo-icon svg g path[fill^="#FF"],
        ytd-logo svg g path[fill^="#ff"],
        .ytd-logo svg g path[fill^="#FF"],
        #logo-icon path.style-scope.ytd-logo[fill="#FF0000"],
        #logo-icon path.style-scope.ytd-logo[fill="#ff0000"] {
            fill: var(--primary) !important;
        }

        #logo-icon [fill="white"],
        .ytd-logo [fill="white"] {
            fill: var(--on_primary) !important;
        }

        #logo-icon path[fill="#212121"],
        #logo-icon path[fill="#fff"],
        .yt-icon-shape path[fill="#fff"] {
            fill: var(--on_surface) !important;
        }

        .ytp-volume-slider-handle:before {
            background: var(--primary) !important;
        }

        /* Notification Badges */
        .yt-spec-icon-badge-shape--type-notification .yt-spec-icon-badge-shape__badge {
            background-color: var(--primary) !important;
            color: var(--on_primary) !important;
        }


        /* Search Bar */
        .ytSearchboxComponentInputBox {
            background-color: var(--surface_container) !important;
            color: var(--on_surface_container) !important;
        }

        .ytSearchboxComponentInputBox.ytSearchboxComponentInputBoxHasFocus {
            border-color: var(--primary) !important;
        }

        .ytSearchboxComponentSearchButton {
            background-color: var(--primary) !important;
            color: var(--on_primary) !important;
        }

        /* Header + Top Bar + Chip background */
        #masthead-container.ytd-app,
        #background.ytd-masthead,
        ytd-feed-filter-chip-bar-renderer[frosted-glass-mode="with-chipbar"] #chips-wrapper.ytd-feed-filter-chip-bar-renderer,
        ytd-mini-guide-entry-renderer[frosted-glass],
        ytd-mini-guide-renderer[frosted-glass] {
            background-color: var(--background) !important;
            color: var(--on_background) !important
        }


        /* Buttons */
        ytd-button-renderer.style-primary {
            --yt-spec-button-chip-background-hover: var(--primary_container) !important;
        }

        /* Live Chat + Comments */
        ytd-live-chat-frame#chat {
            border: 1px solid var(--outline_variant) !important;
            border-radius: 12px !important;
        }

        /* Primary Buttons */
        ytd-button-renderer.style-primary .yt-spec-button-shape-next--filled {
            background-color: var(--primary) !important;
            color: var(--on_primary) !important;
        }

        ytd-button-renderer.style-primary:hover .yt-spec-button-shape-next--filled {
            background-color: var(--primary_fixed_dim) !important;
        }

        /* Tonal/Secondary Buttons */
        .yt-spec-button-shape-next--tonal,
        .yt-spec-touch-feedback-shape--touch-response .yt-spec-touch-feedback-shape__fill {
            background-color: var(--secondary_container) !important;
            color: var(--on_secondary_container) !important;
        }

        .yt-spec-button-shape-next--tonal:hover,
        .yt-spec-touch-feedback-shape--touch-response .yt-spec-touch-feedback-shape__fill:hover {
            background-color: var(--secondary_fixed_dim) !important;
            color: var(--on_secondary_fixed_variant) !important;
        }

        /* Community posts */
        ytd-post-renderer {
            background-color: var(--surface_container) !important;
            border: 1px solid var(--outline_variant) !important;
            color: var(--on_surface_container) !important;
        }

        /* Dropdowns */
        ytd-multi-page-menu-renderer {
            background: var(--surface_container) !important;
            color: var(--on_surface_container) !important;
        }

        /* Search box */
        .ytSearchboxComponentSuggestionsContainer {
            background-color: var(--surface_container) !important;
            color: var(--on_surface_container) !important;
        }

        /* The "Subscribe" button */
        /* Disabled because it looks kinda bad to me */
        /* #subscribe-button .yt-spec-button-shape-next--filled {
            background-color: var(--primary) !important;
        } */

        /* #subscribe-button:hover .yt-spec-button-shape-next--filled {
            background-color: var(--primary_fixed) !important;
            filter: brightness(1.1) !important;
        } */
    }
  '';

  xdg.configFile."noctalia/templates/zen-bitwarden.css".text = ''
    @-moz-document domain("vault.bitwarden.com") {
        :root {
            /* Backgrounds */
            --color-gray-900: var(--background) !important;
            --color-gray-800: var(--surface_container_low) !important;
            --color-background: var(--surface_container_high_rgb) !important;

            /* Login background */
            --color-gray-950: var(--background) !important;
            --color-illustration-bg-primary: var(--primary_rgb) !important;
            --color-illustration-bg-secondary: var(--secondary_rgb) !important;
            --color-illustration-bg-tertiary: var(--surface_container_rgb) !important;
            --color-illustration-outline: var(--outline_rgb) !important;
            --color-illustration-tertiary: var(--on_surface_rgb) !important;

            /* Buttons */
            --color-primary-600: var(--primary_rgb) !important;
            --color-primary-100: var(--primary_container_rgb) !important;

            /* Muted */
            --color-secondary-300: var(--surface_container_low_rgb) !important;
            --color-text-muted: var(--on_surface_rgb) !important;

            /* Also affects some borders */
            --color-secondary-100: var(--surface_container_low_rgb) !important;
            --color-secondary-700: var(--on_surface_rgb) !important;

            /* Hovered */
            --color-primary-700: var(--primary_rgb) !important;
            --color-text-contrast: var(--on_primary_rgb) !important;

            /* Text */
            --color-brand-400: var(--primary) !important;
        }
    }
  '';

  xdg.configFile."noctalia/templates/obsidian.css".text = ''
    /* Matugen Obsidian Dynamic Colors Snippet
     * Place output in: <vault>/.obsidian/snippets/matugen.css
     * Then enable it in: Settings → Appearance → CSS Snippets
     */

    .theme-dark, .theme-light {

        /* ── Material You RGB helpers ──────────────────────────── */
        --mat-bg-rgb:             {{colors.background.default.red}}, {{colors.background.default.green}}, {{colors.background.default.blue}};
        --mat-surface-rgb:        {{colors.surface.default.red}}, {{colors.surface.default.green}}, {{colors.surface.default.blue}};
        --mat-on-surface-rgb:     {{colors.on_surface.default.red}}, {{colors.on_surface.default.green}}, {{colors.on_surface.default.blue}};
        --mat-primary-rgb:        {{colors.primary.default.red}}, {{colors.primary.default.green}}, {{colors.primary.default.blue}};
        --mat-on-primary-rgb:     {{colors.on_primary.default.red}}, {{colors.on_primary.default.green}}, {{colors.on_primary.default.blue}};

        /* ── Core Backgrounds ──────────────────────────────────── */
        --background-primary:           {{colors.background.default.hex}};
        --background-primary-alt:       {{colors.surface_dim.default.hex}};
        --background-secondary:         {{colors.surface_container_low.default.hex}};
        --background-secondary-alt:     {{colors.surface_container.default.hex}};

        /* ── Titlebar ──────────────────────────────────────────── */
        --titlebar-background:          {{colors.surface_dim.default.hex}};
        --titlebar-background-focused:  {{colors.surface_container_low.default.hex}};
        --titlebar-text-color:          {{colors.on_surface.default.hex}};

        /* ── Borders & Dividers ────────────────────────────────── */
        --background-modifier-border:         {{colors.outline_variant.default.hex}};
        --background-modifier-border-focus:   {{colors.outline.default.hex}};
        --background-modifier-border-hover:   {{colors.outline.default.hex}};

        /* ── Text Colors ───────────────────────────────────────── */
        --text-normal:      {{colors.on_surface.default.hex}};
        --text-muted:       {{colors.on_surface_variant.default.hex}};
        --text-faint:       {{colors.outline.default.hex}};
        --text-on-accent:   {{colors.on_primary.default.hex}};
        --text-selection:   rgba({{colors.primary.default.red}}, {{colors.primary.default.green}}, {{colors.primary.default.blue}}, 0.25);

        /* ── Accent & Interactive ──────────────────────────────── */
        --interactive-accent:           {{colors.primary.default.hex}};
        --interactive-accent-hover:     {{colors.primary_container.default.hex}};
        --interactive-accent-rgb:       {{colors.primary.default.red}}, {{colors.primary.default.green}}, {{colors.primary.default.blue}};
        --text-accent:                  {{colors.primary.default.hex}};
        --text-accent-hover:            {{colors.primary_container.default.hex}};

        /* ── Hover & Active Modifiers ──────────────────────────── */
        --background-modifier-hover:          rgba(var(--mat-on-surface-rgb), 0.06);
        --background-modifier-active-hover:   rgba(var(--mat-primary-rgb), 0.15);
        --background-modifier-success:        {{colors.tertiary_container.default.hex}};
        --background-modifier-error:          {{colors.error_container.default.hex}};
        --background-modifier-error-hover:    {{colors.error.default.hex}};

        /* ── Obsidian Color Scale (--color-base-XX) ────────────── */
        --color-base-00:    {{colors.background.default.hex}};
        --color-base-05:    {{colors.surface_dim.default.hex}};
        --color-base-10:    {{colors.surface_container_lowest.default.hex}};
        --color-base-20:    {{colors.surface_container_low.default.hex}};
        --color-base-25:    {{colors.surface_container.default.hex}};
        --color-base-30:    {{colors.surface_container_high.default.hex}};
        --color-base-35:    {{colors.surface_container_highest.default.hex}};
        --color-base-40:    {{colors.outline_variant.default.hex}};
        --color-base-50:    {{colors.outline.default.hex}};
        --color-base-60:    {{colors.on_surface_variant.default.hex}};
        --color-base-70:    {{colors.on_surface.default.hex}};
        --color-base-100:   {{colors.inverse_surface.default.hex}};

        /* ── Semantic Colors ───────────────────────────────────── */
        --color-red:        {{colors.error.default.hex}};
        --color-orange:     {{colors.tertiary.default.hex}};
        --color-yellow:     {{colors.secondary.default.hex}};
        --color-green:      {{colors.tertiary_container.default.hex}};
        --color-cyan:       {{colors.secondary_container.default.hex}};
        --color-blue:       {{colors.primary.default.hex}};
        --color-purple:     {{colors.secondary.default.hex}};
        --color-pink:       {{colors.tertiary.default.hex}};

        /* ── Headings ──────────────────────────────────────────── */
        --h1-color:     {{colors.primary.default.hex}};
        --h2-color:     {{colors.primary.default.hex}};
        --h3-color:     {{colors.secondary.default.hex}};
        --h4-color:     {{colors.tertiary.default.hex}};
        --h5-color:     {{colors.on_surface_variant.default.hex}};
        --h6-color:     {{colors.outline.default.hex}};

        /* ── Links ─────────────────────────────────────────────── */
        --link-color:           {{colors.primary.default.hex}};
        --link-color-hover:     {{colors.on_primary_container.default.hex}};
        --link-external-color:  {{colors.tertiary.default.hex}};
        --link-unresolved-color: {{colors.outline.default.hex}};

        /* ── Tags ──────────────────────────────────────────────── */
        --tag-color:            {{colors.on_primary_container.default.hex}};
        --tag-background:       {{colors.primary_container.default.hex}};
        --tag-border-color:     {{colors.primary.default.hex}};
        --tag-color-hover:      {{colors.on_primary.default.hex}};
        --tag-background-hover: {{colors.primary.default.hex}};

        /* ── Checkboxes ────────────────────────────────────────── */
        --checkbox-color:           {{colors.primary.default.hex}};
        --checkbox-color-hover:     {{colors.primary_container.default.hex}};
        --checkbox-border-color:    {{colors.outline.default.hex}};
        --checkbox-marker-color:    {{colors.on_primary.default.hex}};

        /* ── Code Blocks ───────────────────────────────────────── */
        --code-background:  {{colors.surface_container_low.default.hex}};
        --code-normal:      {{colors.on_surface.default.hex}};
        --code-comment:     {{colors.outline.default.hex}};
        --code-function:    {{colors.primary.default.hex}};
        --code-important:   {{colors.error.default.hex}};
        --code-keyword:     {{colors.secondary.default.hex}};
        --code-operator:    {{colors.tertiary.default.hex}};
        --code-property:    {{colors.on_surface_variant.default.hex}};
        --code-punctuation: {{colors.outline_variant.default.hex}};
        --code-string:      {{colors.tertiary.default.hex}};
        --code-tag:         {{colors.error.default.hex}};
        --code-value:       {{colors.secondary.default.hex}};

        /* ── Scrollbar ─────────────────────────────────────────── */
        --scrollbar-thumb-bg:           rgba(var(--mat-on-surface-rgb), 0.12);
        --scrollbar-active-thumb-bg:    rgba(var(--mat-on-surface-rgb), 0.25);
        --scrollbar-bg:                 transparent;

        /* ── Inputs ────────────────────────────────────────────── */
        --input-shadow: none;
        --input-shadow-hover: 0 0 0 2px {{colors.outline.default.hex}};

        /* ── Graph View ────────────────────────────────────────── */
        --graph-node:           {{colors.primary.default.hex}};
        --graph-node-unresolved: {{colors.outline.default.hex}};
        --graph-node-focused:   {{colors.on_primary_container.default.hex}};
        --graph-node-tag:       {{colors.secondary.default.hex}};
        --graph-node-attachment: {{colors.tertiary.default.hex}};
        --graph-line:           {{colors.outline_variant.default.hex}};
        --graph-background:     {{colors.background.default.hex}};

    }

    /* ── Active line highlight ─────────────────────────────────── */
    .cm-active {
        background-color: rgba(var(--mat-on-surface-rgb), 0.03) !important;
    }
  '';

  xdg.configFile."noctalia/templates/usercontent.css".text = ''
    @import url("/home/thedreamdev/.var/app/app.zen_browser.zen/.zen/pmem02b2.Default (release)/chrome/colors.css");
    @import url("/home/thedreamdev/.var/app/app.zen_browser.zen/.zen/pmem02b2.Default (release)/chrome/zen-usercontent.css");
    @import url("/home/thedreamdev/.var/app/app.zen_browser.zen/.zen/pmem02b2.Default (release)/chrome/websites/github.css");
    @import url("/home/thedreamdev/.var/app/app.zen_browser.zen/.zen/pmem02b2.Default (release)/chrome/websites/youtube.css");
    @import url("/home/thedreamdev/.var/app/app.zen_browser.zen/.zen/pmem02b2.Default (release)/chrome/websites/bitwarden.css");
  '';

  xdg.configFile."noctalia/templates/papirus-color".text = "{{colors.primary.default.hex}}";

  # KDE apps (dolphin, okular, ...) resolve colours through KColorScheme, which
  # reads ~/.config/kdeglobals, not the qt6ct palette. This template renders the
  # same material roles in KDE's group format; the post_hook merges them into
  # kdeglobals so the fonts, icon theme and widget style a user set there survive
  # a repaint.
  xdg.configFile."noctalia/templates/kdeglobals".text = ''
    # Noctalia palette -> the colour groups KColorScheme reads. Hex rather than
    # KDE's usual "R,G,B": KColorScheme parses both.

    [Colors:View]
    BackgroundNormal={{colors.surface.default.hex}}
    # A small step from BackgroundNormal on purpose. A large one stripes the file
    # list light and dark row by row.
    BackgroundAlternate={{colors.surface_container_low.default.hex}}
    ForegroundNormal={{colors.on_surface.default.hex}}
    ForegroundInactive={{colors.on_surface_variant.default.hex}}
    ForegroundActive={{colors.primary.default.hex}}
    ForegroundLink={{colors.primary.default.hex}}
    ForegroundVisited={{colors.tertiary.default.hex}}
    ForegroundNegative={{colors.error.default.hex}}
    ForegroundNeutral={{colors.tertiary.default.hex}}
    ForegroundPositive={{colors.secondary.default.hex}}
    DecorationFocus={{colors.primary.default.hex}}
    DecorationHover={{colors.primary.default.hex}}

    [Colors:Window]
    BackgroundNormal={{colors.surface.default.hex}}
    BackgroundAlternate={{colors.surface_container.default.hex}}
    ForegroundNormal={{colors.on_surface.default.hex}}
    ForegroundInactive={{colors.on_surface_variant.default.hex}}
    ForegroundActive={{colors.primary.default.hex}}
    ForegroundLink={{colors.primary.default.hex}}
    ForegroundVisited={{colors.tertiary.default.hex}}
    ForegroundNegative={{colors.error.default.hex}}
    ForegroundNeutral={{colors.tertiary.default.hex}}
    ForegroundPositive={{colors.secondary.default.hex}}
    DecorationFocus={{colors.primary.default.hex}}
    DecorationHover={{colors.primary.default.hex}}

    [Colors:Button]
    BackgroundNormal={{colors.surface_container.default.hex}}
    BackgroundAlternate={{colors.surface_container_high.default.hex}}
    ForegroundNormal={{colors.on_surface.default.hex}}
    ForegroundInactive={{colors.on_surface_variant.default.hex}}
    ForegroundActive={{colors.primary.default.hex}}
    ForegroundLink={{colors.primary.default.hex}}
    ForegroundVisited={{colors.tertiary.default.hex}}
    ForegroundNegative={{colors.error.default.hex}}
    ForegroundNeutral={{colors.tertiary.default.hex}}
    ForegroundPositive={{colors.secondary.default.hex}}
    DecorationFocus={{colors.primary.default.hex}}
    DecorationHover={{colors.primary.default.hex}}

    [Colors:Selection]
    BackgroundNormal={{colors.primary.default.hex}}
    BackgroundAlternate={{colors.primary_container.default.hex}}
    ForegroundNormal={{colors.on_primary.default.hex}}
    ForegroundInactive={{colors.on_primary.default.hex}}
    ForegroundActive={{colors.on_primary.default.hex}}
    ForegroundLink={{colors.on_primary.default.hex}}
    ForegroundVisited={{colors.on_primary.default.hex}}
    ForegroundNegative={{colors.error.default.hex}}
    ForegroundNeutral={{colors.on_primary.default.hex}}
    ForegroundPositive={{colors.on_primary.default.hex}}
    DecorationFocus={{colors.primary.default.hex}}
    DecorationHover={{colors.primary.default.hex}}

    [Colors:Tooltip]
    BackgroundNormal={{colors.inverse_surface.default.hex}}
    BackgroundAlternate={{colors.inverse_surface.default.hex}}
    ForegroundNormal={{colors.inverse_on_surface.default.hex}}
    ForegroundInactive={{colors.inverse_on_surface.default.hex}}
    ForegroundActive={{colors.inverse_primary.default.hex}}
    ForegroundLink={{colors.inverse_primary.default.hex}}
    ForegroundVisited={{colors.inverse_primary.default.hex}}
    ForegroundNegative={{colors.error.default.hex}}
    ForegroundNeutral={{colors.inverse_on_surface.default.hex}}
    ForegroundPositive={{colors.inverse_on_surface.default.hex}}
    DecorationFocus={{colors.primary.default.hex}}
    DecorationHover={{colors.primary.default.hex}}

    [Colors:Complementary]
    BackgroundNormal={{colors.surface_container_high.default.hex}}
    BackgroundAlternate={{colors.surface_container_highest.default.hex}}
    ForegroundNormal={{colors.on_surface.default.hex}}
    ForegroundInactive={{colors.on_surface_variant.default.hex}}
    ForegroundActive={{colors.primary.default.hex}}
    ForegroundLink={{colors.primary.default.hex}}
    ForegroundVisited={{colors.tertiary.default.hex}}
    ForegroundNegative={{colors.error.default.hex}}
    ForegroundNeutral={{colors.tertiary.default.hex}}
    ForegroundPositive={{colors.secondary.default.hex}}
    DecorationFocus={{colors.primary.default.hex}}
    DecorationHover={{colors.primary.default.hex}}

    [Colors:Header]
    BackgroundNormal={{colors.surface_container_low.default.hex}}
    BackgroundAlternate={{colors.surface_container.default.hex}}
    ForegroundNormal={{colors.on_surface.default.hex}}
    ForegroundInactive={{colors.on_surface_variant.default.hex}}
    ForegroundActive={{colors.primary.default.hex}}
    ForegroundLink={{colors.primary.default.hex}}
    ForegroundVisited={{colors.tertiary.default.hex}}
    ForegroundNegative={{colors.error.default.hex}}
    ForegroundNeutral={{colors.tertiary.default.hex}}
    ForegroundPositive={{colors.secondary.default.hex}}
    DecorationFocus={{colors.primary.default.hex}}
    DecorationHover={{colors.primary.default.hex}}

    [Colors:Header][Inactive]
    BackgroundNormal={{colors.surface.default.hex}}
    BackgroundAlternate={{colors.surface_container_low.default.hex}}
    ForegroundNormal={{colors.on_surface_variant.default.hex}}
    ForegroundInactive={{colors.outline.default.hex}}
    ForegroundActive={{colors.primary.default.hex}}
    ForegroundLink={{colors.primary.default.hex}}
    ForegroundVisited={{colors.tertiary.default.hex}}
    ForegroundNegative={{colors.error.default.hex}}
    ForegroundNeutral={{colors.tertiary.default.hex}}
    ForegroundPositive={{colors.secondary.default.hex}}
    DecorationFocus={{colors.primary.default.hex}}
    DecorationHover={{colors.primary.default.hex}}

    [WM]
    activeBackground={{colors.surface_container.default.hex}}
    activeForeground={{colors.on_surface.default.hex}}
    activeBlend={{colors.primary.default.hex}}
    inactiveBackground={{colors.surface.default.hex}}
    inactiveForeground={{colors.on_surface_variant.default.hex}}
    inactiveBlend={{colors.outline.default.hex}}

    # KDE apps take the Qt font from here; the merge preserves any other keys a
    # user keeps in [General]/[Icons] (later groups override earlier ones).
    [General]
    font=Monocraft,11,-1,5,50,0,0,0,0,0
    fixed=Monocraft,10,-1,5,50,0,0,0,0,0

    [Icons]
    Theme=noctalia-folders

    # Effect blocks are not palette-derived; these are the stock KDE values from
    # BreezeClassic.colors so disabled and inactive widgets dim the way KDE apps expect.
    [ColorEffects:Disabled]
    Color=56,56,56
    ColorAmount=0
    ColorEffect=0
    ContrastAmount=0.65
    ContrastEffect=1
    IntensityAmount=0.1
    IntensityEffect=2

    [ColorEffects:Inactive]
    ChangeSelectionColor=true
    Color=112,111,110
    ColorAmount=0.025
    ColorEffect=2
    ContrastAmount=0.1
    ContrastEffect=2
    Enable=false
    IntensityAmount=0
    IntensityEffect=0
  '';

  xdg.configFile."noctalia/scripts/kdeglobals-merge.sh".text = ''
    #!/usr/bin/env bash
    # Merge the noctalia-rendered KColorScheme groups into ~/.config/kdeglobals
    # without disturbing the rest of the user's KDE settings. We own every group we
    # render ([Colors:*], [WM], [ColorEffects:*]); everything else is preserved.
    set -eu

    rendered="$HOME/.cache/noctalia/kdeglobals.conf"
    target="$HOME/.config/kdeglobals"
    tmp="$target.tmp"

    # Failed renders leave a stale cache file and an error in noctalia.log; if the
    # cache is empty or missing, keep the current target untouched.
    if [ ! -s "$rendered" ]; then
      exit 1
    fi

    # Drop our managed groups from the existing file, keep everything else.
    awk '
      /^[[:space:]]*\[/ {
        name=$0; sub(/^[[:space:]]*\[/, "", name); sub(/\].*$/, "", name)
        keep=(name != "WM" && name !~ /^(Colors|ColorEffects):/)
      }
      keep { print }
    ' "$target" 2>/dev/null > "$tmp" || : # target may not exist yet

    cat "$rendered" >> "$tmp"

    mv "$tmp" "$target"
  '';

  xdg.configFile."noctalia/scripts/papirus-folders.sh".text = ''
    #!/usr/bin/env bash
    # Tint folder icons to the active noctalia accent. Builds a small overlay icon
    # theme that inherits Papirus-Dark and overrides only the folder icons with
    # Papirus's matching colour set (root-free, ~300K, never touches the packaged
    # theme). The fixed theme name is noctalia-folders; only its content changes.
    # Each run builds the new colours in a temp dir and publishes them by renaming
    # a symlink over the old one, so a reader atomically sees a whole tree, and
    # gtk-update-icon-cache busts GTK's on-disk cache. Run at login and on every
    # palette change.
    set -u

    pap=''${PAPIRUS_ROOT:-}
    if [ -z "$pap" ]; then
      old_ifs=$IFS
      IFS=:
      for data_dir in $HOME/.local/share $HOME/.nix-profile/share /run/current-system/sw/share ''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
        if [ -d "$data_dir/icons/Papirus" ]; then
          pap="$data_dir/icons/Papirus"
          break
        fi
      done
      IFS=$old_ifs
    fi
    pap=''${pap:-/usr/share/icons/Papirus}
    src=$pap/64x64/places
    [ -d "$src" ] || exit 0

    # Serialise: a burst of palette changes runs one at a time, last wins.
    exec 9>''${XDG_RUNTIME_DIR:-/tmp}/noctalia-folders.lock 2>/dev/null && flock 9 2>/dev/null

    accent=''${1:-}
    color=blue
    if [ -n "$accent" ]; then
      color=$(awk -v c="$accent" 'BEGIN{
        r=strtonum("0x" substr(c,2,2))/255; g=strtonum("0x" substr(c,4,2))/255; b=strtonum("0x" substr(c,6,2))/255
        mx=(r>g?(r>b?r:b):(g>b?g:b)); mn=(r<g?(r<b?r:b):(g<b?g:b)); d=mx-mn
        if(d==0) h=0; else if(mx==r) h=(g-b)/d; else if(mx==g) h=(b-r)/d+2; else h=(r-g)/d+4
        h*=60; if(h<0) h+=360; s=(mx==0?0:d/mx)
        # near-greyscale accents stay grey; anything with a perceptible hue tints
        print (s<0.10)?"grey":(h<15||h>=345)?"red":(h<45)?"orange":(h<70)?"yellow":(h<165)?"green":(h<195)?"teal":(h<215)?"cyan":(h<255)?"blue":(h<290)?"violet":(h<330)?"magenta":"pink"
      }')
      [ -e "$src/folder-$color.svg" ] || color=blue
    fi

    base=''${XDG_DATA_HOME:-$HOME/.local/share}/icons
    name=noctalia-folders        # fixed theme name consumers resolve to
    link=$base/$name             # symlink -> the live generation
    gens=$base/.noctalia-folders # hidden container: generations + temp builds

    cur=""
    command -v gsettings >/dev/null 2>&1 && cur=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
    prev=""
    [ -L "$link" ] && prev=$(basename "$(readlink "$link")")

    # Build the new content into a temp dir, then rename it into a complete,
    # immutable generation dir before anything points at it.
    gen=$(date +%s%N)
    tmp=$gens/build.$$
    rm -rf "$tmp"
    mkdir -p "$tmp/places"
    for f in "$src/folder-$color.svg" "$src"/folder-"$color"-*.svg "$src"/user-"$color"-*.svg; do
      [ -e "$f" ] || continue
      b=$(basename "$f"); d=''${b/-$color-/-}; d=''${d/-$color./.}
      cp -L "$f" "$tmp/places/$d"
    done
    cat > "$tmp/index.theme" <<'EOF'
    [Icon Theme]
    Name=Noctalia Folders
    Inherits=Papirus-Dark
    Directories=places

    [places]
    Size=64
    MinSize=8
    MaxSize=512
    Type=Scalable
    Context=Places
    EOF
    # Bake the cache into the tree before publishing so GTK re-reads the new
    # colours instead of a stale on-disk cache.
    command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -qf "$tmp" 2>/dev/null
    mv -T "$tmp" "$gens/$gen"

    # Publish atomically: rename a staging symlink over the live one.
    stage=$base/.noctalia-folders.link.$$
    ln -sfn ".noctalia-folders/$gen" "$stage"
    [ -e "$link" ] && [ ! -L "$link" ] && rm -rf "$link"
    mv -T "$stage" "$link"

    # Point consumers at the fixed name once, only when it is not already set so
    # palette changes never churn the setting, and only over the shipped defaults.
    case $cur in
      ""|"$name"|Papirus|Papirus-Dark|Papirus-Light|Adwaita|hicolor|noctalia-folders-*)
        if [ "$cur" != "$name" ] && command -v gsettings >/dev/null 2>&1; then
          gsettings set org.gnome.desktop.interface icon-theme "$name"
        fi
        ;;
    esac

    # Keep only the live and immediately-previous generations.
    for d in "$gens"/*; do
      [ -e "$d" ] || continue
      b=$(basename "$d")
      case $b in "$gen"|"$prev") continue ;; esac
      rm -rf "$d"
    done
    exit 0
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
          user."zen-userchrome" = {
            input_path = "$XDG_CONFIG_HOME/noctalia/templates/zen-userchrome.css";
            output_path = "~/.var/app/app.zen_browser.zen/.zen/pmem02b2.Default (release)/chrome/userChrome.css";
          };
          user."zen-usercontent" = {
            input_path = "$XDG_CONFIG_HOME/noctalia/templates/zen-usercontent.css";
            output_path = "~/.var/app/app.zen_browser.zen/.zen/pmem02b2.Default (release)/chrome/zen-usercontent.css";
          };
          user."zen-colors" = {
            input_path = "$XDG_CONFIG_HOME/noctalia/templates/zen-colors.css";
            output_path = "~/.var/app/app.zen_browser.zen/.zen/pmem02b2.Default (release)/chrome/colors.css";
          };
          user."zen-github" = {
            input_path = "$XDG_CONFIG_HOME/noctalia/templates/zen-github.css";
            output_path = "~/.var/app/app.zen_browser.zen/.zen/pmem02b2.Default (release)/chrome/websites/github.css";
          };
          user."zen-youtube" = {
            input_path = "$XDG_CONFIG_HOME/noctalia/templates/zen-youtube.css";
            output_path = "~/.var/app/app.zen_browser.zen/.zen/pmem02b2.Default (release)/chrome/websites/youtube.css";
          };
          user."zen-bitwarden" = {
            input_path = "$XDG_CONFIG_HOME/noctalia/templates/zen-bitwarden.css";
            output_path = "~/.var/app/app.zen_browser.zen/.zen/pmem02b2.Default (release)/chrome/websites/bitwarden.css";
          };
          user.usercontent = {
            input_path = "$XDG_CONFIG_HOME/noctalia/templates/usercontent.css";
            output_path = "~/.var/app/app.zen_browser.zen/.zen/pmem02b2.Default (release)/chrome/userContent.css";
          };
          user.obsidian = {
            input_path = "$XDG_CONFIG_HOME/noctalia/templates/obsidian.css";
            output_path = "~/Documents/Obsidian/Gohar/.obsidian/snippets/matugen.css";
          };
          user.papirus = {
            input_path = "$XDG_CONFIG_HOME/noctalia/templates/papirus-color";
            output_path = "$XDG_CACHE_HOME/noctalia/papirus-color";
            post_hook = "bash \"$HOME/.config/noctalia/scripts/papirus-folders.sh\" \"$(cat \"$HOME/.cache/noctalia/papirus-color\")\"";
          };
          user.kde = {
            input_path = "$XDG_CONFIG_HOME/noctalia/templates/kdeglobals";
            output_path = "$XDG_CACHE_HOME/noctalia/kdeglobals.conf";
            post_hook = "bash \"$HOME/.config/noctalia/scripts/kdeglobals-merge.sh\"";
          };
          user.vesktop = {
            input_path = "$XDG_CONFIG_HOME/noctalia/templates/midnight-discord.css";
            output_path = "~/.config/vesktop/themes/midnight-discord.css";
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
