set nocompatible

filetype plugin on
syntax on

set encoding=utf-8
set hidden
set list
set listchars=tab:>\ ,trail:-
set number relativenumber
set mouse=a
set spell
set spelllang=en,pt
set whichwrap=b,s,<,>,[,]
set linebreak

set tabstop=8
set textwidth=80
autocmd FileType c          setlocal noexpandtab softtabstop=8 shiftwidth=8
autocmd FileType html       setlocal expandtab   softtabstop=2 shiftwidth=2 textwidth=0
autocmd FileType javascript setlocal expandtab   softtabstop=4 shiftwidth=4

highlight SpecialKey term=NONE cterm=NONE

highlight SpellBad   term=underline cterm=underline ctermbg=NONE
highlight SpellCap   term=underline cterm=underline ctermbg=NONE
highlight SpellRare  term=underline cterm=underline ctermbg=NONE
highlight SpellLocal term=underline cterm=underline ctermbg=NONE

fun! StripTrailingWhitespace()
    if &filetype =~ 'diff'
        return
    endif
    %s/\s\+$//e
endfun

autocmd BufWritePre * call StripTrailingWhitespace()
