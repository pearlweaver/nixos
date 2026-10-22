{ config, pkgs, inputs, lib, ... }: {
  # SekaiPop's phone (Quick Panel + Apps + Settings) as a small Quickshell
  # shell on the Niri + Noctalia session. Imported only by home/home.nix: the
  # Hyprland generation runs the whole shell from home/modules/sekaipop.nix.
  #
  # Noctalia keeps the bar, launcher, lock screen and session chrome. This
  # module takes over notifications and the wallpaper (the matching toggles
  # live in home/modules/noctalia.nix).

  # Only what the phone shells out to and the Niri profile lacks. nmcli,
  # bluetoothctl, wpctl, systemd-inhibit and mpvpaper are already on PATH.
  home.packages = with pkgs; [
    # The same pinned 0.3.2 build the Hyprland profile uses; nixpkgs carries
    # 0.3.1 and the tree imports services added since.
    inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.quickshell

    # Theme.iconFont / Theme.fontFamily. Without the font cache activation
    # below these resolve to nothing and every glyph is a blank box.
    # Google Sans Flex is Theme.fontFamily; jetbrains-mono is the code font.
    google-sans-flex
    material-symbols
    jetbrains-mono

    # SettingsPageNiri shells out to `niri msg` for outputs and layouts.
    # `programs.niri` configures the session but does not put the CLI in PATH.
    niri

    # The brightness half of the Quick slider.
    brightnessctl
    ddcutil

    # Screen snip, clipboard and typing extras.
    grim
    slurp
    swappy
    wl-clipboard
    wtype
    imagemagick
  ];

  # Our shell.qml, with upstream's whole QML tree linked beside it so
  # Quickshell.shellDir and the qs.* imports resolve as upstream expects.
  #
  # .force = true: ~/.config/quickshell is also managed (as a sibling config
  # dir) by the sekaipop profile, so the parent already exists in some
  # generations.
  xdg.configFile."quickshell/sekaipop-phone/shell.qml" = {
    source = ./sekaipop-phone/shell.qml;
    force = true;
  };

  xdg.configFile."quickshell/sekaipop-phone/assets" = {
    source = "${pkgs.sekaipop}/share/sekaipop/sekaipop/assets";
    recursive = true;
    force = true;
  };
  xdg.configFile."quickshell/sekaipop-phone/modules" = {
    source = "${pkgs.sekaipop}/share/sekaipop/sekaipop/modules";
    recursive = true;
    force = true;
  };
  xdg.configFile."quickshell/sekaipop-phone/scripts" = {
    source = "${pkgs.sekaipop}/share/sekaipop/sekaipop/scripts";
    recursive = true;
    force = true;
  };
  xdg.configFile."quickshell/sekaipop-phone/services" = {
    source = "${pkgs.sekaipop}/share/sekaipop/sekaipop/services";
    recursive = true;
    force = true;
  };
  xdg.configFile."quickshell/sekaipop-phone/shaders" = {
    source = "${pkgs.sekaipop}/share/sekaipop/sekaipop/shaders";
    recursive = true;
    force = true;
  };
  # Read by UpdateService / the About page.
  xdg.configFile."quickshell/sekaipop-phone/VERSION" = {
    source = "${pkgs.sekaipop}/share/sekaipop/sekaipop/VERSION";
    force = true;
  };
  xdg.configFile."quickshell/sekaipop-phone/CHANGELOG.md" = {
    source = "${pkgs.sekaipop}/share/sekaipop/sekaipop/CHANGELOG.md";
    force = true;
  };

  # home.packages fonts land in share/fonts, but nothing rebuilds fontconfig's
  # cache on a profile change; without this "Material Symbols Rounded" stays
  # invisible and every icon renders as an empty box. Same trap as
  # home/modules/sekaipop.nix.
  home.activation.sekaipopPhoneFontCache = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    fc-cache -f >/dev/null 2>&1 || true
  '';
}
