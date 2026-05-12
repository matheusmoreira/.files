# shellcheck shell=bash
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

# Terminal rendering library

# shellcheck disable=SC1090
source ~/.local/lib/bash/import
import terminal prompt

# Prompt

prompt-write() {
  if [[ -n "${TMUX:-}" ]]; then
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
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
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

# Git status data collection for both local and remote prompt paths.
# Populates _git_* variables; returns 1 if not in a git repository.
prompt-git-data() {
  local git_directory
  if git_directory="$(git rev-parse --git-dir 2>/dev/null)" && [[ -n "${git_directory}" ]]
  then
    :
  else
    return 1
  fi

  _git_operation=''
  if [[ -d "${git_directory}/rebase-merge" || -d "${git_directory}/rebase-apply" ]]; then
    _git_operation='rebase'
  elif [[ -f "${git_directory}/MERGE_HEAD" ]]; then
    _git_operation='merge'
  elif [[ -f "${git_directory}/CHERRY_PICK_HEAD" ]]; then
    _git_operation='pick'
  elif [[ -f "${git_directory}/REVERT_HEAD" ]]; then
    _git_operation='revert'
  elif [[ -f "${git_directory}/BISECT_LOG" ]]; then
    _git_operation='bisect'
  fi

  _git_commit='' _git_branch='' _git_upstream='' _git_ab=''
  _git_stashed=0 _git_staged=false _git_unstaged=false
  _git_untracked=false _git_conflicted=false

  local status
  if status="$(git status --porcelain=v2 --branch --show-stash)"; then
    local line
    while read -r line; do
      case "${line}" in
        '# branch.oid '*)     _git_commit="${line#'# branch.oid '}" ;;
        '# branch.head '*)    _git_branch="${line#'# branch.head '}" ;;
        '# branch.upstream '*)_git_upstream="${line#'# branch.upstream '}" ;;
        '# branch.ab '*)      _git_ab="${line#'# branch.ab '}" ;;
        '# stash '*)          _git_stashed="${line#'# stash '}" ;;
        '1 '* | '2 '*)
          [[ "${line:2:1}" != '.' ]] && _git_staged=true
          [[ "${line:3:1}" != '.' ]] && _git_unstaged=true
          ;;
        'u '*)                _git_conflicted=true ;;
        '? '*)                _git_untracked=true ;;
      esac
    done <<< "${status}"
  fi

  if [[ "${_git_commit}" != "(initial)" ]]; then
    _git_commit="$(git rev-parse --short "${_git_commit}" 2>/dev/null)" || _git_commit=''
  else
    _git_commit=''
  fi

  _git_ahead=0 _git_behind=0
  if [[ -n "${_git_ab}" ]]; then
    local ahead behind
    read -r ahead behind <<< "${_git_ab}"
    _git_ahead="${ahead#+}"
    _git_behind="${behind#-}"
  fi
}

# Build the prompt arguments array for prompt-render.
# Both the local tmux path and the remote status path use this.
# First argument is the name of the caller's array variable.
prompt-build-args() {
  local -n _build_args_ref="${1}"
  local exit_code="${2}"

  local directory
  case "${PWD}" in
    "${HOME}"/*)  directory="~${PWD:${#HOME}}" ;;
    "${HOME}")    directory='~' ;;
    *)            directory="${PWD}" ;;
  esac

  _build_args_ref=("${exit_code}" "${directory}" "${HOSTNAME%%.*}")

  if prompt-git-data; then
    _build_args_ref+=("${_git_branch}" "${_git_commit}" "${_git_operation}"
                      "${_git_upstream}" "${_git_conflicted}" "${_git_staged}"
                      "${_git_unstaged}" "${_git_untracked}" "${_git_stashed}"
                      "${_git_ahead}" "${_git_behind}")
  fi
}

# Serialize prompt args as a Unit Separator (0x1F) delimited record.
prompt-status-record() {
  local -n _record_args_ref="${1}"
  local sep=$'\x1f'
  local IFS="${sep}"
  printf '1%s%s\n' "${sep}" "${_record_args_ref[*]}"
}

# Persistent status socket connection management.
_virtdev_status_fd=''

_virtdev_status_open() {
  trap '' PIPE
  mkdir -p "$(dirname "${VIRTDEV_STATUS_SOCKET}")" 2>/dev/null
  exec 7> >(socat -u - UNIX-CONNECT:"${VIRTDEV_STATUS_SOCKET}" 2>/dev/null)
  _virtdev_status_fd=7
}

_virtdev_status_write() {
  if [[ -z "${_virtdev_status_fd}" ]]; then
    _virtdev_status_open
  fi
  if ! printf '%s\n' "$1" >&"${_virtdev_status_fd}"; then
    exec 7>&- 2>/dev/null
    _virtdev_status_fd=''
    _virtdev_status_open
    if ! printf '%s\n' "$1" >&"${_virtdev_status_fd}"; then
      exec 7>&- 2>/dev/null
      _virtdev_status_fd=''
    fi
  fi
} 2>/dev/null

prompt-command() {
  local status="$?"

  if [[ -n "${TMUX}" ]]; then
    local -a prompt_args=()
    prompt-build-args prompt_args "${status}"
    tmux set-option -pq @shell_status "$(prompt-render "${prompt_args[@]}")" 2>/dev/null || true
    PS1='\$ '
  elif [[ -n "${VIRTDEV_STATUS_SOCKET:-}" ]]; then
    local -a prompt_args=()
    prompt-build-args prompt_args "${status}"
    _virtdev_status_write "$(prompt-status-record prompt_args)"
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
