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
        theme = "catppuccin";
        detectTheme = true;
        sectionX = [];
        sectionY = [ "filetype" ];
        sectionZ = [ "%p%% %l:%v" ];
      };

      nerdtree = {
        enable = true;
        showHidden = true;
      };

      ale.enable = true;
      smoothie.enable = true;

      # LSP Config
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

      # Treesitter
      treesitter = {
        enable = true;
        settings = {
          highlight = {
            enable = true;
          };
        };
      };
    };

    # =========================
    # CORE SETTINGS & GLOBALS
    # =========================
    globals = {
      "airline#parts#virtualcol#enabled" = 0;
    };

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
    keyMaps = [
      # NERDTree Toggle (Matches `map <F4>` across modes)
      {
        mode = "";
        key = "<F4>";
        action = ":NERDTreeToggle<CR>";
      }
      # Insert Pairs
      {
        mode = "i";
        key = "(";
        action = "()<Left>";
      }
      {
        mode = "i";
        key = "{";
        action = "{}<Left>";
      }
      {
        mode = "i";
        key = "[";
        action = "[]<Left>";
      }
      {
        mode = "i";
        key = "\"";
        action = "\"\"<Left>";
      }
      {
        mode = "i";
        key = "'";
        action = "''<Left>";
      }
    ];

    # =========================
    # HIGHLIGHTS
    # =========================
    highlights = {
      Normal = {
        guibg = "NONE";
        ctermbg = "NONE";
      };
      Type = {
        guifg = "#89B4FA";
        gui = "bold";
      };
      Constant = {
        guifg = "#F9E2AF";
      };
      Identifier = {
        guifg = "#BAC2DE";
      };
    };

    # =========================
    # C++ COMPILE & RUN FUNCTION
    # =========================
    extraConfigVim = ''
      function! CompileRunCpp()
          " 1. Working file and path info
          let l:dir_path   = expand('%:p:h')
          let l:sourcefile = expand('%:t')
          let l:executable = expand('%:t:r')

          " 2. Setup build directory
          let l:build_dir = l:dir_path . '/.build'
          if !isdirectory(l:build_dir)
              call mkdir(l:build_dir, 'p', 0700)
          endif

          " 3. Full paths (handle spaces)
          let l:src = fnameescape(l:dir_path . '/' . l:sourcefile)
          let l:out_shell = shellescape(l:build_dir . '/' . l:executable)
          let l:out_fname = fnameescape(l:build_dir . '/' . l:executable)

          " 4. Compile Command
          let l:src_shell = shellescape(l:dir_path . '/' . l:sourcefile)
          let l:cmd = 'g++ -std=c++20 -Wall -Wextra -O2 ' . l:src_shell . ' -o ' . l:out_shell . ' 2>&1'
          
          echo 'Compiling ' . l:sourcefile . '...'
          cexpr system(l:cmd)

          " 5. Check for Compilation Errors
          if len(getqflist()) > 0
              copen
              echohl ErrorMsg | echo 'Compilation FAILED. See quickfix list.' | echohl None
              return
          endif
          
          echohl WarningMsg | echo 'Compilation successful!' | echohl None

          " 6. Run Executable
          execute 'lcd ' . fnameescape(l:dir_path)
          execute 'botright split | terminal ' . l:out_shell
      endfunction

      " Set mapping for C++ files
      autocmd FileType cpp nnoremap <buffer> <F5> :call CompileRunCpp()<CR>
    '';
  };
}