filetype plugin on
syntax on

set list
set number
set mouse=a
set spell
set spelllang=en,pt
set whichwrap=b,s,<,>,[,]
set linebreak

autocmd BufWritePre * %s/\s\+$//e
autocmd FileType html setlocal expandtab shiftwidth=2 softtabstop=2
