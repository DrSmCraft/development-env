" NeoVim configuartion file
" Customized from https://github.com/cse30-fa22/basic_vimrc/blob/main/.vimrc

" disable vi compatibility (emulation of old bugs)
set nocompatible

" color theme
colorscheme elflord

" highlight syntax
syntax on
filetype on
set showmatch

" show file in titlebar
set title

" display line number
set number relativenumber
set textwidth=80

" set tabs and indentation
set autoindent
set tabstop=4
set expandtab
set shiftwidth=4

" search
set hlsearch
set incsearch
set ignorecase
set smartcase

" enable mouse in all modes
set mouse=a

" Plugins
call plug#begin()
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
call plug#end()
