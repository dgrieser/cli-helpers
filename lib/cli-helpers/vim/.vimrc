" read and show text as UTF-8 whatever the locale, e.g. the non-breaking hyphens
" of a generated commit message instead of ~@~Q; set before anything reads text
set encoding=utf-8

" Esc responds instantly (defaults.vim is skipped because this file exists)
set ttimeout
set ttimeoutlen=50

" do not automatically wrap on load
set nowrap
highlight LineNr ctermfg=Grey guifg=Grey
" show existing tab with 4 spaces width
set tabstop=4
" when indenting with '>', use 4 spaces width
set shiftwidth=4
" Determines the amount of whitespace to add in normal mode
set softtabstop=4
" On pressing tab, insert 4 spaces
set expandtab
" Don't add indention on pasting
" set paste
" set smartindent
" set autoindent
set pastetoggle=<F2>
" use terminal colors
set termguicolors
set background=dark

set title
set titlestring=VIM\ %F

nnoremap <M-Up> :m-2<CR>
inoremap <M-Up> <Esc>:m-2<CR>a
nnoremap <M-Down> :m+1<CR>
inoremap <M-Down> <Esc>:m+1<CR>a

noremap <M-Left> :set norelativenumber nonumber<CR>
noremap <M-Right> :set relativenumber number<CR>
nnoremap <Tab> :set invexpandtab<CR>

imap <Insert> <Nop>
inoremap <S-Insert> <Insert>
hi statusline guibg=LightGrey ctermfg=8 guifg=White ctermbg=15
set laststatus=2
set statusline=%<%f\ \{…\}\ \%{get(g:,'codeium_enabled',1)?codeium#GetStatusString():''}\ %h%m%r%=%-14.(%l,%c%V%)\ %P

" reopen a file at the last cursor position, but a commit message at the top
augroup RestoreCursor
  autocmd!
  autocmd BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") && &ft !~# 'commit' | exe "normal! g'\"" | endif
augroup END

autocmd VimEnter * imap <C-y>   <Cmd>call codeium#CycleCompletions(1)<CR>
" imap <C-d>   <Cmd>call codeium#Clear()<CR>

" make sure we return with a non-zero exit code on quit for git commits; only
" the whole ':' command, so a 'q' in a search or substitution stays as it is
augroup GitCommitAbort
  autocmd!
  autocmd FileType gitcommit cnoreabbrev <buffer> <expr> q! (getcmdtype() ==# ':' && getcmdline() ==# 'q!') ? 'cq' : 'q!'
  autocmd FileType gitcommit cnoreabbrev <buffer> <expr> q  (getcmdtype() ==# ':' && getcmdline() ==# 'q') ? 'cq' : 'q'
augroup END

" vimdiff hints; no space before the '|' after a mapping, it would be mapped too
augroup VimdiffHints
  autocmd!
  autocmd VimEnter,WinEnter * if &diff |
        \ echo "Take diff: do | Put diff: dp | Toggle window: ctrl-w+w | Navigate diffs: ctrl-up/down | Unfold: zR" |
        \   nnoremap <buffer> <C-Down> ]c|
        \   nnoremap <buffer> <C-Up>   [c|
        \ endif
augroup END

" commands; :Clip copies the whole file, :'<,'>Clip the selected lines
command! -range=% Clip silent <line1>,<line2>yank x | call system('xclip -sel c', getreg('x'))
command! BashBraces %s/\$\(\w\+\)/${\1}/g

" Make ':X' (encrypt file) behave like ':x' -- it's an easy typo.
" Built-ins can't be overridden by user commands, so rewrite it on the
" command line instead; only when it's the whole ':' command.
cnoreabbrev <expr> X (getcmdtype() ==# ':' && getcmdline() ==# 'X') ? 'x' : 'X'

" Codeium probes the platform with two blocking system('uname') calls on
" BufEnter. Each one drops the terminal out of raw mode and back, which
" swallows any keystroke typed at that moment -- typically the ':' of ':x',
" leaving the following 'x' to run as a normal-mode delete. Presetting these
" skips the probe entirely (see autoload/codeium/server.vim).
let g:codeium_os = 'Linux'
let g:codeium_arch = 'x86_64'
" Codeium only on amd64, which the updater installs it on; elsewhere a leftover
" install stays switched off. The kernel names its architecture (what uname -m
" prints) in /proc, read without a shell.
let g:codeium_enabled = filereadable('/proc/sys/kernel/arch')
    \ && get(readfile('/proc/sys/kernel/arch', '', 1), 0, '') ==# 'x86_64'

let g:codeium_filetypes = {
    \ "gitcommit": v:true,
    \ }

call plug#begin()
" Plug 'https://github.com/yegappan/lsp'
call plug#end()

" jq language server + data-aware key completion, currently switched off.
" To turn it back on: uncomment the yegappan/lsp line above, drop the
" g:loaded_jq_lsp line below, and see ~/.vim/plugin/jq-lsp.vim
let g:loaded_jq_lsp = 1
