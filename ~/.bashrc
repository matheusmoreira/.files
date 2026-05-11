# ~/.bashrc
# Sourced by all bash shells
# Everything past the PATH adjustment is interactive-only

# Functions

function paths.list {
  [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1
  declare -n variable=$1

  echo "${variable}" | tr : '\n'
}

function paths.add {
  [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1
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
alias tree='tree -lh --du --dirsfirst --sort size'
alias g=git

# Terminal escape sequences

# Single tput -S call for all capabilities.
# The bel (0x07) character is interleaved
# as a record separator, since it cannot
# appear in SGR sequences.
declare -A terminal=()
terminal-init() {
  local -a keys=(
    ansi.foreground.black ansi.foreground.red
    ansi.foreground.green ansi.foreground.yellow
    ansi.foreground.blue  ansi.foreground.magenta
    ansi.foreground.cyan  ansi.foreground.white
    ansi.background.black ansi.background.red
    ansi.background.green ansi.background.yellow
    ansi.background.blue  ansi.background.magenta
    ansi.background.cyan  ansi.background.white
    attributes.bold       attributes.dim
    attributes.italics    attributes.underline
    attributes.reverse    attributes.standout
    attributes.invisible  attributes.blink
    attributes.reset
  )
  local -a capabilities=(
    'setaf 0' 'setaf 1' 'setaf 2' 'setaf 3'
    'setaf 4' 'setaf 5' 'setaf 6' 'setaf 7'
    'setab 0' 'setab 1' 'setab 2' 'setab 3'
    'setab 4' 'setab 5' 'setab 6' 'setab 7'
    bold dim sitm smul rev smso invis blink sgr0
  )
  local raw
  raw=$(printf '%s\nbel\n' "${capabilities[@]}" | tput -S 2>/dev/null)
  local -a values=()
  local value
  while IFS= read -rd $'\a' value; do
    values+=("${value}")
  done <<< "${raw}"
  local i
  for (( i = 0; i < ${#keys[@]}; i++ )); do
    terminal["${keys[i]}"]="${values[i]:-}"
  done
}
terminal-init
unset -f terminal-init

declare -A tmux_format=(
  [ansi.foreground.black]='#[fg=black]'
  [ansi.foreground.red]='#[fg=red]'
  [ansi.foreground.green]='#[fg=green]'
  [ansi.foreground.yellow]='#[fg=yellow]'
  [ansi.foreground.blue]='#[fg=blue]'
  [ansi.foreground.magenta]='#[fg=magenta]'
  [ansi.foreground.cyan]='#[fg=cyan]'
  [ansi.foreground.white]='#[fg=white]'
  [ansi.background.black]='#[bg=black]'
  [ansi.background.red]='#[bg=red]'
  [ansi.background.green]='#[bg=green]'
  [ansi.background.yellow]='#[bg=yellow]'
  [ansi.background.blue]='#[bg=blue]'
  [ansi.background.magenta]='#[bg=magenta]'
  [ansi.background.cyan]='#[bg=cyan]'
  [ansi.background.white]='#[bg=white]'
  [attributes.bold]='#[bold]'
  [attributes.dim]='#[dim]'
  [attributes.italics]='#[italics]'
  [attributes.underline]='#[underscore]'
  [attributes.reverse]='#[reverse]'
  [attributes.standout]='#[reverse]'
  [attributes.invisible]='#[hidden]'
  [attributes.blink]='#[blink]'
  [attributes.reset]='#[default]'
)

# Bash and readline need these codes to be escaped by surrounding them
# with \[ \] and \x01 and \x02 respectively to indicate they are
# non-printing characters, lest they interfere with their own codes.
for key in "${!terminal[@]}"; do
  terminal[${key}.escaped.bash]="\[${terminal[${key}]}\]"
  terminal[${key}.escaped.readline]=$'\x01'"${terminal[${key}]}"$'\x02'
done

terminal-write() {
  local output=''
  local selector=''

  # Current escaping mode for non-printable characters.
  # If escape=mode is passed as argument, turn on the specified
  # escaping mode. Currently supported modes are bash, readline,
  # and tmux. Bash and readline need this for line editing and
  # cursor positions. If non-printable characters aren't escaped,
  # these programs can get confused and overwrite part of the screen.
  # Really aggravating. Tmux #[...] codes are inherently
  # non-printing-safe within tmux's own parser.
  local escaping_mode=''

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      escape=bash | escape=readline | escape=tmux | escape='')
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

    if [[ "${escaping_mode}" == "tmux" ]]; then
      output+="${tmux_format[${selector}]}"
    else
      if [[ -n "${escaping_mode}" ]]; then
        selector+=".escaped.${escaping_mode}"
      fi
      output+="${terminal[${selector}]}"
    fi

    shift
  done

  printf '%s' "${output}"
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
  if [[ -n "${TMUX}" ]]; then
    terminal-write escape=tmux "$@"
  else
    terminal-write escape=bash "$@"
  fi
}

prompt-format() {
  if [[ -n "$1" ]]; then
    local input="$1"
    shift
    if [[ -n "${TMUX}" ]]; then
      terminal-write escape=tmux ' '
      terminal-format "${input}" escape=tmux "$@"
    else
      terminal-write escape=bash ' '
      terminal-format "${input}" escape=bash "$@"
    fi
  fi
}

prompt-working-directory() {
  local directory
  if [[ -n "${TMUX}" ]]; then
    case "${PWD}" in
      "${HOME}"/*)  directory="~${PWD:${#HOME}}" ;;
      "${HOME}")    directory='~' ;;
      *)            directory="${PWD}" ;;
    esac
  else
    directory='\w'
  fi
  if [[ -n "${SSH_CONNECTION}" ]]; then
    prompt-write '[ ' foreground=yellow "${HOSTNAME%%.*}" reset ' ' foreground=green "${directory}" reset ' ]'
  else
    prompt-write '[ ' foreground=green "${directory}" reset ' ]'
  fi
}

prompt-error-code() {
  local code="$1"
  local format

  if [[ "${code}" -ne 0 ]]; then
    format='foreground=red'
  else
    format='dim'
  fi

  printf -v code '%3d' "${code}"
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

  local operation=''
  if [[ -d "${git_directory}/rebase-merge" || -d "${git_directory}/rebase-apply" ]]; then
    operation='rebase'
  elif [[ -f "${git_directory}/MERGE_HEAD" ]]; then
    operation='merge'
  elif [[ -f "${git_directory}/CHERRY_PICK_HEAD" ]]; then
    operation='pick'
  elif [[ -f "${git_directory}/REVERT_HEAD" ]]; then
    operation='revert'
  elif [[ -f "${git_directory}/BISECT_LOG" ]]; then
    operation='bisect'
  fi

  if [[ -n "${operation}" ]]; then
    prompt-format "${operation}" foreground=magenta
  fi

  local status commit branch upstream ab stashed staged unstaged untracked conflicted
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
          if [[ "${line:2:1}" != '.' ]]; then
            staged='•'
          fi
          if [[ "${line:3:1}" != '.' ]]; then
            unstaged='*'
          fi
          ;;
        'u '*)
          conflicted='!' ; ;;
        '? '*)
          untracked='?' ; ;;
        *)
          :
      esac
    done <<< "${status}"
  fi

  if [[ -n "${conflicted}" || -n "${staged}" || -n "${unstaged}" || -n "${untracked}" || -n "${stashed}" ]]
  then
    prompt-write ' '
    if [[ -n "${conflicted}" ]]; then
      prompt-write foreground=red "${conflicted}" reset
    fi
    if [[ -n "${staged}" ]]; then
      prompt-write foreground=green "${staged}" reset
    fi
    if [[ -n "${unstaged}" ]]; then
      prompt-write foreground=magenta "${unstaged}" reset
    fi
    if [[ -n "${untracked}" ]]; then
      prompt-write foreground=blue "${untracked}" reset
    fi
    if [[ -n "${stashed}" ]]; then
      prompt-write foreground=cyan "${stashed}" reset
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

  if [[ -n "${TMUX}" ]]; then
    local shell_status
    shell_status="$(prompt-error-code "${status}"; prompt-working-directory; prompt-git)"
    if [[ "${shell_status}" != "${_shell_status_prev:-}" ]]; then
      if tmux set-option -pq @shell_status "${shell_status}"; then
        _shell_status_prev="${shell_status}"
      fi
    fi
    PS1='\$ '
  else
    PS1="$(prompt-working-directory; prompt-git; printf '%s' '\n'; prompt-error-code "${status}")"
    PS1+='\$ '
  fi

  return "${status}"
}

PROMPT_COMMAND=(prompt-command)

# Exported environment variables

export EDITOR=vim
export LIBVIRT_DEFAULT_URI=qemu:///system
