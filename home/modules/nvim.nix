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
          airline = true;
        };
      };
    };

    # =========================
    # PLUGINS
    # =========================
    plugins = {
      startify.enable = true;

      airline = {
        enable = true;
        settings = {
          airline_theme = "catppuccin_mocha";
          airline_section_x = "";
          airline_section_y = "%y";
          airline_section_z = "%p%% %l:%v";
          "airline#parts#virtualcol#enabled" = 0;
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
    # C++ COMPILE & RUN
    # =========================
    extraConfigVim = ''
      autocmd VimEnter * AirlineTheme catppuccin_mocha
      function! CompileRunCpp()
          let l:dir_path   = expand('%:p:h')
          let l:sourcefile = expand('%:t')
          let l:executable = expand('%:t:r')
          let l:build_dir  = l:dir_path . '/.build'
          if !isdirectory(l:build_dir)
              call mkdir(l:build_dir, 'p', 0700)
          endif
          let l:src_shell = shellescape(l:dir_path . '/' . l:sourcefile)
          let l:out_shell = shellescape(l:build_dir . '/' . l:executable)
          let l:cmd = 'g++ -std=c++20 -Wall -Wextra -O2 ' . l:src_shell . ' -o ' . l:out_shell . ' 2>&1'
          echo 'Compiling ' . l:sourcefile . '...'
          cexpr system(l:cmd)
          if len(getqflist()) > 0
              copen
              echohl ErrorMsg | echo 'Compilation FAILED.' | echohl None
              return
          endif
          echohl WarningMsg | echo 'Compilation successful!' | echohl None
          execute 'lcd ' . fnameescape(l:dir_path)
          execute 'botright split | terminal ' . l:out_shell
      endfunction

      autocmd FileType cpp nnoremap <buffer> <F5> :call CompileRunCpp()<CR>
    '';
  };
}