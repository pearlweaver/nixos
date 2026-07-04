{ config, ... }: {
  programs.starship.settings = {
    palette = "rose_pine";

    palettes.rose_pine = {
      rosewater = "#ebbcba";
      flamingo = "#ebbcba";
      pink = "#ebbcba";
      mauve = "#c4a7e7";
      red = "#eb6f92";
      maroon = "#eb6f92";
      peach = "#f6c177";
      yellow = "#f6c177";
      green = "#31748f";
      teal = "#31748f";
      sky = "#9ccfd8";
      sapphire = "#9ccfd8";
      blue = "#9ccfd8";
      lavender = "#c4a7e7";
      text = "#e0def4";
      subtext1 = "#908caa";
      subtext0 = "#6e6a86";
      overlay2 = "#6e6a86";
      overlay1 = "#524f67";
      overlay0 = "#403d52";
      surface2 = "#403d52";
      surface1 = "#26233a";
      surface0 = "#1f1d2e";
      base = "#191724";
      mantle = "#191724";
      crust = "#191724";
    };
  };

  catppuccin = {
    enable = false;
  };
}
