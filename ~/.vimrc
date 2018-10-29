filetype plugin on
syntax on

set number
set mouse=a
set spell
set spelllang=en,pt
set whichwrap=b,s,<,>,[,]
set linebreak

autocmd BufWritePre * %s/\s\+$//e
