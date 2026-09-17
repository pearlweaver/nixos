{ ryokuSession ? false, ... }: {
  imports = [ (if ryokuSession then ./themes/rose-pine.nix else ./themes/noctalia.nix) ];
}
