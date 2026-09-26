#!/usr/bin/env bash
# REQUIRES_ROOT=0
# DESCRIPTION=mise (unified version manager) + optional runtimes + uv + CLI/cloud tools
# ROLLBACK=# Per runtime first (clean removal of toolchains): mise uninstall <node|python|ruby|java|go|deno|bun>
# ROLLBACK=# Per tool: mise uninstall <lazygit|zellij|fzf|yq|pre-commit|glow|github:abhinav/git-spice|terraform|databricks-cli|azure>
# ROLLBACK=# azure-devops az extension (leave the rest of ~/.azure: it holds az login state):
# ROLLBACK=rm -rf "$HOME/.azure/cliextensions/azure-devops"
# ROLLBACK=# delta git wiring (only unset if still pointing at delta; we never overwrite an existing pager):
# ROLLBACK=[ "$(git config --global --get core.pager)" = delta ] && git config --global --unset core.pager
# ROLLBACK=[ "$(git config --global --get interactive.diffFilter)" = "delta --color-only" ] && git config --global --unset interactive.diffFilter
# ROLLBACK=sed -i '/# >>> wsl-starter:git-spice >>>/,/# <<< wsl-starter:git-spice <<</d' "$HOME/.bashrc" "$HOME/.zshrc" 2>/dev/null || true
# ROLLBACK=sed -i '/# >>> wsl-starter:fzf >>>/,/# <<< wsl-starter:fzf <<</d' "$HOME/.bashrc" "$HOME/.zshrc" 2>/dev/null || true
# ROLLBACK=rm -rf "$HOME/.local/bin/mise" "$HOME/.local/share/mise" "$HOME/.config/mise"
# ROLLBACK=# uv (if installed): we pass UV_NO_MODIFY_PATH=1 to its installer so all rc
# ROLLBACK=#   wiring stays inside our wsl-starter:mise block — no separate rc-strip needed.
# ROLLBACK=rm -rf "$HOME/.local/bin/uv" "$HOME/.local/bin/uvx" "$HOME/.local/share/uv" "$HOME/.local/bin/env"
# ROLLBACK=# Marker-specific rc-block strip (so single-module --rollback is complete; the
# ROLLBACK=#   cross-cutting tail at the end of the all-modules form covers it too).
# ROLLBACK=sed -i '/# >>> wsl-starter:mise >>>/,/# <<< wsl-starter:mise <<</d' "$HOME/.bashrc" "$HOME/.zshrc" 2>/dev/null || true
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_user

# Validate MISE_<LANG>_VERSION env values up front — they get interpolated
# into `mise use -g node@<value>` shell strings, so a value containing
# whitespace or shell metachars would split or inject. Allow alnum, dot,
# dash, underscore, plus. Runs before the mise install so bad env vars fail
# fast without first downloading a runtime manager that's about to be unused.
_ver_re='^[A-Za-z0-9._+-]+$'
for v in MISE_NODE_VERSION MISE_PYTHON_VERSION MISE_RUBY_VERSION MISE_JAVA_VERSION \
         MISE_GO_VERSION MISE_DENO_VERSION MISE_BUN_VERSION \
         MISE_TERRAFORM_VERSION MISE_DATABRICKS_VERSION MISE_AZURE_CLI_VERSION MISE_GIT_SPICE_VERSION; do
  if [ -n "${!v:-}" ] && ! [[ "${!v}" =~ $_ver_re ]]; then
    die "$v='${!v}' contains unsafe characters (allowed: alnum, dot, dash, underscore, plus)."
  fi
done

# Tools: MISE_TOOLS (comma-separated) overrides the prompts further down.
# Parsed here so a typo fails fast, same as the version checks above.
declare -A TOOL_SPECS=(
  [lazygit]="lazygit@latest"
  [zellij]="zellij@latest"
  [fzf]="fzf@latest"
  [yq]="yq@latest"
  [pre-commit]="pre-commit@latest"
  [glow]="glow@latest"
  [terraform]="terraform@${MISE_TERRAFORM_VERSION:-latest}"
  [databricks]="databricks-cli@${MISE_DATABRICKS_VERSION:-latest}"
  # uv venvs ship without pip, which `az extension add` shells out to. Setting
  # uvx_args replaces the registry's own --prerelease=allow, so repeat it.
  [azure-cli]="azure[uvx_args=--prerelease=allow --with=pip]@${MISE_AZURE_CLI_VERSION:-latest}"
  # Not in mise's own registry.
  [git-spice]="github:abhinav/git-spice@${MISE_GIT_SPICE_VERSION:-latest}"
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
  run "curl -fsSL https://mise.run | sh"
else
  skip "mise already installed"
fi

MISE_BIN="$HOME/.local/bin/mise"
[ -x "$MISE_BIN" ] || MISE_BIN="$(command -v mise || true)"
[ -n "$MISE_BIN" ] || die "mise installed but not on PATH; open a new shell and re-run."
# Fresh login shells only get ~/.local/bin on PATH if it existed at login; uv
# and mise's pipx backend (uvx, for azure-cli) must be findable from here on.
export PATH="$HOME/.local/bin:$PATH"

ensure_block_per_shell "wsl-starter:mise" "$HOME" \
  'export PATH="$HOME/.local/bin:$PATH"
command -v mise >/dev/null 2>&1 && eval "$("$HOME/.local/bin/mise" activate bash)"' \
  'export PATH="$HOME/.local/bin:$PATH"
command -v mise >/dev/null 2>&1 && eval "$("$HOME/.local/bin/mise" activate zsh)"'

# ---- Runtimes ---------------------------------------------------------------
# MISE_LANGUAGES env var overrides the prompts (comma-separated).
# Per-language version overrides via env: MISE_<LANG>_VERSION (e.g. MISE_NODE_VERSION=22).
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

# ---- Tools ------------------------------------------------------------------
# Runs after uv because azure-cli's only Linux backend in mise is pipx, which
# runs via uvx.
if [ -z "${MISE_TOOLS:-}" ]; then
  for t in lazygit zellij fzf yq pre-commit glow git-spice; do
    if confirm "Install ${t} (${TOOL_SPECS[$t]})?" y; then tools+=("$t"); fi
  done
  if confirm "Show cloud tools (terraform/databricks/azure-cli)?" n; then
    for t in terraform databricks azure-cli; do
      if confirm "Install ${t} (${TOOL_SPECS[$t]})?" n; then tools+=("$t"); fi
    done
  fi
fi

for t in "${tools[@]}"; do
  [ -z "$t" ] && continue
  if [ "$t" = azure-cli ] && [ "$DRY_RUN" != "1" ] && ! command_exists uv; then
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
    git-spice)
      # Upstream ships the binary as git-spice and recommends aliasing gs
      # rather than renaming it.
      ensure_block_in_rcs "wsl-starter:git-spice" "$HOME" 'alias gs=git-spice'
      ;;
  esac
done

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
