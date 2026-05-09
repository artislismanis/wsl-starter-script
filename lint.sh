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

# Lint `.sh` files plus `.tmpl` files that are shell scripts (e.g.
# claude/statusline.sh.tmpl) plus any tracked extensionless file with a
# bash/sh shebang (covers .githooks/pre-commit and
# modules/files/wsl-port-check). Detecting by shebang means new shell helpers
# without `.sh` get linted automatically. We accept flags after the shell name
# (`#!/bin/bash -e`) so a maintainer adding such a script doesn't silently
# skip lint.
_is_shell_shebang() {
  case "$1" in
    "#!/usr/bin/env bash"*|"#!/bin/bash"*|"#!/usr/bin/env sh"*|"#!/bin/sh"*) return 0 ;;
  esac
  return 1
}
FILTERED=()
for f in "${TARGETS[@]}"; do
  [ -f "$f" ] || continue
  case "$f" in
    *.sh) FILTERED+=("$f"); continue ;;
    *.sh.tmpl) FILTERED+=("$f"); continue ;;
  esac
  case "$f" in
    *.tmpl)
      # .tmpl files without a `.sh.` middle segment may still be shell —
      # only lint when the shebang says so.
      read -r shebang <"$f" 2>/dev/null || continue
      _is_shell_shebang "$shebang" && FILTERED+=("$f")
      continue ;;
  esac
  base="${f##*/}"
  case "$base" in *.*) continue ;; esac   # basename has another extension
  read -r shebang <"$f" 2>/dev/null || continue
  _is_shell_shebang "$shebang" && FILTERED+=("$f")
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

  # -S warning matches the PostToolUse hook in .claude/settings.json: info-level
  # findings (notably SC1091 "not following" on dynamic-path source statements,
  # which fires for every module's `source $(dirname "${BASH_SOURCE[0]}")/...`
  # line) aren't actionable here and would otherwise make every commit fail
  # once shellcheck is installed.
  if [ "$HAVE_SHELLCHECK" = "1" ] && ! shellcheck -S warning -x "$f"; then
    fail=1
  fi
done

[ "$fail" = "0" ] && echo "lint: ok"
exit "$fail"
