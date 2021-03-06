set nocompatible              " be iMproved, required

filetype off                  " required

"w0rp/ale
let &runtimepath.=',~/.vim/bundle/ale'

" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()

Plugin 'VundleVim/Vundle.vim'
Plugin 'vim-airline/vim-airline'
Plugin 'https://github.com/scrooloose/nerdtree.git'
Plugin 'jistr/vim-nerdtree-tabs'
"Plugin 'joonty/vdebug'
Plugin 'fugitive.vim'
Plugin 'php.vim'
Plugin 'shawncplus/phpcomplete.vim'
Plugin 'xuyuanp/nerdtree-git-plugin'
Plugin 'ervandew/supertab'
Plugin 'ryanoasis/vim-devicons'
Plugin 'tiagofumo/vim-nerdtree-syntax-highlight'
Plugin 'ctrlpvim/ctrlp.vim'
Plugin 'Tagbar'
Plugin 'mileszs/ack.vim'
Plugin 'csv.vim'
"Plugin 'surround.vim'
Plugin 'scrooloose/nerdcommenter'
Plugin 'mattn/emmet-vim'
Plugin 'pearofducks/ansible-vim'
Plugin 'hashivim/vim-terraform'
Plugin 'hashivim/vim-packer'
Plugin 'hashivim/vim-vaultproject'
Plugin 'sheerun/vim-polyglot'
Plugin 'w0rp/ale'
Plugin 'Valloric/YouCompleteMe'
"Plugin 'ruanyl/vim-fixmyjs'

call vundle#end()            " required
filetype plugin indent on    " required


set omnifunc=syntaxcomplete#Complete
" To ignore plugin indent changes, instead use:
"filetype plugin on
"
" Brief help
" :PluginList       - lists configured plugins
" :PluginInstall    - installs plugins; append `!` to update or just :PluginUpdate
" :PluginSearch foo - searches for foo; append `!` to refresh local cache
" :PluginClean      - confirms removal of unused plugins; append `!` to auto-approve removal
"
" see :h vundle for more details or wiki for FAQ
" Put your non-Plugin stuff after this line
set encoding=utf8
set nu
set tabstop=2
set shiftwidth=2
set softtabstop=2
set expandtab
set backspace=indent,eol,start
set cursorline
set colorcolumn=100

set smartindent
set autoindent

set mouse=r

syntax on
autocmd FileType * set formatoptions=croql
set autoindent
set autowrite

" search
set hlsearch
set incsearch


set background=dark
let g:solarized_termtrans =   1
let g:solarized_visibility = "high"
let g:solarized_contrast = "high"
let g:solarized_italic=0
colorscheme solarized8_dark
"colorscheme solarized

" Ansible
let g:ansible_name_highlight = 'd'
let g:ansible_attribute_highlight = "ob"
let g:ansible_name_highlight = 'd'

" Status line
set laststatus=2
let g:airline_powerline_fonts = 1
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#tab_nr_type = 1

let g:ale_linters = {'javascript': ['eslint'],}

"ctrlp
set runtimepath^=~/.vim/bundle/ctrlp.vim

" NerdTree open if no file specified
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if argc() == 0 && !exists("s:std_in") | NERDTree | endif

"let g:nerdtree_tabs_open_on_console_startup=2
"let g:nerdtree_tabs_focus_on_files=1
let NERDTreeQuitOnOpen=1
map <C-n> :NERDTreeToggle<CR>

"remap help link
nmap <C-K> <C-]>

"Php Autocomplete
autocmd FileType php setlocal omnifunc=phpcomplete#CompletePHP
set completeopt=longest,menuone
let g:SuperTabDefaultCompletionType = "<c-x><c-o>"

" AutoPairs
let g:AutoPairsFlyMode = 1

" Highlights
let g:webdevicons_conceal_nerdtree_brackets = 1 
let g:WebDevIconsNerdTreeAfterGlyphPadding = ' '
let g:WebDevIconsNerdTreeBeforeGlyphPadding = ' '

let g:NERDTreeFileExtensionHighlightFullName = 1
let g:NERDTreeExactMatchHighlightFullName = 1
let g:NERDTreePatternMatchHighlightFullName = 1

"Snippets
let g:UltiSnipsExpandTrigger="<tab>"
let g:UltiSnipsJumpForwardTrigger="<c-b>"
let g:UltiSnipsJumpBackwardTrigger="<c-z>"

" Ack
let g:ackprg = 'ag --vimgrep --smart-case'                                                   
cnoreabbrev ag Ack                                                                           
cnoreabbrev aG Ack                                                                           
cnoreabbrev Ag Ack                                                                           
cnoreabbrev AG Ack

let php_folding=0

"emmet
let g:user_emmet_install_global = 0
autocmd FileType html,css EmmetInstall

nnoremap <silent> <F5> :!clear;python %<CR>
nnoremap <silent> <F4> :!clear;php %<CR>

"tagBar
nmap <F8> :TagbarToggle<CR>

"elm auto format
let g:elm_format_autosave = 1

"fixMyJs
let g:fixmyjs_engine = 'eslint'
"
"
" dl vundle
" git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim

"command for xml formatting with gg=G
set equalprg=xmllint\ --format\ -
