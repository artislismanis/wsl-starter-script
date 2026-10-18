#!/usr/bin/env bash
# Rewrite every pinned `${MISE_<NAME>_VERSION:-<ver>}` default in a module to
# what `mise latest` reports: for the `# bump: <spec>` on that line if there is
# one, else for the tool spelled just before the `@`. Prints "spec: old -> new"
# per change. Needs mise on PATH (and GITHUB_TOKEN for API rate limits).
set -euo pipefail

file="${1:-modules/40-mise.sh}"
pin_re='\$\{MISE_[A-Z_]+_VERSION:-([^}]+)\}'
tool_re='([^]["@[:space:]]+)(\[[^]]*\])?@\$\{MISE_'
bump_re='# bump: ([^[:space:]]+)'

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

while IFS= read -r line; do
  if [[ "$line" =~ $pin_re ]]; then
    cur="${BASH_REMATCH[1]}"
    if [[ "$line" =~ $bump_re ]] || [[ "$line" =~ $tool_re ]]; then
      spec="${BASH_REMATCH[1]}"
    else
      echo "bump-pins: can't tell which tool this pins: $line" >&2
      exit 1
    fi
    new="$(mise latest "$spec")"
    if [ -n "$new" ] && [ "$new" != "$cur" ]; then
      line="${line/":-$cur}"/":-$new}"}"
      echo "$spec: $cur -> $new"
    fi
  fi
  printf '%s\n' "$line" >>"$tmp"
done <"$file"

cat "$tmp" >"$file"
