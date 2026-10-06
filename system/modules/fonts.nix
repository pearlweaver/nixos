{ config, pkgs, ... }: { 
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    liberation_ttf
    monocraft
    # Inter is the UI CHROME face (sidebar, buttons, labels, nav) as of
    # v26.10.5.x. The prose face is still Noto Serif, which noto-fonts above
    # already installs, and code is still JetBrains Mono below. This comment
    # used to record that Inter had been REMOVED; that is no longer true.
    inter
    # The Perla web companion UI (home/modules/perla/perla-companion.css) names
    # this as the leading family in --font-mono, so dropping it here makes the
    # code blocks fall back to a generic and fails tests/test_scales.sh.
    jetbrains-mono
  ];
}
