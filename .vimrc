set nocp
call pathogen#infect()
syntax on
filetype plugin indent on
call pathogen#infect()
filetype off 
syntax on 
filetype plugin indent on 
noremap <F12> :tabnew <CR>
noremap <F3> :tabprev <CR>
noremap <F4> :!./%< < inp <CR>
noremap Q :
noremap <F7> :w <CR> :make
noremap <F10> :w <CR> :make <CR> :!%:p:r <CR>
noremap <F8> :w <CR> :make <CR> :!%:p:r < inp <CR>
noremap <F6> :w <CR> :!g++ -std=c++11 -fsanitize=address -o %:p:r -g % grader.cpp <CR>
noremap <F5> :!%:p:r <CR>
"noremap <F10> :w <CR> :!clang++ -fsanitize=address -std=c++11 -O2 -o "%<" "%" && "./%<" <CR>
"noremap <F8> :w <CR> :!clang++ -fsanitize=address -std=c++11 -O2 -o "%<" "%" && ./%< < inp <CR>
inoremap <F1> <ESC>
nnoremap <F1> <nop>
vnoremap <F1> <ESC>


inoremap {<CR> {<CR>}<ESC>k$A<CR> 
inoremap jk <ESC>

noremap <TAB> %

let g:ycm_autoclose_preview_window_after_completion = 1
let g:ycm_global_ycm_extra_conf = 0 "'~/.vim/YcmEC.py'
let g:ycm_path_to_python_interpreter = '/usr/bin/python'

let g:ycm_error_symbol = 'ER'
let g:ycm_warning_symbol = 'WA'

let g:netrw_keepdir = 0
let g:netrw_list_hide = '\.dSYM/$'


let g:UltiSnipsExpandTrigger="<tab>"
let g:UltiSnipsJumpForwardTrigger="<tab>"
let g:UltiSnipsJumpBackwardTrigger="<c-z>"
let g:UltiSnipsUsePythonVersion = 2

let g:netrw_localrmdir='rm -r'

let g:tex_flavor='latex'
let g:vimtex_view_method = 'skim'

let mapleader = "\<Space>"
noremap <Leader>b ^
noremap <Leader>e <ESC>:e .<CR>
noremap <Leader>r <C-R>
noremap <Leader>j <C-W><C-J>
noremap <Leader>k <C-W><C-K>
noremap <Leader>h <C-W><C-H>
noremap <Leader>l <C-W><C-L>
noremap <Leader>u i_<ESC>r
noremap <Leader>n :vs 
noremap <Leader>q :q<CR>
noremap <Leader>o <C-O>
noremap <Leader>i <C-I>
noremap <Leader>a ggVG
noremap <Leader>s :w<CR>
" comment selected lines
nnoremap <Leader>/ ms0I//<ESC>`sll
vnoremap <Leader>/ ms0I//<ESC>`sll

colorscheme darkblue
colo nova
command! Kek source ~/.vimrc
command! Dvorak set keymap=russian-dvorak
command! Undvorak set keymap=
command! Temp execute "normal ggVGd" | :0r ~/Code/template.cpp  | :8
command! LLDB :!clang++ -fsanitize=address -std=c++17 -O0 -g -o "%<" "%" && lldb %<
command! CrRelease !crystal build --release % -o %< 
command! Inpout !%:p:r < inp > out
command! Iterm !osascript ~/iterm.scpt
command! Gdb !g++ -std=c++11 -O0 -g -o %< %
command! Testlib !clang++ -std=c++17 -O2 -o %< % -Wno-varargs -Wno-unknown-attributes
set shiftwidth=4
set tabstop=4
set relativenumber
set number
set ignorecase
set noerrorbells
set cin
set autoread
set autoindent
set history=1000
set smartindent
set guifont=Jetbrains\ Mono\ Regular:h14
"set autochdir
set noswapfile
set splitright
set vb t_vb=
autocmd FileType cpp setlocal makeprg=clang++\ -fsanitize=address\ -Wl,-stack_size\ -Wl,0x1000000000\ -std=gnu++17\ -g\ -o\ %<\ %\ -DONPC
autocmd FileType haskell setlocal makeprg=ghc\ %
autocmd FileType python setlocal makeprg=python3\ %
autocmd FileType ruby setlocal makeprg=ruby\ %
autocmd FileType sh setlocal makeprg=./%
autocmd FileType crystal setlocal makeprg=crystal\ %
autocmd FileType d setlocal makeprg=ldc2\ %
autocmd FileType kotlin setlocal makeprg=kotlinc\ %
au GUIEnter * simalt ~x

source $VIMRUNTIME/mswin.vim
behave mswin

"autocmd FocusLost :wa
"
"autocmd CursorHold * smile
"filetype plugin on 
"au FileType cpp setl ofu=ccomplete#CompleteCpp
syntax on
cd ~/Code
