{ config, pkgs, ... }: { 
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    liberation_ttf
    monocraft
    # The Perla web companion UI (home/modules/perla/perla-companion.css) names
    # this as the leading family in --font-mono, so dropping it here makes the
    # code blocks fall back to a generic and fails tests/test_scales.sh.
    #
    # The UI's text face needs NO entry: it leads with "Noto Serif", which
    # noto-fonts above already installs. That is the whole point of the token -
    # the leading family is the one this machine actually renders. Inter was
    # briefly installed for a sans-serif pass and removed when the UI went back
    # to serif; leaving it would have been the monocraft problem in reverse, an
    # installed font nothing references.
    jetbrains-mono
  ];
}
