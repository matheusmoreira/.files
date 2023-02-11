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

autocmd FileType c    setlocal noexpandtab tabstop=8 softtabstop=8 shiftwidth=8 textwidth=80
autocmd FileType html setlocal expandtab shiftwidth=2 softtabstop=2
