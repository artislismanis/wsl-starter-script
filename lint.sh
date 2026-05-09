#!/usr/bin/env bash
# lint.sh — bash -n + shellcheck across every shell file in the repo.
# Usage:  ./lint.sh [file ...]   (no args = lint everything tracked)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if [ "$#" -gt 0 ]; then
  TARGETS=("$@")
else
  mapfile -t TARGETS < <(git ls-files '*.sh' 'install.sh' 'bootstrap.sh' 'lib/*.sh' 'modules/*.sh' '.githooks/*' 2>/dev/null | sort -u)
fi

# Filter once: keep only existing shell files we care about.
FILTERED=()
for f in "${TARGETS[@]}"; do
  [ -f "$f" ] || continue
  case "$f" in
    *.sh|install.sh|bootstrap.sh|.githooks/pre-commit) FILTERED+=("$f") ;;
  esac
done

[ "${#FILTERED[@]}" -gt 0 ] || { echo "no shell files to lint"; exit 0; }

HAVE_SHELLCHECK=0
command -v shellcheck >/dev/null 2>&1 && HAVE_SHELLCHECK=1
[ "$HAVE_SHELLCHECK" = "0" ] && echo "(shellcheck not installed — skipping; \`apt install shellcheck\` to enable)"

fail=0

for f in "${FILTERED[@]}"; do
  if LC_ALL=C grep -q $'\r' "$f"; then
    echo "  CRLF: $f"
    fail=1
  fi

  if ! bash -n "$f" 2>/tmp/lint.err; then
    echo "  syntax: $f"
    sed 's/^/    /' /tmp/lint.err
    fail=1
  fi

  if [ "$HAVE_SHELLCHECK" = "1" ] && ! shellcheck -x "$f"; then
    fail=1
  fi
done

[ "$fail" = "0" ] && echo "lint: ok"
exit "$fail"
