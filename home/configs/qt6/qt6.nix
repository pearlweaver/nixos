{ hyprlandSession ? false, ... }: {
  imports = [ (if hyprlandSession then ./themes/rose-pine.nix else ./themes/noctalia.nix) ];
}
