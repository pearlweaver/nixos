{ ... }: {
  imports = [ ./base.nix ];

  programs.kitty.extraConfig = "include themes/matugen.conf";
}
