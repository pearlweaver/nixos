" =========================
" PLUGINS
" =========================

call plug#begin('~/.local/share/nvim/plugged')

Plug 'catppuccin/nvim', { 'as': 'catppuccin' }
Plug 'mhinz/vim-startify'
Plug 'vim-airline/vim-airline'
Plug 'preservim/nerdtree'
Plug 'dense-analysis/ale'
Plug 'psliwka/vim-smoothie'

" Neovim extras
Plug 'neovim/nvim-lspconfig'
Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}

call plug#end()

" =========================
" CORE SETTINGS
" =========================

set termguicolors
set nocompatible

filetype on
filetype plugin on
filetype indent on
syntax on

set mouse=a
set number
set relativenumber

set shiftwidth=4
set tabstop=4
set expandtab

set scrolloff=10
set nowrap
set incsearch
set ignorecase
set smartcase
set showcmd
set noshowmode
set showmatch
set hlsearch
set history=1000
set wildmenu
set wildmode=list:longest
set wildignore=*.docx,*.jpg,*.png,*.gif,*.pdf,*.pyc,*.exe,*.flv,*.img,*.xlsx

" Fix trailing whitespace
autocmd BufWritePre * %s/\s\+$//e

" =========================
" NERDTREE
" =========================

map <F4> :NERDTreeToggle<CR>
let NERDTreeShowHidden=1

" =========================
" INSERT PAIRS
" =========================

inoremap ( ()<Left>
inoremap { {}<Left>
inoremap [ []<Left>
inoremap " ""<Left>
inoremap ' ''<Left>

" =========================
" C++ COMPILE & RUN
" =========================

function! CompileRunCpp()
    " 1. Working file and path info
    let l:dir_path   = expand('%:p:h')
    let l:sourcefile = expand('%:t')
    let l:executable = expand('%:t:r')

    " 2. Setup build directory
    " Use a build directory to avoid clutter and handle same-name files
    let l:build_dir = l:dir_path . '/.build'
    if !isdirectory(l:build_dir)
        " 'p' creates parent dirs, '0700' is permissions (owner only)
        call mkdir(l:build_dir, 'p', 0700)
    endif

    " 3. Full paths (handle spaces)
    " fnameescape is for VIM/NVIM commands/functions (like 'execute' 'lcd')
    let l:src = fnameescape(l:dir_path . '/' . l:sourcefile)
    " shellescape is for commands run in the shell (like 'g++')
    let l:out_shell = shellescape(l:build_dir . '/' . l:executable)
    " We need a fnameescaped path for the 'terminal' command later
    let l:out_fname = fnameescape(l:build_dir . '/' . l:executable)


    " 4. Compile Command
    " We use shellescape for the source file in the command string passed to system()
    let l:src_shell = shellescape(l:dir_path . '/' . l:sourcefile)

    " Compile with warnings; populate quickfix on error
    let l:cmd = 'g++ -std=c++20 -Wall -Wextra -O2 ' . l:src_shell . ' -o ' . l:out_shell . ' 2>&1'
    
    " Execute compilation and feed output to quickfix (cexpr)
    echo 'Compiling ' . l:sourcefile . '...'
    cexpr system(l:cmd)

    " 5. Check for Compilation Errors
    " If quickfix has entries, open it and stop.
    if len(getqflist()) > 0
        copen
        echohl ErrorMsg | echo 'Compilation FAILED. See quickfix list.' | echohl None
        return
    endif
    
    echohl WarningMsg | echo 'Compilation successful!' | echohl None

    " 6. Run Executable
    
    " Change local directory to the source file's directory. 
    " This ensures the program can find relative input/output files.
    execute 'lcd ' . fnameescape(l:dir_path)

    " Run executable in a terminal split so input/output works
    " botright split: open new split at the bottom-right corner
    " terminal {command}: execute the compiled program
    execute 'botright split | terminal ' . l:out_shell

    " Switch back to previous window (the editor)
    " wincmd p 
    " Optional: You might prefer to jump directly into the terminal window 
    " to interact with the running program immediately. If so, remove the 
    " 'wincmd p' line or add a separate mapping for that.
    " wincmd p

endfunction

" Set mapping for C++ files
autocmd FileType cpp nnoremap <buffer> <F5> :call CompileRunCpp()<CR>

" =========================
" CATPPUCCIN
" =========================

lua << EOF
require("catppuccin").setup({
  flavour = "mocha",
  integrations = {
        airline = true, -- This is the magic line
  },
})
EOF

colorscheme catppuccin-mocha
hi Normal guibg=NONE ctermbg=NONE

highlight Type       guifg=#89B4FA gui=bold
highlight Constant   guifg=#F9E2AF
highlight Identifier guifg=#BAC2DE

" =========================
" TREESITTER
" =========================

lua << EOF
require'nvim-treesitter.configs'.setup {
  highlight = { enable = true },
}
EOF

" =========================
" LSP (clangd) - migrated to new API (vim.lsp.config / vim.lsp.enable)
" =========================

lua << EOF
-- Optional: define on_attach/capabilities here if needed
local on_attach = function(client, bufnr)
  -- example: enable omnifunc for completion
  vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')
end

local capabilities = vim.lsp.protocol.make_client_capabilities()

-- register clangd server config and enable it
vim.lsp.config('clangd', {
  cmd = { "clangd", "--clang-tidy" },
  on_attach = on_attach,
  capabilities = capabilities,
})

vim.lsp.enable('clangd')
EOF

" =========================
" AIRLINE
" =========================

let g:airline_theme='catppuccin'
let g:airline_detect_theme=1

let g:airline_section_x = airline#section#create([])
let g:airline_section_y = airline#section#create(['filetype'])
let g:airline#parts#virtualcol#enabled = 0
let g:airline_section_z = airline#section#create(['%p%% %l:%v'])
