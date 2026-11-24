{ config, pkgs, lib, ... }:

let
  # pkgs/chillpill is the upstream flake package plus the lockscreen binary;
  # the flake's `packages.chillpill` output is the same derivation.
  chillpill = pkgs.chillpill;

  # Fixed IPC state names from the shell's IpcHandler blocks.
  ipc = target: [ "chillpill-shell-ipc" "call" target "toggle" ];
in {
  # Reuse the whole niri settings block (input, outputs, layout, rules, every
  # bind) and override only what the shell change requires. niri.nix itself is
  # untouched, so the Noctalia profile keeps its exact configuration.
  imports = [ ./niri.nix ];

  # The manual ChillPill setup left a regular config.jsonc at this path, so
  # home-manager's checkLinkTargets refuses to replace the generated one.
  # Nix owns this file in the profile (the GUI config app cannot save to a
  # store symlink anyway), hence the same force used for the other dotfiles.
  xdg.configFile."chillpill-shell/config.jsonc".force = true;

  programs.chillpill-shell = {
    enable = true;
    package = chillpill;
    settings = {
      clockFormat = "HH:mm";
      maxWorkspaces = 6;
      screenLockAppCommand = "chillpill-lock";
      defaultTerminal = "kitty";
      textFontFamily = "Monocraft";
      nerdFontFamily = "JetBrainsMono Nerd Font Propo";
      weatherLocation = "Lahore";
      # The calendar's holiday dots, coloured day numbers and next-holiday
      # line all hang off Config.holidaysUsable(); switching this off removes
      # every marking without touching the country/weather settings.
      holidaysEnabled = false;
      wallpapersDir = "~/Pictures/Wallpapers";
    };
  };

  # Runtime companions the upstream module does not install. The package's own
  # wrapper has cliphist/brightnessctl/awww, but niri binds and
  # spawn-at-startup run from the user PATH.
  home.packages = with pkgs; [
    awww
    brightnessctl
    nerd-fonts.jetbrains-mono
  ];

  # Noctalia and the SekaiPop phone are deliberately absent: both claim the
  # notification bus and the wallpaper.
  programs.niri.settings = {
    spawn-at-startup = lib.mkForce [
      { command = [ "chillpill-shell" ]; }
      { command = [ "xwayland-satellite" ]; }
      { command = [ "awww-daemon" ]; }
      # awww-daemon may still be starting; retry briefly, then give up. A
      # missing last_wallpaper is normal on the first run (pick one with Mod+A).
      { command = [ "sh" "-c" ''
        wp="$HOME/.cache/chillpill-shell/last_wallpaper"
        [ -s "$wp" ] || exit 0
        for _ in 1 2 3 4 5; do
          awww img "$(cat "$wp")" && exit 0
          sleep 0.5
        done
      '' ]; }
    ];

    # The user's keys stay. Shell features move onto the key that already did
    # the same job in the Noctalia profile; shell defaults that collide with an
    # existing app bind are not added.
    binds = {
      "Alt+Space" = lib.mkForce { action.spawn = ipc "spotlight"; };
      "Mod+V" = lib.mkForce { action.spawn = ipc "cliphist"; };
      "Mod+Space" = lib.mkForce { action.spawn = ipc "controlCenter"; };
      "Mod+A" = lib.mkForce { action.spawn = ipc "wallpaperSwitcher"; };
      "Mod+L" = lib.mkForce { action.spawn = [ "chillpill-lock" ]; };
      "Ctrl+Alt+Delete" = lib.mkForce { action.spawn = ipc "powerMenu"; };

      "XF86AudioRaiseVolume" = lib.mkForce { action.spawn = [ "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+" ]; };
      "XF86AudioLowerVolume" = lib.mkForce { action.spawn = [ "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-" ]; };
      "XF86AudioMute" = lib.mkForce { action.spawn = [ "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle" ]; };
      "XF86AudioMicMute" = lib.mkForce { action.spawn = [ "wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle" ]; };
      "XF86MonBrightnessUp" = lib.mkForce { action.spawn = [ "brightnessctl" "set" "5%+" ]; };
      "XF86MonBrightnessDown" = lib.mkForce { action.spawn = [ "brightnessctl" "set" "5%-" ]; };

      # States with no equivalent in the current setup. Mod+D, Mod+W and
      # Mod+Shift+B are intentionally absent: they keep Vesktop, LibreOffice
      # and playerctl-previous.
      "Mod+Ctrl+B".action.spawn = ipc "dashboard";
      "Mod+Shift+W".action.spawn = ipc "wifiState";
    };
  };

  # Theme presets live in the runtime cache, not the store. -n preserves any
  # theme the user drops in later.
  home.activation.chillpillThemes = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.cache/chillpill-shell/themes"
    run cp -n ${chillpill}/share/chillpill-shell/share/themes/*.json "$HOME/.cache/chillpill-shell/themes/" 2>/dev/null || true
  '';

  # home.packages fonts do not refresh fontconfig on a profile change; without
  # this "JetBrainsMono Nerd Font Propo" resolves to a blank glyph. Activation
  # PATH is minimal (home.emptyActivationPath), so call fontconfig by store
  # path instead of relying on `fc-cache` being on PATH.
  home.activation.chillpillFontCache = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    ${pkgs.fontconfig}/bin/fc-cache -f >/dev/null 2>&1 || true
  '';
}
