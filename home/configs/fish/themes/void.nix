{ config, ... }: {
  programs.starship.settings = {
    palette = "void";

    palettes.void = {
      rosewater = "#ffffff";
      flamingo = "#ffffff";
      pink = "#ffffff";
      mauve = "#cccccc";
      red = "#888888";
      maroon = "#888888";
      peach = "#aaaaaa";
      yellow = "#bbbbbb";
      green = "#999999";
      teal = "#999999";
      sky = "#dddddd";
      sapphire = "#dddddd";
      blue = "#ffffff";
      lavender = "#cccccc";
      text = "#ffffff";
      subtext1 = "#bbbbbb";
      subtext0 = "#999999";
      overlay2 = "#777777";
      overlay1 = "#555555";
      overlay0 = "#444444";
      surface2 = "#333333";
      surface1 = "#1a1a1a";
      surface0 = "#111111";
      base = "#000000";
      mantle = "#000000";
      crust = "#000000";
    };
  };

  catppuccin = {
    enable = false;
  };
}
