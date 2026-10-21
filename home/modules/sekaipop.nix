{ config, pkgs, inputs, lib, ... }: {
  # SekaiPop: a full Quickshell desktop shell for the Hyprland generation.
  #
  # Imported ONLY by home/home-sekaipop.nix. Nothing in the Niri session reaches
  # this file, which is what keeps that session unchanged.
  #
  # Deliberately absent: programs.hyprland.enable. That is a NixOS option and is
  # already set in system/modules/packages.nix for every output.

  # === Dependencies ===
  #
  # Only what SekaiPop's check-deps.sh requires that home/modules/packages.nix
  # does not already provide. Already present there and NOT repeated:
  # plasma-integration, cava, ffmpeg, playerctl, mpvpaper, adw-gtk3,
  # xdg-desktop-portal, nautilus, nodejs, kdePackages.qt6ct.
  home.packages = with pkgs; [
    # Quickshell 0.3.2 from the pinned flake input, not nixpkgs' 0.3.1. Gate 0
    # confirmed this build loads the shell and carries all 11 QML modules it
    # imports (Hyprland, Wayland, Io, Widgets, and Services/{Pam, Polkit,
    # Notifications, UPower, Pipewire, Mpris, SystemTray}).
    inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.quickshell

    # Google Sans Flex. Tier 1 in check-deps.sh, absent from nixpkgs; see
    # pkgs/google-sans-flex.
    google-sans-flex

    # NOTE: no python3 env here on purpose. The audio analyzer
    # (VisualizerService.qml spawning scripts/cava/sekai_analyzer.py) needs
    # numpy, but home/modules/perla.nix already puts one `python3.withPackages`
    # env on PATH, and two python envs collide in buildEnv on bin/idle3.*.
    # numpy and aubio-ledfx are therefore added to Perla's existing env rather
    # than adding a second one. See the comment at that call site.

    # Lock, idle, colour picker, blue-light filter, cursor theme.
    hypridle
    hyprlock
    hyprpicker
    hyprsunset
    hyprcursor

    # Clipboard and screen capture.
    wl-clipboard
    cliphist
    grim
    slurp
    wtype
    swappy

    # Audio service the visualizer taps. `pactl` (and `parec`/`paplay`) come from
    # the `pulseaudio` package -- there is no standalone pulseaudioUtils in this
    # nixpkgs. Without pactl the shell logs "Process failed to start: pactl
    # subscribe" continuously and the audio-reactive parts stay dead. The
    # daemon itself is not started; wireplumber owns the audio stack.
    wireplumber
    pulseaudio

    # Hardware and power.
    brightnessctl
    ddcutil
    upower
    power-profiles-daemon
    bluez
    networkmanager

    # Fonts. Renamed from the Arch names ttf-material-symbols-variable and
    # ttf-jetbrains-mono-nerd; the CJK font is the -sans subset.
    material-symbols
    jetbrains-mono
    noto-fonts-cjk-sans
    noto-fonts-color-emoji

    # Theming. matugen generates the palette at runtime from the wallpaper and
    # writes the GTK/Qt/Xresources files.
    matugen

    # Region selector, dialogs, OCR, wallpaper tooling, monitor layout.
    imagemagick
    tesseract
    ffmpegthumbnailer
    nwg-displays

    # Polkit prompts and tray volume control.
    zenity
    pavucontrol

    # Misc shell integrations.
    xdg-desktop-portal-gtk
    gvfs
    libsecret
    gnome-keyring
    jq
    curl
    git

    # `glib` provides the `gsettings` binary that the shell's theming scripts call.
    # NOTE: gsettings-desktop-schemas is deliberately NOT here -- the nixpkgs
    # package builds empty (0 schemas), so adding it achieves nothing. Icon
    # theming actually comes from ~/.config/kdeglobals [Icons] Theme= and
    # qt6ct.conf icon_theme=.
    glib
  ];

  # home.packages fonts land in the profile's share/fonts, but nothing rebuilds
  # the fontconfig cache when the profile changes. Without this the shell's
  # "Material Symbols Rounded" font (Theme.iconFont) stays invisible to
  # fontconfig and every bar/widget icon renders as a blank box -- the only
  # icons the shell draws are glyphs from that font, so it takes the whole bar
  # with it. Observed: fc-list reported 0 material fonts until fc-cache ran.
  home.activation.sekaipopFontCache = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    fc-cache -f >/dev/null 2>&1 || true
  '';

  # === Static configuration: store symlinks ===
  #
  # hyprland.lua is the compositor entry point. It loads these four without the
  # optional flag, so they must exist or Hyprland fails to start:
  #   hyprland.variables  hyprland.env  hyprland.execs
  #   hyprland.general    hyprland.rules hyprland.keybinds
  # and hyprland.lib, which resolves to hyprland/lib/init.lua. Linking the
  # directory recursively gets all of them plus hyprland/scripts/.
  #
  # .force = true is required: ~/.config/hypr does not exist on a fresh profile,
  # and without it home-manager refuses to create the tree.
  xdg.configFile."hypr/hyprland.lua" = {
    source = "${pkgs.sekaipop}/share/sekaipop/hypr/hyprland.lua";
    force = true;
  };
  xdg.configFile."hypr/hypridle.conf" = {
    source = "${pkgs.sekaipop}/share/sekaipop/hypr/hypridle.conf";
    force = true;
  };
  xdg.configFile."hypr/hyprland" = {
    source = "${pkgs.sekaipop}/share/sekaipop/hypr/hyprland";
    recursive = true;
    force = true;
  };

  # The whole quickshell config tree. home-manager walks it and symlinks each
  # file into the store; the shell never writes into this directory.
  xdg.configFile."quickshell/sekaipop" = {
    source = "${pkgs.sekaipop}/share/sekaipop/sekaipop";
    recursive = true;
    force = true;
  };

  # === Mutable configuration: seeded once, then left alone ===
  #
  # hyprland.lua loads these with `load(name, true)` -- optional, skipped when
  # absent. sekaipop_overrides.lua is rewritten in place by the shell's Settings
  # panel; custom/*.lua is the user's own edit surface.
  #
  # monitors.lua and workspaces.lua are deliberately NOT seeded: upstream never
  # ships them (install.sh:238 warns that a monitors.lua written for someone
  # else's screens is what gives a black screen). They are optional loads, so
  # Hyprland uses its own defaults until you write them. Generate monitors.lua
  # from your actual outputs if you need one.
  #
  # install -Dm644 is guarded by `[ -e ]`, so this only ever creates a missing
  # file. Idempotent, and it never overwrites an edit. Asserted by
  # home/modules/sekaipop-seed-test.sh.
  home.activation.sekaipopSeed = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    seed=${config.xdg.configHome}/hypr
    for f in custom/env.lua custom/execs.lua custom/general.lua custom/keybinds.lua custom/rules.lua custom/variables.lua sekaipop_overrides.lua; do
      [ -e "$seed/$f" ] || \
        install -Dm644 ${pkgs.sekaipop}/share/sekaipop/hypr/"$f" "$seed/$f"
    done
  '';
}