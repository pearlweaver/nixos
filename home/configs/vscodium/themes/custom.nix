{ pkgs, ... }: {
  programs.vscode.extensions = with pkgs.vscode-extensions; [
    catppuccin.catppuccin-vsc
    catppuccin.catppuccin-vsc-icons
  ];

  programs.vscode.userSettings = {
    "workbench.colorTheme" = "Catppuccin Mocha";
    "workbench.iconTheme" = "catppuccin-mocha";
    "workbench.productIconTheme" = "bongocat";
  };
}
