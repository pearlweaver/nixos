{ lib, config, pkgs, ... }:

{
  programs.nixvim = {
    enable = true;

    # =========================
    # THEME (Catppuccin)
    # =========================
    colorschemes.catppuccin = {
      enable = true;
      settings = {
        flavour = "mocha";
        transparent_background = true;
        integrations = {
          lualine = true;
          treesitter = true;
        };
      };
    };

    # =========================
    # PLUGINS
    # =========================
    plugins = {
      startify.enable = true;

      lualine = {
        enable = true;
        settings = {
          options = {
            theme = "auto";
            globalstatus = true;
            component_separators = { left = ""; right = ""; };
            section_separators = { left = ""; right = ""; };
          };
          sections = {
            lualine_x = [ ];
            lualine_y = [ "filetype" ];
            lualine_z = [ "progress" "location" ];
          };
        };
      };

      treesitter = {
        enable = true;
        settings = {
          highlight.enable = true;
        };
      };

      lsp = {
        enable = true;
        servers = {
          clangd = {
            enable = true;
            package = pkgs.clang-tools;
            cmd = [ "clangd" "--clang-tidy" ];
          };
        };
      };
    };

    extraPlugins = with pkgs.vimPlugins; [
      vim-smoothie
      nerdtree
    ];

    # =========================
    # OPTIONS
    # =========================
    opts = {
      termguicolors = true;
      mouse = "a";
      number = true;
      relativenumber = true;
      shiftwidth = 4;
      tabstop = 4;
      expandtab = true;
      scrolloff = 10;
      wrap = false;
      incsearch = true;
      ignorecase = true;
      smartcase = true;
      showcmd = true;
      showmode = false;
      showmatch = true;
      hlsearch = true;
      history = 1000;
      wildmenu = true;
      wildmode = "list:longest";
      wildignore = [
        "*.docx" "*.jpg" "*.png" "*.gif" "*.pdf"
        "*.pyc" "*.exe" "*.flv" "*.img" "*.xlsx"
      ];
    };

    # =========================
    # HIGHLIGHTS
    # =========================
    highlight = {
      Normal = { bg = "NONE"; };
      Type = { fg = "#89B4FA"; bold = true; };
      Constant = { fg = "#F9E2AF"; };
      Identifier = { fg = "#BAC2DE"; };
    };

    # =========================
    # AUTOCOMMANDS
    # =========================
    autoCmd = [
      {
        event = [ "BufWritePre" ];
        pattern = [ "*" ];
        command = ":%s/\\s\\+$//e";
      }
    ];

    # =========================
    # KEYMAPPINGS
    # =========================
    keymaps = [
      {
        mode = "n";
        key = "<F4>";
        action = ":NERDTreeToggle<CR>";
      }
      { mode = "i"; key = "("; action = "()<Left>"; }
      { mode = "i"; key = "{"; action = "{}<Left>"; }
      { mode = "i"; key = "["; action = "[]<Left>"; }
      { mode = "i"; key = "\""; action = "\"\"<Left>"; }
      { mode = "i"; key = "'"; action = "''<Left>"; }
    ];

    # =========================
    # EXTRA CONFIG
    # =========================
    extraConfigVim = ''
      let NERDTreeShowHidden=1
    '';
  };
}
