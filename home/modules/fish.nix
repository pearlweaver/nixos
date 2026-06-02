{ config, pkgs, ... }:

{
  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      set fish_greeting # Clear the default friendly greeting text
    '';

    shellAliases = {
      ll = "ls -l";
      rebuild-nix = "cd ~/nixos-config && sudo nixos-rebuild switch --flake .#nixos";
      rebuild-home = "cd ~/nixos-config && home-manager switch --flake .#thedreamdev";
    };
  };

  catppuccin = {
    enable = true;
    flavor = "mocha"; # latte, frappe, macchiato, mocha
  };
}
