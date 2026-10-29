#!/usr/bin/env bash
# Rewrite the release-binary and commit pins in a module:
#   <NAME>_VERSION=<ver>  # bump: github:<owner/repo> <asset>
#   <NAME>_SHA256=<sha>                       (the line right after)
#   <NAME>_COMMIT=<sha>   # bump: git:<owner/repo>
# A version moves to the repo's latest release and its sha256 is recomputed
# from the downloaded asset; a commit moves to the default branch's tip.
# Prints "repo: old -> new" per change. Needs gh (GH_TOKEN) and curl.
set -euo pipefail

file="${1:-modules/55-workbench.sh}"
ver_re='^([A-Z_]+)_VERSION=([^ ]+)  # bump: github:([^ ]+) ([^ ]+)$'
commit_re='^([A-Z_]+)_COMMIT=([0-9a-f]+)  # bump: git:([^ ]+)$'

tmp="$(mktemp)"
dl="$(mktemp)"
trap 'rm -f "$tmp" "$dl"' EXIT

pending_sha=""
while IFS= read -r line; do
  if [ -n "$pending_sha" ]; then
    [[ "$line" == "${pending_sha%%=*}="* ]] || { echo "bump-binaries: expected ${pending_sha%%=*}= after its version" >&2; exit 1; }
    line="$pending_sha"
    pending_sha=""
  elif [[ "$line" =~ $ver_re ]]; then
    name="${BASH_REMATCH[1]}" cur="${BASH_REMATCH[2]}" repo="${BASH_REMATCH[3]}" asset="${BASH_REMATCH[4]}"
    tag="$(gh api "repos/$repo/releases/latest" --jq .tag_name)"
    new="${tag#v}"
    if [ "$new" != "$cur" ]; then
      curl -fsSL -o "$dl" "https://github.com/$repo/releases/download/$tag/$asset"
      line="${line/"_VERSION=$cur "/"_VERSION=$new "}"
      pending_sha="${name}_SHA256=$(sha256sum "$dl" | cut -d' ' -f1)"
      echo "$repo: $cur -> $new"
    fi
  elif [[ "$line" =~ $commit_re ]]; then
    cur="${BASH_REMATCH[2]}" repo="${BASH_REMATCH[3]}"
    new="$(gh api "repos/$repo/commits/HEAD" --jq .sha)"
    if [ "$new" != "$cur" ]; then
      line="${line/"_COMMIT=$cur "/"_COMMIT=$new "}"
      echo "$repo: ${cur:0:12} -> ${new:0:12}"
    fi
  fi
  printf '%s\n' "$line" >>"$tmp"
done <"$file"

cat "$tmp" >"$file"
