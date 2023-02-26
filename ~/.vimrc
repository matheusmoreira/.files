filetype plugin on
syntax on

set nocompatible
set list
set number
set mouse=a
set spell
set spelllang=en,pt
set whichwrap=b,s,<,>,[,]
set linebreak

hi clear SpellBad
hi SpellBad cterm=underline

fun! StripTrailingWhitespace()
    if &filetype =~ 'diff'
        return
    endif
    %s/\s\+$//e
endfun

autocmd BufWritePre * call StripTrailingWhitespace()

autocmd FileType c    setlocal noexpandtab tabstop=8 softtabstop=8 shiftwidth=8 textwidth=80
autocmd FileType html setlocal expandtab shiftwidth=2 softtabstop=2
