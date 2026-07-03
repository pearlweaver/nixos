{ pkgs, ... }:
let
  noctis = pkgs.vscode-utils.buildVscodeMarketplaceExtension {
    mktplcRef = {
      publisher = "alexdauenhauer";
      name = "catppuccin-noctis";
      version = "3.1.9";
    };
    vsix = pkgs.fetchurl {
      url = "https://open-vsx.org/api/alexdauenhauer/catppuccin-noctis/3.1.9/file/download";
      hash = "sha256-k94REvJn8gp1PLh9E2WUXmNnSAnFD7OuZrFrjKeDGWQ=";
    };
  };

  noctis-icons = pkgs.vscode-utils.buildVscodeMarketplaceExtension {
    mktplcRef = {
      publisher = "alexdauenhauer";
      name = "catppuccin-noctis-icons";
      version = "0.3.0";
    };
    vsix = pkgs.fetchurl {
      url = "https://open-vsx.org/api/alexdauenhauer/catppuccin-noctis-icons/0.3.0/file/download";
      hash = "sha256-dlBwnhCcBcIUE8qggLS7I6m7ZSC7ge+Vl2YGglprurI=";
    };
  };
in {
  programs.vscode.extensions = with pkgs.vscode-extensions; [
    catppuccin.catppuccin-vsc
    catppuccin.catppuccin-vsc-icons
    noctis
    noctis-icons
  ];

  programs.vscode.userSettings = {
    "workbench.colorTheme" = "Catppuccin Mocha";
    "workbench.iconTheme" = "catppuccin-mocha";
    "workbench.productIconTheme" = "bongocat";
  };
}
