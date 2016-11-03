set nocompatible              " be iMproved, required

filetype off                  " required

" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()

Plugin 'VundleVim/Vundle.vim'
Plugin 'pearofducks/ansible-vim'
Plugin 'vim-airline/vim-airline'
Plugin 'Syntastic'
Plugin 'https://github.com/scrooloose/nerdtree.git'
Plugin 'jistr/vim-nerdtree-tabs'
Plugin 'joonty/vdebug'
Plugin 'fugitive.vim'
Plugin 'php.vim'
Plugin 'shawncplus/phpcomplete.vim'
Plugin 'jiangmiao/auto-pairs'
Plugin 'xuyuanp/nerdtree-git-plugin'
Plugin 'ervandew/supertab'
Plugin 'Solarized'
Plugin 'ryanoasis/vim-devicons'
Plugin 'tiagofumo/vim-nerdtree-syntax-highlight'
Plugin 'ctrlpvim/ctrlp.vim'

call vundle#end()            " required
filetype plugin indent on    " required
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
set tabstop=4
set shiftwidth=4
set softtabstop=4
set expandtab

set smartindent
set autoindent

set mouse=a

syntax on
set background=dark
let g:solarized_visibility = "high"
let g:solarized_contrast = "high"
let g:solarized_italic=0
colorscheme solarized

" Ansible
let g:ansible_name_highlight = 'd'
let g:ansible_attribute_highlight = "ob"
let g:ansible_name_highlight = 'd'

" Status line
set laststatus=2
let g:airline_powerline_fonts = 1

" Syntastic
set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*

let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_wq = 0
let g:syntastic_php_checkers = ['php']

"ctrlp
set runtimepath^=~/.vim/bundle/ctrlp.vim

" NerdTree open if no file specified
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if argc() == 0 && !exists("s:std_in") | NERDTree | endif

let g:nerdtree_tabs_open_on_console_startup=2
let g:nerdtree_tabs_focus_on_files=1
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

