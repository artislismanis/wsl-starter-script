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

[ "${#TARGETS[@]}" -gt 0 ] || { echo "no shell files to lint"; exit 0; }

fail=0

for f in "${TARGETS[@]}"; do
  [ -f "$f" ] || continue
  case "$f" in
    *.sh|install.sh|bootstrap.sh|.githooks/pre-commit) ;;
    *) continue ;;
  esac

  if LC_ALL=C grep -q $'\r' "$f"; then
    echo "  CRLF: $f"
    fail=1
  fi

  if ! bash -n "$f" 2>/tmp/lint.err; then
    echo "  syntax: $f"
    sed 's/^/    /' /tmp/lint.err
    fail=1
  fi
done

if command -v shellcheck >/dev/null 2>&1; then
  for f in "${TARGETS[@]}"; do
    [ -f "$f" ] || continue
    case "$f" in
      *.sh|install.sh|bootstrap.sh|.githooks/pre-commit) ;;
      *) continue ;;
    esac
    if ! shellcheck -x "$f"; then fail=1; fi
  done
else
  echo "(shellcheck not installed — skipping; \`apt install shellcheck\` to enable)"
fi

[ "$fail" = "0" ] && echo "lint: ok"
exit "$fail"
