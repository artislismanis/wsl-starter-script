#!/usr/bin/env bash
# lint.sh — bash -n + shellcheck across every shell file in the repo.
# Usage:  ./lint.sh [file ...]   (no args = lint everything tracked)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if [ "$#" -gt 0 ]; then
  TARGETS=("$@")
else
  mapfile -t TARGETS < <(git ls-files 2>/dev/null | sort -u)
fi

# Keep `.sh` files plus any tracked file whose basename has no extension and
# starts with a bash/sh shebang (covers .githooks/pre-commit and
# modules/files/wsl-port-check). Detecting by shebang means new shell helpers
# without `.sh` get linted automatically. The shebang match is deliberately
# exact (no `-S bash`, no flags after `bash`, no `#! /bin/bash` with a space):
# project convention is `#!/usr/bin/env bash`, and a stricter check rejects
# accidental shell scripts that aren't actually bash.
FILTERED=()
for f in "${TARGETS[@]}"; do
  [ -f "$f" ] || continue
  case "$f" in
    *.sh) FILTERED+=("$f"); continue ;;
  esac
  base="${f##*/}"
  case "$base" in *.*) continue ;; esac   # basename has another extension
  read -r shebang <"$f" 2>/dev/null || continue
  case "$shebang" in
    "#!/usr/bin/env bash"|"#!/bin/bash"|"#!/usr/bin/env sh"|"#!/bin/sh")
      FILTERED+=("$f") ;;
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
