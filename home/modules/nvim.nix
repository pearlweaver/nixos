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
        # integrations = {
        #   lualine = true;
        # };
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
            lualine_x = [ "" ];
            lualine_y = [ "filetype" ];
            lualine_z = [ "progress" "location" ];
          };
        };
      };

      nerdtree = {
        enable = true;
        showHidden = true;
      };

      ale.enable = true;
      smoothie.enable = true;

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

      treesitter = {
        enable = true;
        settings = {
          highlight.enable = true;
        };
      };
    };

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

    syntax = "on";

    # =========================
    # HIGHLIGHTS
    # =========================
    highlights = {
      Normal = { guibg = "NONE"; ctermbg = "NONE"; };
      Type = { guifg = "#89B4FA"; bold = true; };
      Constant = { guifg = "#F9E2AF"; };
      Identifier = { guifg = "#BAC2DE"; };
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
      {
        event = [ "FileType" ];
        pattern = [ "cpp" ];
        callback.__raw = ''
          function()
            vim.api.nvim_buf_set_keymap(0, 'n', '<F5>', ':LuaCompileRunCpp<CR>', { silent = true, noremap = true })
          end
        '';
      }
    ];

    # =========================
    # KEYMAPPINGS
    # =========================
    keymaps = [
      {
        mode = "";
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
    # MODERN C++ USER COMMAND
    # =========================
    extraConfigLua = ''
      vim.api.nvim_create_user_command('LuaCompileRunCpp', function()
        local dir_path = vim.fn.expand('%:p:h')
        local sourcefile = vim.fn.expand('%:t')
        local executable = vim.fn.expand('%:t:r')
        local build_dir = dir_path .. '/.build'

        if vim.fn.isdirectory(build_dir) == 0 then
          vim.fn.mkdir(build_dir, 'p', 448) -- 448 is 0700 octal
        end

        local src_shell = vim.fn.shellescape(dir_path .. '/' .. sourcefile)
        local out_shell = vim.fn.shellescape(build_dir .. '/' .. executable)
        local cmd = 'g++ -std=c++20 -Wall -Wextra -O2 ' .. src_shell .. ' -o ' .. out_shell .. ' 2>&1'

        print('Compiling ' .. sourcefile .. '...')
        vim.fn.cexpr(vim.fn.system(cmd))

        if #vim.fn.getqflist() > 0 then
          vim.cmd('copen')
          vim.api.nvim_echo({{ 'Compilation FAILED.', 'ErrorMsg' }}, true, {})
          return
        end

        vim.api.nvim_echo({{ 'Compilation successful!', 'WarningMsg' }}, true, {})
        vim.cmd('lcd ' .. vim.fn.fnameescape(dir_path))
        vim.cmd('botright split | terminal ' .. build_dir .. '/' .. executable)
      end, {})
    '';
  };
}