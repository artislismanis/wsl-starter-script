#!/usr/bin/env bash
# REQUIRES_ROOT=0
# DESCRIPTION=mise (unified version manager) + optional runtimes + uv + CLI/cloud tools
# ROLLBACK=# Per runtime first (clean removal of toolchains): mise uninstall <node|python|ruby|java|go|deno|bun>
# ROLLBACK=# Per tool: mise uninstall <uv|lazygit|zellij|fzf|yq|pre-commit|glow|terraform|databricks-cli|azure|poetry> (older installs also github:abhinav/git-spice)
# ROLLBACK=# azure-devops az extension (leave the rest of ~/.azure: it holds az login state):
# ROLLBACK=rm -rf "$HOME/.azure/cliextensions/azure-devops"
# ROLLBACK=# delta git wiring (only unset if still pointing at delta; we never overwrite an existing pager):
# ROLLBACK=[ "$(git config --global --get core.pager)" = delta ] && git config --global --unset core.pager
# ROLLBACK=[ "$(git config --global --get interactive.diffFilter)" = "delta --color-only" ] && git config --global --unset interactive.diffFilter
# ROLLBACK=# Older installs: git-spice's gs alias block.
# ROLLBACK=sed -i '/# >>> wsl-starter:git-spice >>>/,/# <<< wsl-starter:git-spice <<</d' "$HOME/.bashrc" "$HOME/.zshrc" 2>/dev/null || true
# ROLLBACK=sed -i '/# >>> wsl-starter:fzf >>>/,/# <<< wsl-starter:fzf <<</d' "$HOME/.bashrc" "$HOME/.zshrc" 2>/dev/null || true
# ROLLBACK=sed -i '/# >>> wsl-starter:pip >>>/,/# <<< wsl-starter:pip <<</d' "$HOME/.config/pip/pip.conf" 2>/dev/null || true
# ROLLBACK=rm -rf "$HOME/.local/bin/mise" "$HOME/.local/share/mise" "$HOME/.config/mise"
# ROLLBACK=# uv from Astral's installer (installs before uv moved to mise): we passed
# ROLLBACK=#   UV_NO_MODIFY_PATH=1 so all rc wiring stays inside our wsl-starter:mise block.
# ROLLBACK=rm -rf "$HOME/.local/bin/uv" "$HOME/.local/bin/uvx" "$HOME/.local/share/uv" "$HOME/.local/bin/env"
# ROLLBACK=# Marker-specific rc-block strip (so single-module --rollback is complete; the
# ROLLBACK=#   cross-cutting tail at the end of the all-modules form covers it too).
# ROLLBACK=sed -i '/# >>> wsl-starter:mise >>>/,/# <<< wsl-starter:mise <<</d' "$HOME/.bashrc" "$HOME/.zshrc" 2>/dev/null || true
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_user

# Validate MISE_<NAME>_VERSION env values up front — they get interpolated
# into `mise use -g node@<value>` shell strings, so a value containing
# whitespace or shell metachars would split or inject. Allow alnum, dot,
# dash, underscore, plus. Runs before the mise install so bad env vars fail
# fast without first downloading a runtime manager that's about to be unused.
_ver_re='^[A-Za-z0-9._+-]+$'
while IFS= read -r v; do
  if [ -n "${!v}" ] && ! [[ "${!v}" =~ $_ver_re ]]; then
    die "$v='${!v}' contains unsafe characters (allowed: alnum, dot, dash, underscore, plus)."
  fi
done < <(compgen -v | grep -E '^MISE_[A-Z_]+_VERSION$' || true)

# Every default below is an exact, reviewed version. .github/workflows/bump-pins.yml
# opens a PR when upstream moves; a trailing `# bump: <spec>` makes it follow
# `mise latest <spec>` (e.g. stay on python 3.12) instead of the tool's latest.

# Tools: MISE_TOOLS (comma-separated) overrides the prompts further down.
# Parsed here so a typo fails fast, same as the version checks above.
declare -A TOOL_SPECS=(
  [lazygit]="lazygit@${MISE_LAZYGIT_VERSION:-0.66.2}"
  [zellij]="zellij@${MISE_ZELLIJ_VERSION:-0.45.1}"
  [fzf]="fzf@${MISE_FZF_VERSION:-0.74.5}"
  [yq]="yq@${MISE_YQ_VERSION:-4.54.1}"
  [pre-commit]="pre-commit@${MISE_PRE_COMMIT_VERSION:-4.7.0}"
  [glow]="glow@${MISE_GLOW_VERSION:-3.0.0}"
  [terraform]="terraform@${MISE_TERRAFORM_VERSION:-1.16.6}"
  [databricks]="databricks-cli@${MISE_DATABRICKS_VERSION:-1.21.0}"
  # uv venvs ship without pip, which `az extension add` shells out to. Setting
  # uvx_args replaces the registry's own --prerelease=allow, so repeat it.
  [azure-cli]="azure[uvx_args=--prerelease=allow --with=pip]@${MISE_AZURE_CLI_VERSION:-2.91.0}"
  [poetry]="poetry@${MISE_POETRY_VERSION:-2.5.1}"
)
tools=()
if [ -n "${MISE_TOOLS:-}" ]; then
  IFS=',' read -r -a tools <<<"$MISE_TOOLS"
  unknown=()
  for t in "${tools[@]}"; do
    if [ -n "$t" ] && [ -z "${TOOL_SPECS[$t]:-}" ]; then unknown+=("$t"); fi
  done
  [ ${#unknown[@]} -gt 0 ] && die "MISE_TOOLS contains unknown tool(s): ${unknown[*]}. Valid: ${!TOOL_SPECS[*]}"
fi

if ! command_exists mise; then
  log "Installing mise"
  run "curl -fsSL https://mise.run | MISE_VERSION=v${MISE_SELF_VERSION:-2026.10.14} sh"  # bump: aqua:jdx/mise
else
  skip "mise already installed"
fi

MISE_BIN="$HOME/.local/bin/mise"
[ -x "$MISE_BIN" ] || MISE_BIN="$(command -v mise || true)"
[ -n "$MISE_BIN" ] || die "mise installed but not on PATH; open a new shell and re-run."
# Fresh login shells only get ~/.local/bin on PATH if it existed at login; uv
# and mise's pipx backend (uvx, for azure-cli) must be findable from here on.
export PATH="$HOME/.local/bin:$PATH"

# mise only records checksums for global tools when this file exists.
write_file_once "$HOME/.config/mise/mise.lock" </dev/null

ensure_block_per_shell "wsl-starter:mise" "$HOME" \
  'export PATH="$HOME/.local/bin:$PATH"
command -v mise >/dev/null 2>&1 && eval "$("$HOME/.local/bin/mise" activate bash)"' \
  'export PATH="$HOME/.local/bin:$PATH"
command -v mise >/dev/null 2>&1 && eval "$("$HOME/.local/bin/mise" activate zsh)"'

# ---- Runtimes ---------------------------------------------------------------
# MISE_LANGUAGES env var overrides the prompts (comma-separated).
# Per-language version overrides via env: MISE_<LANG>_VERSION (e.g. MISE_NODE_VERSION=22).
declare -A SPECS=(
  [node]="node@${MISE_NODE_VERSION:-24.22.0}"  # bump: node@lts
  [python]="python@${MISE_PYTHON_VERSION:-3.12.15}"  # bump: python@3.12
  [ruby]="ruby@${MISE_RUBY_VERSION:-3.3.12}"  # bump: ruby@3.3
  [java]="java@${MISE_JAVA_VERSION:-temurin-21.0.12+101.0.LTS}"  # bump: java@temurin-21
  [go]="go@${MISE_GO_VERSION:-1.27.2}"
  [deno]="deno@${MISE_DENO_VERSION:-2.9.7}"
  [bun]="bun@${MISE_BUN_VERSION:-1.4.3}"
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
# No venv activation on cd: commands go through `uv run`, which always picks
# the project's own .venv (an activated one goes stale across worktrees).
UV_SPEC="uv@${MISE_UV_VERSION:-0.13.1}"
if confirm "Install uv (fast Python project/env manager, ${UV_SPEC})?" y; then
  log "mise use -g $UV_SPEC"
  run "\"$MISE_BIN\" use -g $UV_SPEC"
fi

# ---- Tools ------------------------------------------------------------------
# Runs after uv because azure-cli's only Linux backend in mise is pipx, which
# runs via uvx.
if [ -z "${MISE_TOOLS:-}" ]; then
  for t in lazygit zellij fzf yq pre-commit glow; do
    if confirm "Install ${t} (${TOOL_SPECS[$t]})?" y; then tools+=("$t"); fi
  done
  if confirm "Show extra tools (terraform/databricks/azure-cli/poetry)?" n; then
    for t in terraform databricks azure-cli poetry; do
      if confirm "Install ${t} (${TOOL_SPECS[$t]})?" n; then tools+=("$t"); fi
    done
  fi
fi

for t in "${tools[@]}"; do
  [ -z "$t" ] && continue
  if [ "$t" = azure-cli ] && [ "$DRY_RUN" != "1" ] && ! "$MISE_BIN" which uv >/dev/null 2>&1 && ! command_exists uv; then
    warn "azure-cli needs uv (mise installs it via uvx); skipping. Install uv and re-run."
    continue
  fi
  log "mise use -g ${TOOL_SPECS[$t]}"
  run "\"$MISE_BIN\" use -g '${TOOL_SPECS[$t]}'"

  case "$t" in
    azure-cli)
      # MISE_EXEC_AUTO_INSTALL=false so this probe never installs anything
      # itself (it would under --dry-run, where the `use -g` above didn't run).
      if MISE_EXEC_AUTO_INSTALL=false "$MISE_BIN" exec -- az extension show --name azure-devops >/dev/null 2>&1; then
        skip "az extension azure-devops already installed"
      else
        run "\"$MISE_BIN\" exec -- az extension add --name azure-devops --only-show-errors"
      fi
      ;;
    fzf)
      # Empty FZF_CTRL_R_COMMAND stops fzf binding Ctrl-R, which atuin owns.
      ensure_block_per_shell "wsl-starter:fzf" "$HOME" \
        'command -v atuin >/dev/null 2>&1 && FZF_CTRL_R_COMMAND=
command -v fzf >/dev/null 2>&1 && eval "$(fzf --bash)"' \
        'command -v atuin >/dev/null 2>&1 && FZF_CTRL_R_COMMAND=
command -v fzf >/dev/null 2>&1 && eval "$(fzf --zsh)"'
      ;;
  esac
done

# ---- pip guard ----------------------------------------------------------------
# Nothing activates venvs (commands go through uv run / poetry run), so a bare
# `pip install` would land in mise's global Python. Refuse outside a venv.
run "mkdir -p '$HOME/.config/pip'"
replace_ini_section "wsl-starter:pip" "$HOME/.config/pip/pip.conf" global "[global]
require-virtualenv = true"

# ---- delta git wiring -------------------------------------------------------
# delta comes from apt (20-cli-modern), not mise: git runs it from processes
# that never ran `mise activate` (wsl -- git, IDEs). Dry-run assumes 20 ran.
if [ "$DRY_RUN" = "1" ] || command_exists delta; then
  # Only fill unset keys so an operator's own pager setup wins.
  for kv in "core.pager=delta" "interactive.diffFilter=delta --color-only"; do
    key="${kv%%=*}" val="${kv#*=}"
    if [ -n "$(git config --global --get "$key" || true)" ]; then
      skip "git $key already set"
    else
      run "git config --global $key '$val'"
    fi
  done
fi

ok "mise configured. Open a new shell so 'mise activate' is in effect."
