# ChillPill-only theming: the wallpaper drives GTK/Qt/KDE colours via matugen.
# Kept out of the shared gtk.nix/qt6.nix modules so the Noctalia and SekaiPop
# home generations keep their own static/runtime theming unchanged.
{ pkgs, lib, ... }: {
  # The GTK icon theme is set explicitly below; don't let catppuccin override it.
  catppuccin.gtk.icon.enable = false;

  home.packages = with pkgs; [
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
}
