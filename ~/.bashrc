# ~/.bashrc
# Executed by interactive non-login shells

# Functions

function paths.list {
  declare -n variable=$1

  echo $variable | tr : '\n'
}

# These settings only make sense for interactive shells.
# Do nothing if shell is not interactive.
[[ $- != *i* ]] && return

# Aliases

alias ls='ls -lahp --group-directories-first --color=auto'

# Prompt

PS1='[\W]\$ '

# Exported environment variables

export EDITOR=vim
