{ pkgs, lib, ... }:
let
  fromOpenVsx = { publisher, name, version, hash }:
    pkgs.vscode-utils.buildVscodeMarketplaceExtension {
      mktplcRef = { inherit publisher name version; };
      vsix = pkgs.fetchurl {
        url = "https://open-vsx.org/api/${publisher}/${name}/${version}/file/download";
        inherit hash;
      };
    };

  csharp = fromOpenVsx {
    publisher = "muhammad-sammy";
    name = "csharp";
    version = "2.145.21-g154a82fd27";
    hash = "sha256-i867SkBI4duaQJThB5eYv95uLWB/Ux/G/ZUDwD+gq68=";
  };

  clang-tidy = fromOpenVsx {
    publisher = "notskm";
    name = "clang-tidy";
    version = "0.5.1";
    hash = "sha256-j3DkamdDeHv8NFa3a4o00yB5j/JCbsVS+5W4VAcB9PE=";
  };

  antigravity-unity = fromOpenVsx {
    publisher = "antigravity-unity";
    name = "antigravity-unity";
    version = "1.2.52";
    hash = "sha256-NX8Nk3k4etKb+Pz1AncUnNZSmJGRzMnoXsq3xQ6QYI8=";
  };

  cmake-intellisence = fromOpenVsx {
    publisher = "kylinideteam";
    name = "cmake-intellisence";
    version = "0.8.0";
    hash = "sha256-oLpYSEasRAyifWAKzTAd8L1lrlkbO7WDBmzh6zBJR9M=";
  };

  kylin-cmake-tools = fromOpenVsx {
    publisher = "kylinideteam";
    name = "kylin-cmake-tools";
    version = "0.3.1";
    hash = "sha256-Fk4Kln9VmuR24KjY+yfyKmrkv9LBYBBwOLJXATpzZ7k=";
  };

  kylin-cpp-pack = fromOpenVsx {
    publisher = "kylinideteam";
    name = "kylin-cpp-pack";
    version = "0.2.0";
    hash = "sha256-RL94DM/jzCLpRVB91h3PIdhRg7In2AWM4zmNFpQdZF4=";
  };

  love2d = fromOpenVsx {
    publisher = "lazarus-overlook";
    name = "lazarusoverlook-love2d";
    version = "0.1.26";
    hash = "sha256-GCo+mfqsTqMZUdTJopzKcIs6o9Mc7WCFs4xI5KiBKx4=";
  };

  vstuc = fromOpenVsx {
    publisher = "zlorn";
    name = "vstuc";
    version = "1.2.1";
    hash = "sha256-NQgf5X3nbU18EwTaCA/SE1fPuJ2xhCNaVYPkvMs8/SA=";
  };
in {
  imports = [ ./themes/catppuccin.nix ];

  programs.vscode = {
    enable = true;
    package = pkgs.vscodium;
    enableUpdateCheck = false;
    enableExtensionUpdateCheck = false;

    extensions = with pkgs.vscode-extensions; [
      csharp
      dracula-theme.theme-dracula
      enkia.tokyo-night
      jnoortheen.nix-ide
      llvm-vs-code-extensions.vscode-clangd
      ms-dotnettools.vscode-dotnet-runtime
      ms-python.debugpy
      ms-python.python
      ms-python.vscode-python-envs
      mvllow.rose-pine
      sumneko.lua
      clang-tidy
      antigravity-unity
      cmake-intellisence
      kylin-cmake-tools
      kylin-cpp-pack
      love2d
      vstuc
    ];

    userSettings = {
      # Editor
      "editor.fontFamily" = "Monocraft, monospace";
      "editor.fontSize" = 15;
      "editor.fontLigatures" = true;
      "editor.lineNumbers" = "relative";
      "editor.tabSize" = 4;
      "editor.detectIndentation" = false;
      "editor.cursorBlinking" = "phase";
      "editor.cursorSmoothCaretAnimation" = "on";
      "editor.cursorStyle" = "block";
      "editor.smoothScrolling" = true;
      "editor.parameterHints.enabled" = true;
      "editor.hover.enabled" = "on";
      "editor.showFoldingControls" = "never";
      "editor.renderWhitespace" = "none";
      "editor.renderLineHighlight" = "none";
      "editor.occurrencesHighlight" = "off";
      "editor.selectionHighlight" = false;
      "editor.matchBrackets" = "never";
      "editor.guides.indentation" = false;
      "editor.lightbulb.enabled" = "off";
      "editor.scrollbar.verticalScrollbarSize" = 8;

      # Files
      "files.autoSave" = "afterDelay";
      "explorer.compactFolders" = false;

      # Terminal
      "terminal.explorerKind" = "external";
      "terminal.integrated.lineHeight" = 1;
      "terminal.integrated.letterSpacing" = 0;
      "terminal.integrated.fontSize" = 16;
      "terminal.integrated.gpuAcceleration" = "off";

      # Workbench
      "workbench.editor.showTabs" = "none";
      "workbench.tree.renderIndentGuides" = "none";
      "workbench.tree.indent" = 16;
      "workbench.activityBar.location" = "top";
      "workbench.navigationControl.enabled" = false;
      "workbench.editor.editorActionsLocation" = "hidden";
      "workbench.layoutControl.enabled" = false;

      # Window
      "window.autoDetectColorScheme" = false;
      "window.controlsStyle" = "custom";
      "window.menuBarVisibility" = "compact";
      "window.commandCenter" = false;

      # Extensions
      "clangd.path" = "/run/current-system/sw/bin/clangd";

      # OmniSharp
      "omnisharp.useModernNet" = false;
      "omnisharp.useGlobalMono" = "always";
      "omnisharp.monoPath" = "/run/current-system/sw";
      "omnisharp.sdkPath" = "/run/current-system/sw";

      # Lua
      "Lua.workspace.library" = {
        "/run/current-system/sw/share/love" = true;
      };
      "Lua.runtime.version" = "LuaJIT";
      "Lua.workspace.checkThirdParty" = false;
      "Lua.diagnostics.globals" = [ "love" ];

      # LÖVE
      "lazarusoverlook.love2d.path" = "/home/thedreamdev/.nix-profile/bin/love";

      # Misc
      "where-am-i.colorful" = false;
    };
  };
}
