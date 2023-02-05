# ~/.bashrc
# Executed by interactive non-login shells

# Functions

function paths.list {
  declare -n variable=$1

  echo $variable | tr : '\n'
}

function paths.add {
  declare -n variable=$1

  case ":${variable}:" in
    *:"$2":*)
      ;;
    *)
      if [[ "$3" = "after" ]]
      then
        variable="${variable:+${variable}:}$2"
      else
        variable="$2${variable:+:${variable}}"
      fi
      ;;
  esac
}

paths.add PATH ~/.local/bin/

# These settings only make sense for interactive shells.
# Do nothing if shell is not interactive.
[[ $- != *i* ]] && return

# Aliases

alias ls='ls -lahp --group-directories-first --color=auto'
alias tree='tree -l --dirsfirst'

# Terminal escape sequences

declare -A terminal=(
  [ansi.foreground.black]=$(tput setaf 0)
  [ansi.foreground.red]=$(tput setaf 1)
  [ansi.foreground.green]=$(tput setaf 2)
  [ansi.foreground.yellow]=$(tput setaf 3)
  [ansi.foreground.blue]=$(tput setaf 4)
  [ansi.foreground.magenta]=$(tput setaf 5)
  [ansi.foreground.cyan]=$(tput setaf 6)
  [ansi.foreground.white]=$(tput setaf 7)

  [ansi.background.black]=$(tput setab 0)
  [ansi.background.red]=$(tput setab 1)
  [ansi.background.green]=$(tput setab 2)
  [ansi.background.yellow]=$(tput setab 3)
  [ansi.background.blue]=$(tput setab 4)
  [ansi.background.magenta]=$(tput setab 5)
  [ansi.background.cyan]=$(tput setab 6)
  [ansi.background.white]=$(tput setab 7)

  [attributes.reset]=$(tput sgr0)
  [attributes.bold]=$(tput bold)
  [attributes.dim]=$(tput dim)
  [attributes.italics]=$(tput sitm)
  [attributes.underline]=$(tput smul)
  [attributes.reverse]=$(tput rev)
  [attributes.standout]=$(tput smso)
  [attributes.invisible]=$(tput invis)
  [attributes.blink]=$(tput blink)
)

terminal-format() {
  local output=''

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      foreground=* | fg=*)
        output+="${terminal[ansi.foreground.${1#*=}]}"
        ;;
      background=* | bg=*)
        output+="${terminal[ansi.background.${1#*=}]}"
        ;;
      reset)
        output+="${terminal[attributes.reset]}"
        ;;
      bold | bright)
        output+="${terminal[attributes.bold]}"
        ;;
      dim)
        output+="${terminal[attributes.dim]}"
        ;;
      italics)
        output+="${terminal[attributes.italics]}"
        ;;
      underline | underlined)
        output+="${terminal[attributes.underline]}"
        ;;
      reverse | reversed | reverse-video | reversed-video)
        output+="${terminal[attributes.reverse]}"
        ;;
      standout | highlight | highlighted)
        output+="${terminal[attributes.standout]}"
        ;;
      invis | invisible)
        output+="${terminal[attributes.invisible]}"
        ;;
      blink | blinking)
        output+="${terminal[attributes.blink]}"
        ;;
      *)
        output+="$1"
        ;;
    esac
    shift
  done

  printf '%b' "${output}"
}

alias tty-fmt=terminal-format

# Prompt

prompt-pad() {
  if [[ -n "$1" ]]; then
    printf " %s" "$1"
  fi
}

prompt-working-directory() {
  terminal-format '[ ' foreground=green '\w' reset ' ]'
}

prompt-error-code() {
  local code="$?"

  if [[ "${code}" -ne 0 ]]; then
    local prompt
    prompt="$(terminal-format foreground=red "${code}" reset)"
    prompt-pad "${prompt}"
  fi
}

prompt-git() {
  local git_directory
  if git_directory="$(git rev-parse --git-dir 2>/dev/null)" && [[ -n "${git_directory}" ]]
  then
    prompt-pad "$(terminal-format foreground=yellow ± reset)"
  else
    return 1
  fi

  local commit branch
  if commit="$(git rev-parse --short HEAD 2>/dev/null)" && [[ -n "${commit}" ]]; then
    branch="$(git rev-parse --symbolic-full-name --abbrev-ref HEAD 2>/dev/null)"
    prompt-pad "$(terminal-format dim foreground=cyan "${commit}" reset)"
    prompt-pad "$(terminal-format bold "${branch}" reset)"
  else
    prompt-pad "$(terminal-format dim ∅ reset)"
    return
  fi

  local upstream_status
  if upstream_status="$(git rev-list --count --left-right 'HEAD...@{upstream}' 2>/dev/null)"
  then
    local ahead behind
    read -r ahead behind <<< "${upstream_status}"
    if [[ "${ahead}" -gt 0 ]]; then
      prompt-pad "$(terminal-format foreground=green '+' reset "${ahead}")"
    fi
    if [[ "${behind}" -gt 0 ]]; then
      prompt-pad "$(terminal-format foreground=red   '-' reset "${behind}")"
    fi
  fi
}

PS1=''
PS1+="$(prompt-working-directory)"
PS1+='$(prompt-error-code)'
PS1+='$(prompt-git)'
PS1+='\n'
PS1+='\$ '

# Exported environment variables

export EDITOR=vim
