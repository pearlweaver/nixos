{ ... }: {
  imports = [ ./base.nix ];

  programs.kitty.extraConfig = "include themes/noctalia.conf";
}
