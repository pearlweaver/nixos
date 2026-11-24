{ lib, ... }: {
  imports = [ ./noctalia.nix ];

  programs.kitty.extraConfig = lib.mkForce "include themes/matugen.conf";
}
