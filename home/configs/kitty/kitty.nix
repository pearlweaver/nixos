{ hyprlandSession ? false, matugenTheme ? false, ... }: {
  imports =
    if hyprlandSession then
      [ ./themes/rose-pine.nix ]
    else if matugenTheme then
      [ ./themes/matugen.nix ]
    else
      [ ./themes/noctalia.nix ];
}