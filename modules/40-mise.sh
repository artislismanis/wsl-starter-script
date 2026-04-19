#!/usr/bin/env bash
# REQUIRES_ROOT=0
# DESCRIPTION=mise (unified version manager) + optional runtimes + uv
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

ensure_block "wsl-starter:mise" "$HOME/.bashrc" 'export PATH="$HOME/.local/bin:$PATH"
command -v mise >/dev/null 2>&1 && eval "$("$HOME/.local/bin/mise" activate bash)"'
[ -f "$HOME/.zshrc" ] && ensure_block "wsl-starter:mise" "$HOME/.zshrc" 'export PATH="$HOME/.local/bin:$PATH"
command -v mise >/dev/null 2>&1 && eval "$("$HOME/.local/bin/mise" activate zsh)"'

# ---- Runtimes ---------------------------------------------------------------
# MISE_LANGUAGES env var overrides the prompts (comma-separated).
declare -A SPECS=(
  [node]="node@lts"
  [python]="python@3.12"
  [ruby]="ruby@3.3"
  [java]="java@temurin-21"
  [go]="go@latest"
  [deno]="deno@latest"
  [bun]="bun@latest"
)

if [ -n "${MISE_LANGUAGES:-}" ]; then
  IFS=',' read -r -a choices <<<"$MISE_LANGUAGES"
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

for lang in "${choices[@]:-}"; do
  [ -z "$lang" ] && continue
  spec="${SPECS[$lang]:-}"
  [ -z "$spec" ] && { warn "Unknown language: $lang"; continue; }
  log "mise use -g $spec"
  run "\"$MISE_BIN\" use -g $spec"
done

# uv — project-local Python env manager (complements mise-managed python).
if confirm "Install uv (fast Python project/env manager)?" y; then
  if ! command_exists uv; then
    run "curl -LsSf https://astral.sh/uv/install.sh | sh"
  else
    skip "uv already installed"
  fi
fi

ok "mise configured. Open a new shell so 'mise activate' is in effect."
