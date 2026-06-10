#!/usr/bin/bash
# Generic git hygiene for a commit range: whitespace errors and
# conflict markers, overlong commit subjects, fixup/squash
# leftovers, TODO/FIXME markers added by the range.

repository="${1}"
range="${2}"

findings=0

found() {
  printf '%s\n' "${1}"
  findings=$((findings + 1))
}

while IFS= read -r line; do
  found "whitespace: ${line}"
done < <(git -C "${repository}" diff --check "${range}" 2>/dev/null)

while IFS= read -r subject; do
  if (( ${#subject} > 50 )); then
    found "subject over 50 characters: ${subject}"
  fi
done < <(git -C "${repository}" log --format=%s "${range}")

while IFS= read -r subject; do
  found "unfolded fixup: ${subject}"
done < <(git -C "${repository}" log --format=%s "${range}" | grep -E '^(fixup|squash)!')

while IFS= read -r line; do
  found "marker added: ${line}"
done < <(git -C "${repository}" diff "${range}" | grep -E '^\+.*(TODO|FIXME|XXX)\b' | head -20)

(( findings == 0 ))
