# ~/.bashrc
# Executed by interactive non-login shells

# Functions

function paths.list {
  declare -n variable=$1

  echo "${variable}" | tr : '\n'
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

# Bash and readline need these codes to be escaped by surrounding them
# with \[ \] and \x01 and \x02 respectively to indicate they are
# non-printing characters, lest they interfere with their own codes.
for key in "${!terminal[@]}"; do
  terminal[${key}.escaped.bash]="\[${terminal[${key}]}\]"
  terminal[${key}.escaped.readline]="\x01${terminal[${key}]}\x02"
done

terminal-write() {
  local output=''
  local selector=''

  # Current escaping mode for non-printable characters.
  # If escape=mode is passed as argument, turn on the specified
  # escaping mode. Currently supported modes are bash and readline.
  #
  # Bash and readline need this for line editing and cursor positions.
  # If non-printable characters aren't escaped, these programs can get
  # confused and overwrite part of the screen. Really aggravating.
  local escaping_mode=''

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      escape=bash | escape=readline | escape='')
        escaping_mode="${1#*=}"; shift; continue; ;;
      foreground=* | fg=*)
        selector="ansi.foreground.${1#*=}"; ;;
      background=* | bg=*)
        selector="ansi.background.${1#*=}"; ;;
      reset)
        selector='attributes.reset'; ;;
      bold | bright)
        selector='attributes.bold'; ;;
      dim)
        selector='attributes.dim'; ;;
      italics)
        selector='attributes.italics'; ;;
      underline | underlined)
        selector='attributes.underline'; ;;
      reverse | reversed | reverse-video | reversed-video)
        selector='attributes.reverse'; ;;
      standout | highlight | highlighted)
        selector='attributes.standout'; ;;
      invis | invisible)
        selector='attributes.invisible'; ;;
      blink | blinking)
        selector='attributes.blink'; ;;
      *)
        output+="${1}"; shift; continue; ;;
    esac

    if [[ -n "${escaping_mode}" ]]; then
      selector+=".escaped.${escaping_mode}"
    fi
    output+="${terminal[${selector}]}"

    shift
  done

  printf '%b' "${output}"
}

terminal-format() {
  if [[ -n "$1" ]]; then
    local input
    input="$1"
    shift
    terminal-write "$@" "${input}" reset
  fi
}

alias tty-write=terminal-write tty-fmt=terminal-format

# Prompt

prompt-write() {
  terminal-write escape=bash "$@"
}

prompt-format() {
  if [[ -n "$1" ]]; then
    local input="$1"
    shift
    terminal-write escape=bash ' '
    terminal-format "${input}" escape=bash "$@"
  fi
}

prompt-working-directory() {
  prompt-write '[ ' foreground=green '\w' reset ' ]'
}

prompt-error-code() {
  local code="$1"
  local format

  if [[ "${code}" -ne 0 ]]; then
    format='foreground=red'
  else
    format='dim'
  fi

  code="$(printf '%3d' "${code}")"
  prompt-write "${format}" "${code}" reset ' '
}

prompt-git() {
  local git_directory
  if git_directory="$(git rev-parse --git-dir 2>/dev/null)" && [[ -n "${git_directory}" ]]
  then
    prompt-format ± foreground=yellow
  else
    return 1
  fi

  local status commit branch upstream ab stashed modified untracked
  if status="$(git status --porcelain=v2 --branch --show-stash)"; then
    local line
    while read -r line; do
      case "${line}" in
        '# branch.oid '*)
          commit="${line#'# branch.oid '}" ; ;;
        '# branch.head '*)
          branch="${line#'# branch.head '}" ; ;;
        '# branch.upstream '*)
          upstream="${line#'# branch.upstream '}" ; ;;
        '# branch.ab '*)
          ab="${line#'# branch.ab '}" ; ;;
        '# stash '*)
          stashed="${line#'# stash '}" ; ;;
        '1 '* | '2 '*)
          modified='*' ; ;;
        '? '*)
          untracked='?' ; ;;
        *)
          :
      esac
    done <<< "${status}"
  fi

  if [[ -n "${untracked}" || -n "${modified}" || -n "${stashed}" ]]
  then
    prompt-write ' '
    if [[ -n "${untracked}" ]]; then
      prompt-write foreground=blue "${untracked}" reset
    fi
    if [[ -n "${modified}" ]]; then
      prompt-write foreground=red  "${modified}" reset
    fi
    if [[ -n "${stashed}" ]]; then
      prompt-write foreground=green "${stashed}" reset
    fi
  fi

  if [[ "${commit}" != "(initial)"  ]]; then
    if commit="$(git rev-parse --short "${commit}" 2>/dev/null)"; then
      prompt-format "${commit}" dim foreground=cyan
    fi
  else
    prompt-format ∅ dim
    return
  fi

  if [[ "${branch}" != "(detached)" ]]; then
    prompt-format "${branch}" bright
  else
    return
  fi

  if [[ -n "${upstream}" ]]; then
    prompt-format "${upstream}" dim
  else
    return
  fi

  local ahead behind
  read -r ahead behind <<< "${ab}"
  ahead="${ahead#+}"
  behind="${behind#-}"
  if [[ "${ahead}" -gt 0 ]]; then
    prompt-format + foreground=green
    prompt-write "${ahead}"
  fi
  if [[ "${behind}" -gt 0 ]]; then
    prompt-format - foreground=red
    prompt-write "${behind}"
  fi
}

prompt-command() {
  local status="$?"

  PS1=''
  PS1+="$(prompt-working-directory)"
  PS1+="$(prompt-git)"
  PS1+='\n'
  PS1+="$(prompt-error-code "${status}")"
  PS1+='\$ '
}

PROMPT_COMMAND=prompt-command

# Exported environment variables

export EDITOR=vim
