#!/usr/bin/env bash
# REQUIRES_ROOT=0
# DESCRIPTION=mise (unified version manager) + optional runtimes + uv
# ROLLBACK=# Per runtime first (clean removal of toolchains): mise uninstall <node|python|ruby|java|go|deno|bun>
# ROLLBACK=rm -rf "$HOME/.local/bin/mise" "$HOME/.local/share/mise" "$HOME/.config/mise"
# ROLLBACK=# uv (if installed): we pass UV_NO_MODIFY_PATH=1 to its installer so all rc
# ROLLBACK=#   wiring stays inside our wsl-starter:mise block — no separate rc-strip needed.
# ROLLBACK=rm -rf "$HOME/.local/bin/uv" "$HOME/.local/bin/uvx" "$HOME/.local/share/uv" "$HOME/.local/bin/env"
# ROLLBACK=# rc-block (wsl-starter:mise) is removed by the cross-cutting rc strip below.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_user

if ! command_exists mise; then
  log "Installing mise"
  run "curl -fsSL https://mise.run | sh"
else
  skip "mise already installed"
fi

MISE_BIN="$HOME/.local/bin/mise"
[ -x "$MISE_BIN" ] || MISE_BIN="$(command -v mise || true)"
[ -n "$MISE_BIN" ] || die "mise installed but not on PATH; open a new shell and re-run."

ensure_block_per_shell "wsl-starter:mise" "$HOME" \
  'export PATH="$HOME/.local/bin:$PATH"
command -v mise >/dev/null 2>&1 && eval "$("$HOME/.local/bin/mise" activate bash)"' \
  'export PATH="$HOME/.local/bin:$PATH"
command -v mise >/dev/null 2>&1 && eval "$("$HOME/.local/bin/mise" activate zsh)"'

# ---- Runtimes ---------------------------------------------------------------
# MISE_LANGUAGES env var overrides the prompts (comma-separated).
# Per-language version overrides via env: MISE_<LANG>_VERSION (e.g. MISE_NODE_VERSION=22).
# Validate version values up front — they get interpolated into `mise use -g
# node@<value>` shell strings, so a value containing whitespace or shell
# metachars would split or inject. Allow alnum, dot, dash, underscore, plus.
_ver_re='^[A-Za-z0-9._+-]+$'
for v in MISE_NODE_VERSION MISE_PYTHON_VERSION MISE_RUBY_VERSION MISE_JAVA_VERSION \
         MISE_GO_VERSION MISE_DENO_VERSION MISE_BUN_VERSION; do
  if [ -n "${!v:-}" ] && ! [[ "${!v}" =~ $_ver_re ]]; then
    die "$v='${!v}' contains unsafe characters (allowed: alnum, dot, dash, underscore, plus)."
  fi
done
declare -A SPECS=(
  [node]="node@${MISE_NODE_VERSION:-lts}"
  [python]="python@${MISE_PYTHON_VERSION:-3.12}"
  [ruby]="ruby@${MISE_RUBY_VERSION:-3.3}"
  [java]="java@${MISE_JAVA_VERSION:-temurin-21}"
  [go]="go@${MISE_GO_VERSION:-latest}"
  [deno]="deno@${MISE_DENO_VERSION:-latest}"
  [bun]="bun@${MISE_BUN_VERSION:-latest}"
)

if [ -n "${MISE_LANGUAGES:-}" ]; then
  IFS=',' read -r -a choices <<<"$MISE_LANGUAGES"
  # Surface typos in MISE_LANGUAGES at parse time, not silently in the install
  # loop below. Each entry must map to a known SPECS key.
  unknown=()
  for lang in "${choices[@]}"; do
    [ -n "$lang" ] && [ -z "${SPECS[$lang]:-}" ] && unknown+=("$lang")
  done
  [ ${#unknown[@]} -gt 0 ] && die "MISE_LANGUAGES contains unknown runtime(s): ${unknown[*]}. Valid: ${!SPECS[*]}"
else
  choices=()
  # Default prompts: only node + python. Everything else is an "advanced" opt-in.
  for lang in node python; do
    confirm "Install ${lang} (${SPECS[$lang]})?" y && choices+=("$lang")
  done
  if confirm "Show other runtimes (ruby/java/go/deno/bun)?" n; then
    for lang in ruby java go deno bun; do
      confirm "Install ${lang} (${SPECS[$lang]})?" n && choices+=("$lang")
    done
  fi
fi

for lang in "${choices[@]}"; do
  spec="${SPECS[$lang]:-}"
  [ -z "$spec" ] && { warn "Unknown language: $lang"; continue; }
  log "mise use -g $spec"
  run "\"$MISE_BIN\" use -g $spec"
done

# uv — project-local Python env manager (complements mise-managed python).
# UV_NO_MODIFY_PATH=1 stops Astral's installer from appending its own
# `. "$HOME/.local/bin/env"` line to ~/.bashrc / ~/.zshrc — the wsl-starter:mise
# block above already adds ~/.local/bin to PATH, so the second wiring would be
# redundant noise that lives outside our fence and survives a --rollback.
if confirm "Install uv (fast Python project/env manager)?" y; then
  if ! command_exists uv; then
    run "curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh"
  else
    skip "uv already installed"
  fi
fi

ok "mise configured. Open a new shell so 'mise activate' is in effect."
