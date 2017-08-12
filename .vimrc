set nocompatible              " be iMproved, required
filetype off                  " required

" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
" alternatively, pass a path where Vundle should install plugins
"call vundle#begin('~/some/path/here')

" let Vundle manage Vundle, required
Plugin 'VundleVim/Vundle.vim'

Plugin 'marijnh/tern_for_vim'
Plugin 'Valloric/YouCompleteMe'
Plugin 'tmhedberg/SimpylFold'

Plugin 'terryma/vim-multiple-cursors'

Plugin 'christoomey/vim-tmux-navigator'

Plugin 'pangloss/vim-javascript'
Plugin 'rust-lang/rust.vim'
Plugin 'fatih/vim-go'

Bundle 'Raimondi/delimitMate'

call vundle#end()

filetype plugin indent on
syntax on

colorscheme Tomorrow-Night

set number
set relativenumber

function! NumberToggle()
	if(&relativenumber == 1)
		set norelativenumber
	else
		set relativenumber
	endif
endfunc

autocmd InsertEnter * :set norelativenumber
autocmd InsertLeave * :set relativenumber

nnoremap <C-y> :call NumberToggle()<cr>

set foldmethod=syntax
set foldlevelstart=0
set tabstop=2 shiftwidth=2

set showmatch

set ignorecase
set smartcase

set hlsearch

" Rebind for Dvorak
no t j
no n k
no s l
no l n
no L N

no zt zj
no zn zk

let g:multi_cursor_use_default_mapping=0

let g:multi_cursor_next_key='<C-l>'
let g:multi_cursor_prev_key='<C-p>'
let g:multi_cursor_skip_key='<C-x>'
let g:multi_cursor_quit_key='<Esc>'

no - $
no j s

" Fix bindings for netrw
augroup netrw_dvorak_fix
	autocmd!
	autocmd filetype netrw call Fix_netrw_maps_for_dvorak()
augroup END
function! Fix_netrw_maps_for_dvorak()
	noremap <buffer> t gj
	noremap <buffer> n gk
	noremap <buffer> s l
	noremap <buffer> l n
endfunction

no - $
no _ ^
no T 8<Down>
no N 8<Up>

let g:tmux_navigator_no_mappings = 1

nnoremap <silent> <C-h> :TmuxNavigateLeft<cr>
nnoremap <silent> <C-t> :TmuxNavigateDown<cr>
nnoremap <silent> <C-n> :TmuxNavigateUp<cr>
nnoremap <silent> <C-s> :TmuxNavigateRight<cr>
nnoremap <silent> <C-\> :TmuxNavigatePrevious<cr>

set splitbelow
set splitright

nmap <C-J> O<Esc>
nmap <CR> o<Esc>

"remove trailing whitespace on save
autocmd BufWritePre * :%s/\s\+$//e

augroup reload_vimrc " {
	autocmd!
	autocmd BufWritePost $MYVIMRC source $MYVIMRC
augroup END " }

autocmd CompleteDone * pclose

set wildmode=longest,list,full
set wildmenu

map <F1> <Esc>
imap <F1> <Esc>

command! W :execute ':silent w !sudo tee % > /dev/null' | :edit!
command! Wq :execute ':silent w !sudo tee % > /dev/null' | :edit! | :q
nnoremap Q <nop>

set viminfo='20,\"100,:20,%,n~/.viminfo'
set history=50

set noerrorbells visualbell t_vb=
autocmd GUIEnter * set visualbell t_vb=
