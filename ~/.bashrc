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

# Git status data collection for prompt-build-args.
# Fills the caller's associative array; returns 1 if not in a git repository.
# shellcheck disable=SC2154  # associative array keys are not variable references
prompt-git-data() {
  local -n _git_ref="${1}"
  local git_directory
  if git_directory="$(git rev-parse --git-dir 2>/dev/null)" && [[ -n "${git_directory}" ]]
  then
    :
  else
    return 1
  fi

  _git_ref[operation]=''
  if [[ -d "${git_directory}/rebase-merge" || -d "${git_directory}/rebase-apply" ]]; then
    _git_ref[operation]='rebase'
  elif [[ -f "${git_directory}/MERGE_HEAD" ]]; then
    _git_ref[operation]='merge'
  elif [[ -f "${git_directory}/CHERRY_PICK_HEAD" ]]; then
    _git_ref[operation]='pick'
  elif [[ -f "${git_directory}/REVERT_HEAD" ]]; then
    _git_ref[operation]='revert'
  elif [[ -f "${git_directory}/BISECT_LOG" ]]; then
    _git_ref[operation]='bisect'
  fi

  _git_ref[commit]='' _git_ref[branch]='' _git_ref[upstream]=''
  _git_ref[stashed]=0 _git_ref[staged]=false _git_ref[unstaged]=false
  _git_ref[untracked]=false _git_ref[conflicted]=false

  local ab='' status
  if status="$(git status --porcelain=v2 --branch --show-stash)"; then
    local line
    while read -r line; do
      case "${line}" in
        '# branch.oid '*)     _git_ref[commit]="${line#'# branch.oid '}" ;;
        '# branch.head '*)    _git_ref[branch]="${line#'# branch.head '}" ;;
        '# branch.upstream '*)_git_ref[upstream]="${line#'# branch.upstream '}" ;;
        '# branch.ab '*)      ab="${line#'# branch.ab '}" ;;
        '# stash '*)          _git_ref[stashed]="${line#'# stash '}" ;;
        '1 '* | '2 '*)
          [[ "${line:2:1}" != '.' ]] && _git_ref[staged]=true
          [[ "${line:3:1}" != '.' ]] && _git_ref[unstaged]=true
          ;;
        'u '*)                _git_ref[conflicted]=true ;;
        '? '*)                _git_ref[untracked]=true ;;
      esac
    done <<< "${status}"
  fi

  if [[ "${_git_ref[commit]}" != "(initial)" ]]; then
    _git_ref[commit]="$(git rev-parse --short "${_git_ref[commit]}" 2>/dev/null)" || _git_ref[commit]=''
  else
    _git_ref[commit]=''
  fi

  _git_ref[ahead]=0 _git_ref[behind]=0
  if [[ -n "${ab}" ]]; then
    local ahead behind
    read -r ahead behind <<< "${ab}"
    _git_ref[ahead]="${ahead#+}"
    _git_ref[behind]="${behind#-}"
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

  local host="${HOSTNAME%%.*}"
  if [[ -z "${TMUX:-}" && -z "${VIRTDEV_STATUS_SOCKET:-}" && -z "${SSH_CONNECTION:-}" ]]; then
    host=''
  fi

  _build_args_ref=("${exit_code}" "${directory}" "${host}")

  local -A git=()
  if prompt-git-data git; then
    _build_args_ref+=("${git[branch]}" "${git[commit]}" "${git[operation]}"
                      "${git[upstream]}" "${git[conflicted]}" "${git[staged]}"
                      "${git[unstaged]}" "${git[untracked]}" "${git[stashed]}"
                      "${git[ahead]}" "${git[behind]}")
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

  local -a prompt_args=()
  prompt-build-args prompt_args "${status}"

  if [[ -n "${TMUX}" ]]; then
    tmux set-option -pq @shell_status "$(prompt-render tmux "${prompt_args[@]}")" 2>/dev/null || true
    PS1='\$ '
  elif [[ -n "${VIRTDEV_STATUS_SOCKET:-}" ]]; then
    _virtdev_status_write "$(prompt-status-record prompt_args)"
    PS1='\$ '
  else
    PS1="$(prompt-render bash "${prompt_args[@]}")"
    PS1+='\$ '
  fi

  return "${status}"
}

PROMPT_COMMAND=(prompt-command)

# Exported environment variables

export EDITOR=vim
export LIBVIRT_DEFAULT_URI=qemu:///system
