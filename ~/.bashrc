# ~/.bashrc
# Interactive shell configuration script for bash

# These settings only make sense for interactive shells.
# Do nothing if shell is not interactive.
[[ $- != *i* ]] && return

# Aliases

alias ls='ls -lahp --group-directories-first --color=auto'

# Prompt

PS1='[\W]\$ '

# Exported environment variables

export EDITOR=vim
