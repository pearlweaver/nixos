# ChillPill-only theming: the wallpaper drives GTK/Qt/KDE colours via matugen.
# Kept out of the shared gtk.nix/qt6.nix modules so the Noctalia and SekaiPop
# home generations keep their own static/runtime theming unchanged.
{ pkgs, lib, ... }:
let
  # Substitute the absolute template path into matugen's TOML config. matugen
  # does not expand $HOME, and this repo already hardcodes /home/thedreamdev.
  # This nixpkgs has no substituteAll; replaceVars is its checked replacement.
  matugenConfig = pkgs.replaceVars ./matugen-config.toml {
    template = "${./chillpill-theme.json.tmpl}";
    template_kitty = "${./kitty-theme.conf.tmpl}";
  };

  # The shell's own wrapper PATH excludes ~/.nix-profile/bin, so every tool the
  # hook needs is either substituted as a store path or put on PATH explicitly.
  # replaceVarsWith writes the script itself (and marks it executable); using
  # writeShellScriptBin with the derivation as `text` would only embed its path.
  matugenScript = pkgs.replaceVarsWith {
    src = ./chillpill-matugen.sh;
    name = "chillpill-matugen";
    dir = "bin";
    isExecutable = true;
    replacements = {
      awww = "${pkgs.awww}/bin/awww";
      matugen = "${pkgs.matugen}/bin/matugen";
      matugen_config = "${matugenConfig}";
      system_theme = "${pkgs.sekaipop}/share/sekaipop/sekaipop/scripts/theming/system-theme.sh";
      # system-theme.sh calls matugen and a handful of coreutils/grep/awk tools
      # by name; glib/dconf provide its gsettings/dconf steps.
      path_value = lib.makeBinPath (with pkgs; [ coreutils findutils gnugrep gnused gawk matugen glib dconf ]);
    };
  };
in {
  # The GTK icon theme is set explicitly below; don't let catppuccin override it.
  catppuccin.gtk.icon.enable = false;

  # Both gtk.css files already exist as leftover regular files from earlier
  # switches; without force, checkLinkTargets refuses to replace them.
  xdg.configFile."gtk-3.0/gtk.css".force = true;
  xdg.configFile."gtk-4.0/gtk.css".force = true;

  home.packages = with pkgs; [
    matugenScript
    matugen
    # system-theme.sh calls gsettings/gdbus/dconf for a few of its steps.
    glib
    dconf
  ];

  gtk = {
    enable = true;
    gtk2.enable = false;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    iconTheme = {
      name = "noctalia-folders";
      package = pkgs.papirus-icon-theme;
    };
    font = {
      name = "Monocraft";
      size = 11;
    };
    # system-theme.sh writes sekaipop-colors.css next to gtk.css and refuses to
    # edit symlinks; import it from the Nix-managed file instead. GTK reads the
    # CSS on next launch, which is intentional: no live reload means no flash.
    gtk3.extraCss = ''
      @import url("sekaipop-colors.css");
    '';
    gtk4.extraCss = ''
      @import url("sekaipop-colors.css");
    '';
  };

  qt = {
    enable = true;
    platformTheme.name = "qt6ct";
    style = {
      name = "qt6ct";
      package = pkgs.kdePackages.breeze;
    };
  };

  # Copied from the Noctalia Qt theme. Qt/KDE apps still read these when the
  # matugen palette is applied via qt6ct/kdeglobals.
  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_STYLE_OVERRIDE = "qt6ct";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    KDE_SESSION_VERSION = "6";
  };

  # Seed qt6ct.conf once. Home-manager must not manage this file: the SekaiPop
  # theming script rewrites it with ini_set (custom_palette/color_scheme_path),
  # and a later switch would otherwise stomp the generated palette.
  home.activation.matugenQtConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    qtconf="$HOME/.config/qt6ct/qt6ct.conf"
    if [ ! -e "$qtconf" ]; then
      ${pkgs.coreutils}/bin/mkdir -p "$HOME/.config/qt6ct"
      ${pkgs.coreutils}/bin/cat > "$qtconf" <<'EOF'
[Appearance]
style=Fusion
icon_theme=Papirus-Dark
custom_palette=false
color_scheme_path=/home/thedreamdev/.config/qt6ct/colors/sekaipop.conf
standard_dialogs=default

[Fonts]
fixed=@Variant(\0\0\0\x87\0Latos-Regular,10,-1,5,50,0,0,0,0,0)General=@Variant(\0\0\0\x87\0Space Grotesk,11,-1,5,50,0,0,0,0,0)
EOF
    fi
  '';

  # Seed the matugen kitty include once. Home-manager must not manage this
  # file: the wallpaper hook rewrites it, so a later switch would otherwise
  # replace the generated palette with a read-only store symlink.
  home.activation.matugenKittyConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    kitty_theme="$HOME/.config/kitty/themes/matugen.conf"
    if [ ! -e "$kitty_theme" ]; then
      ${pkgs.coreutils}/bin/mkdir -p "$HOME/.config/kitty/themes"
      ${pkgs.coreutils}/bin/cp ${./kitty-matugen-fallback.conf} "$kitty_theme"
    fi
  '';

  # ChillPill writes last_wallpaper on every wallpaper pick (Mod+A, cliphist
  # drops). Watching that file avoids wrapping awww: its wrapper PATH is built
  # into the flake package and does not include ~/.nix-profile/bin.
  systemd.user.services."chillpill-matugen" = {
    Unit.Description = "Theme ChillPill and GTK/Qt/KDE apps from the wallpaper";
    Service = {
      Type = "oneshot";
      ExecStart = "${matugenScript}/bin/chillpill-matugen";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.paths."chillpill-matugen" = {
    Unit.Description = "Re-theme when ChillPill changes the wallpaper";
    Path = {
      PathChanged = "%h/.cache/chillpill-shell/last_wallpaper";
      # systemd would default to this from the unit name; be explicit so the
      # link between the watcher and the one-shot service is visible.
      Unit = "chillpill-matugen.service";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
