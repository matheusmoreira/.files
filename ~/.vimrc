filetype plugin on
syntax on

set encoding=utf-8
set nocompatible
set hidden
set list
set listchars=tab:>\ ,lead:-,leadmultispace:---\ ,trail:-
set number relativenumber
set mouse=a
set spell
set spelllang=en,pt
set whichwrap=b,s,<,>,[,]
set linebreak

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

autocmd FileType c    setlocal noexpandtab tabstop=8 softtabstop=8 shiftwidth=8 textwidth=80
autocmd FileType html setlocal expandtab shiftwidth=2 softtabstop=2
autocmd FileType javascript setlocal expandtab tabstop=4 softtabstop=4 shiftwidth=4 textwidth=80
