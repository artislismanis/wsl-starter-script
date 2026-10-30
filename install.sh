#!/usr/bin/env bash
# wsl-starter-script — modular WSL bootstrap.
# Usage: ./install.sh [--preset NAME|--base|--dev|--claude|--tailscale|--workbench|--logins|--module NAME] [--non-interactive] [--dry-run]
set -euo pipefail

# lib/common.sh re-derives + exports REPO_ROOT itself; we set it here so the
# source line below works without recomputing the path.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REPO_ROOT/lib/common.sh"
source "$REPO_ROOT/lib/idempotent.sh"

MODULES_DIR="$REPO_ROOT/modules"

usage() {
  cat <<USAGE
wsl-starter-script

  ./install.sh                       Interactive menu.
  ./install.sh --base                Root-phase only: 00-wsl-base + 10-apt-core.
  ./install.sh --dev                 cli-modern (root, auto-escalates) + zsh + history + mise.
                                     If invoked as root the user-phase is deferred to the
                                     post-handoff/reopen user run.
  ./install.sh --docker              Docker Engine.
  ./install.sh --podman              Podman (rootless, daemonless).
  ./install.sh --claude              Claude Code CLI + user-global config.
  ./install.sh --tailscale           Tailscale (private network for SSH and phone access).
  ./install.sh --workflow            worktrunk + hunk (pinned binaries) + gh-stack.
  ./install.sh --herdr               herdr (pinned binary).
  ./install.sh --workbench           herdr-workbench config, plus any tools above it needs.
  ./install.sh --preset NAME         Saved selection: wsl, dev, ai, full.
  ./install.sh --print-plan          With any of the above: show the plan, change nothing.
  ./install.sh --logins              Log in to the installed tools and set git identity. Re-runnable.
  ./install.sh --module NAME         Run one module (e.g. 20-cli-modern).
  ./install.sh --list                List available modules.
  ./install.sh --rollback [NAME]     Print rollback recipe (one module, or all in
                                     reverse install order). Output is shell-pasteable;
                                     review before running. Source-of-truth lives in
                                     each module's '# ROLLBACK=' headers.

Flags:
  --non-interactive   Read answers from env vars. Common ones:
                      WSL_USER, WSL_PASSWORD, WSL_HOSTNAME, WSL_DNS, WSL_APT_UPGRADE,
                      MISE_LANGUAGES (csv), MISE_<LANG>_VERSION,
                      MISE_TOOLS (csv), MISE_<TOOL>_VERSION,
                      DOCKER_MODE, DOCKER_USER,
                      PODMAN_COMPOSE, PODMAN_DOCKER_SHIM,
                      ZSH_THEME, ZSH_PLUGINS, CLAUDE_PERMISSION_MODE, CLAUDE_MY_CLAUDE.
                      Full list and defaults in docs/reference/env-vars.md.
  --dry-run           Print what would happen, make no changes.
  -h, --help          This message.

Note: presets don't include Podman; it's the alternative to Docker, so pass --podman
explicitly. See docs/explanation/tool-groups.md.
USAGE
}

list_modules() {
  for f in "$MODULES_DIR"/*.sh; do
    name="$(basename "$f" .sh)"
    desc="$(grep -m1 '^# DESCRIPTION=' "$f" | cut -d= -f2- || true)"
    root="$(grep -m1 '^# REQUIRES_ROOT=' "$f" | cut -d= -f2 || echo 0)"
    tag="[user]"; [ "$root" = "1" ] && tag="[root]"
    printf "  %-18s %s %s\n" "$name" "$tag" "$desc"
  done
}

module_requires_root() {
  grep -q '^# REQUIRES_ROOT=1' "$MODULES_DIR/$1.sh"
}

# print_rollback [module-name]
#   Read each module's '# ROLLBACK=<line>' headers and print them verbatim,
#   wrapped with a module separator. With no arg, walk every module in reverse
#   install order (so user-phase + container modules unwind before the base
#   distro setup). Output is shell-pasteable but never executed: rolling back
#   a system mutation is the operator's call, not the dispatcher's.
print_rollback() {
  local target="${1:-}"
  local files=()
  if [ -n "$target" ]; then
    local f="$MODULES_DIR/$target.sh"
    [ -f "$f" ] || die "Unknown module: $target (see --list)"
    files=("$f")
  else
    # Reverse install order: walk numeric prefixes from highest to lowest so
    # 99-cleanup → 50-claude → 40-mise → ... → 00-wsl-base.
    while IFS= read -r f; do files+=("$f"); done < <(printf '%s\n' "$MODULES_DIR"/*.sh | sort -r)
  fi
  cat <<'PREAMBLE'
#!/usr/bin/env bash
# wsl-starter-script rollback recipe — review before running.
# Each module section lists what to undo for that module's writes.
# Lines beginning with `#` are comments; everything else is shell-executable.
PREAMBLE
  local f base
  for f in "${files[@]}"; do
    base="$(basename "$f")"
    printf '\n# ===== %s =====\n' "$base"
    # cut -d= -f2- preserves any '=' inside the value.
    grep '^# ROLLBACK=' "$f" | cut -d= -f2- || true
  done
  if [ -z "$target" ]; then
    cat <<'FOOTER'

# ===== Cross-cutting (run once at the end) =====
# Strip every wsl-starter:* fenced block from the operator's rc files.
sed -i '/# >>> wsl-starter:/,/# <<< wsl-starter:/d' "$HOME/.bashrc" "$HOME/.zshrc" 2>/dev/null || true
# Module ROLLBACK comments above list packages by name but do NOT emit
# 'apt-get remove' lines (deciding what to keep is the operator's call —
# e.g. you may want to keep podman after uninstalling docker). Pick what to
# remove from those lists, run 'sudo apt-get remove <packages>', then:
sudo apt-get autoremove -y || true
# Per-session marker files self-clear on tmpfs (no action needed):
#   /run/wsl-starter-handoff /run/wsl-starter.container-runtime /run/wsl-starter.apt-fresh
# Final step: from Windows PowerShell so WSL re-reads /etc/wsl.conf:
#   wsl --shutdown
FOOTER
  fi
}

# Sweep WSL_*/DOCKER_*/PODMAN_*/MISE_*/CLAUDE_*/ZSH_* env vars (plus
# NON_INTERACTIVE/DRY_RUN) into FORWARD_ASSIGNS for sudo handoffs. Blocklist
# covers SDK/system vars that share a prefix but would corrupt behaviour or
# leak secrets. WSL_DISTRO_NAME is intentionally NOT blocked — it's needed for
# operator-facing "wsl --terminate <distro>" banners after the env scrub.
_collect_forward_assigns() {
  local always=(NON_INTERACTIVE DRY_RUN)
  local prefix_re='^(WSL|DOCKER|PODMAN|MISE|CLAUDE|ZSH)_'
  local block_re='^(WSL_INTEROP|WSL_STARTER_.*|DOCKER_(HOST|CONFIG|CONTEXT|TLS_.*|CERT_PATH)|CLAUDE_CODE_.*)$'
  local v
  FORWARD_ASSIGNS=()
  # `if` rather than `&&` so a never-set var (no FORWARD_ASSIGNS append) doesn't
  # return 1 from the final statement of the loop body — set -e + && footgun.
  # Today protected by upstream invariants (compgen -v only emits set names;
  # ${always[@]} entries are :- defaulted in common.sh) but defensive anyway.
  for v in "${always[@]}"; do
    if [ -n "${!v+set}" ]; then
      FORWARD_ASSIGNS+=("$v=$(printf '%q' "${!v}")")
    fi
  done
  while IFS= read -r v; do
    [[ "$v" =~ $prefix_re ]] || continue
    [[ "$v" =~ $block_re ]] && continue
    if [ -n "${!v+set}" ]; then
      FORWARD_ASSIGNS+=("$v=$(printf '%q' "${!v}")")
    fi
  done < <(compgen -v)
}

# _sudo_with_forwards <bash-args...> — argv-style sudo+env+bash.
# The post-handoff path at the bottom of this file builds a single bash -lc
# string instead and uses ${...[*]} (FORWARD_ASSIGNS entries are %q-quoted, so
# the IFS-space join is shell-safe). Keep both patterns aligned.
_sudo_with_forwards() {
  _collect_forward_assigns
  sudo env "${FORWARD_ASSIGNS[@]}" bash "$@"
}

declare -A RAN_MODULES=()
run_module() {
  local name="$1" path="$MODULES_DIR/$1.sh"
  [ -f "$path" ] || die "Unknown module: $name"
  if [ -n "${RAN_MODULES[$name]:-}" ]; then
    skip "module '$name' already ran in this invocation"
    return 0
  fi
  RAN_MODULES[$name]=1
  printf "\n${C_BLUE}━━ %s ━━${C_RESET}\n" "$name"
  if module_requires_root "$name"; then
    if is_root; then
      bash "$path"
    else
      log "Module '$name' requires root — escalating via sudo."
      _sudo_with_forwards "$path"
    fi
  else
    if is_root; then
      die "Module '$name' must run as your non-root user, not sudo."
    fi
    bash "$path"
  fi
}

BASE_MODULES=(00-wsl-base)
CORE_MODULES=(10-apt-core)
DEV_ROOT_MODULES=(20-cli-modern)
DEV_USER_MODULES=(30-shell-zsh 31-shell-history 40-mise)
DOCKER_MODULES=(25-docker-engine)
PODMAN_MODULES=(26-podman)
CLAUDE_MODULES=(50-claude-code)
TAILSCALE_MODULES=(28-tailscale)
WORKFLOW_MODULES=(52-workflow-tools)
HERDR_MODULES=(54-herdr)
WORKBENCH_MODULES=(55-workbench)
LOGINS_MODULES=(60-logins)
# 27-wsl-network is fired once at the bottom of the script (see the gate after
# the case block) when a container-runtime module ran AND actually installed.
# Combining --docker --podman in one invocation runs it once via RAN_MODULES.

# ----- plan -------------------------------------------------------------------
# Every group flag, preset and the guided list become one SELECTED list. Install
# order comes from GROUP_ORDER. What a group pulls in comes from its modules'
# NEEDS / PROVIDES headers: commands, so a tool that's already there adds nothing.
# See docs/explanation/tool-groups.md.
GROUP_ORDER=(base core dev stack workflow docker podman tailscale claude herdr workbench logins cleanup)
declare -A GROUP_MODULES=(
  [base]="${BASE_MODULES[*]}"
  [core]="${CORE_MODULES[*]}"
  [dev]="${DEV_ROOT_MODULES[*]} ${DEV_USER_MODULES[*]}"
  [docker]="${DOCKER_MODULES[*]}"
  [podman]="${PODMAN_MODULES[*]}"
  [tailscale]="${TAILSCALE_MODULES[*]}"
  [workflow]="${WORKFLOW_MODULES[*]}"
  [claude]="${CLAUDE_MODULES[*]}"
  [herdr]="${HERDR_MODULES[*]}"
  [workbench]="${WORKBENCH_MODULES[*]}"
  [logins]="${LOGINS_MODULES[*]}"
)
declare -A GROUP_LABELS=(
  [base]="WSL base (systemd, user, hostname, DNS)"
  [core]="Core apt packages"
  [dev]="Terminal and basic dev (zsh, CLI tools, gh, mise, languages)"
  [stack]="Stack-specific tools (terraform, azure-cli, databricks, poetry)"
  [workflow]="Workflow tools (worktrunk, hunk, gh-stack)"
  [docker]="Docker Engine (rootful; one distro per WSL VM)"
  [podman]="Podman (rootless, daemonless)"
  [tailscale]="Tailscale (one distro per WSL VM)"
  [claude]="Claude Code"
  [herdr]="herdr"
  [workbench]="herdr-workbench config"
  [logins]="Logins and git identity"
)
declare -A PRESETS=(
  [wsl]="base core"
  [dev]="base core dev logins"
  [ai]="base core dev workflow claude herdr workbench logins"
  [full]="base core dev stack workflow docker tailscale claude herdr workbench logins"
)
STACK_TOOLS=lazygit,yq,pre-commit,glow,terraform,databricks,azure-cli,poetry
PLAN_NOTES=()

_selected() {
  local g
  for g in "${SELECTED[@]}"; do
    if [ "$g" = "$1" ]; then return 0; fi
  done
  return 1
}

_module_header() { sed -n "s/^# $2=//p" "$MODULES_DIR/$1.sh" | head -1; }

# ~/.local/bin isn't on PATH in every shell this runs from.
_have() { command -v "$1" >/dev/null 2>&1 || [ -x "$HOME/.local/bin/$1" ]; }

_group_providing() {
  local g m
  for g in "${GROUP_ORDER[@]}"; do
    for m in ${GROUP_MODULES[$g]:-}; do
      if [[ " $(_module_header "$m" PROVIDES) " == *" $1 "* ]]; then
        printf '%s\n' "$g"
        return 0
      fi
    done
  done
  return 1
}

# Add what the selection needs until nothing changes, then sort into install order.
resolve_plan() {
  local changed=1 g m cmd provider
  while [ "$changed" = 1 ]; do
    changed=0
    if _selected stack && ! _selected dev; then
      SELECTED+=(dev); PLAN_NOTES+=("dev: stack-specific tools install through mise"); changed=1
    fi
    for g in "${SELECTED[@]}"; do
      for m in ${GROUP_MODULES[$g]:-}; do
        for cmd in $(_module_header "$m" NEEDS); do
          provider="$(_group_providing "$cmd")" || die "$m needs $cmd, but no module provides it."
          if ! _selected "$provider" && ! _have "$cmd"; then
            SELECTED+=("$provider"); PLAN_NOTES+=("$provider: needed by $m ($cmd)"); changed=1
          fi
        done
      done
    done
  done
  local sorted=()
  for g in "${GROUP_ORDER[@]}"; do
    if _selected "$g"; then sorted+=("$g"); fi
  done
  SELECTED=("${sorted[@]}")
  if _selected stack && [ -z "${MISE_TOOLS:-}" ]; then export MISE_TOOLS="$STACK_TOOLS"; fi
}

# All distros share one VM and network namespace, so another distro's daemon
# shows up here as an interface. A stopped local service looks the same, so warn
# and carry on.
_warn_vm_service() {
  if ip link show "$2" >/dev/null 2>&1 && ! systemctl is-active --quiet "$3" 2>/dev/null; then
    warn "$1: $2 exists but $3 isn't running here. Another distro in this WSL VM probably runs it, and they'd conflict."
  fi
}
_warn_vm_services() {
  if _selected docker; then _warn_vm_service Docker docker0 docker; fi
  if _selected tailscale; then _warn_vm_service Tailscale tailscale0 tailscaled; fi
}

show_plan() {
  local g note
  log "Plan:"
  for g in "${SELECTED[@]}"; do log "  $g: ${GROUP_MODULES[$g]:-${GROUP_LABELS[$g]:-$g}}"; done
  for note in "${PLAN_NOTES[@]}"; do log "  added $note"; done
  if [ -n "${MISE_TOOLS:-}" ]; then log "  MISE_TOOLS=$MISE_TOOLS"; fi
  _warn_vm_services
}

apply_preset() {
  [ -n "${PRESETS[$1]:-}" ] || die "Unknown preset: $1. Valid: ${!PRESETS[*]}"
  local g
  for g in ${PRESETS[$1]}; do
    # 00-wsl-base creates the user, so running as that user means it's done.
    if [ "$g" != base ] || is_root; then SELECTED+=("$g"); fi
  done
  if is_root; then SELECTED+=(cleanup); fi
}

# Start from a preset, then toggle groups by number.
guided_plan() {
  local preset reply n g i
  preset="$(ask "Preset (wsl, dev, ai, full)" ai)"
  apply_preset "$preset"
  local list=()
  for g in "${GROUP_ORDER[@]}"; do
    if [ "$g" != cleanup ]; then list+=("$g"); fi
  done
  while true; do
    for i in "${!list[@]}"; do
      g="${list[$i]}"
      if _selected "$g"; then n="x"; else n=" "; fi
      printf '  %2d) [%s] %s\n' "$((i + 1))" "$n" "${GROUP_LABELS[$g]}"
    done
    reply="$(ask "Toggle by number, Enter to continue")"
    [ -n "$reply" ] || break
    for n in $reply; do
      [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#list[@]}" ] || die "Invalid selection: $n"
      g="${list[$((n - 1))]}"
      if _selected "$g"; then
        local kept=() s
        for s in "${SELECTED[@]}"; do
          if [ "$s" != "$g" ]; then kept+=("$s"); fi
        done
        SELECTED=("${kept[@]}")
      else
        SELECTED+=("$g")
      fi
    done
  done
}

interactive_menu() {
  echo "Select what to run:"
  echo "  1) WSL only   (base setup, nothing else)"
  echo "  2) Dev        (terminal + dev tools)"
  echo "  3) AI         (dev + workflow tools, Claude Code, herdr, workbench)"
  echo "  4) Full       (AI + Docker, Tailscale, stack-specific tools)"
  echo "  5) Custom     (start from a preset, tick what you want)"
  echo "  6) One module"
  echo "  q) Quit"
  read -r -p "$(fmt_prompt "Choice >")" sel
  case "$sel" in
    1) MODE=menu; apply_preset wsl ;;
    2) MODE=menu; apply_preset dev ;;
    3) MODE=menu; apply_preset ai ;;
    4) MODE=menu; apply_preset full ;;
    5) MODE=menu; guided_plan ;;
    6) list_modules; read -r -p "$(fmt_prompt "Module name:")" SINGLE; MODE=single ;;
    q|Q) exit 0 ;;
    *) die "Invalid selection" ;;
  esac
}

# ----- group runners ----------------------------------------------------------
# Each runs one logical group. User-phase modules are silently deferred when
# the group is invoked as root; they surface in the handoff banner at the end.
DEFERRED=()
REOPEN_REQUIRED=0

_run_each() { for m in "$@"; do run_module "$m"; done; }

# Fall through (run-now) when base wasn't part of this invocation, so a
# standalone --docker on an unconfigured distro still hits the module's own
# die message instead of deferring to a reopen that has no new user to land as.
_runtime_needs_defer() {
  is_systemd && return 1
  [ -n "${RAN_MODULES[00-wsl-base]:-}" ] && return 0
  return 1
}

run_group() {
  case "$1" in
    base)    _run_each "${BASE_MODULES[@]}" ;;
    core)    _run_each "${CORE_MODULES[@]}" ;;
    dev)
      # When invoked as root, defer the entire dev group (root + user phase) to
      # the post-handoff child so the root-phase modules run exactly once — the
      # RAN_MODULES dedupe can't span the sudo-handoff process boundary.
      # Standalone non-root --dev runs both phases inline (run_module
      # auto-escalates the root modules via sudo).
      if is_root; then
        DEFERRED+=("--dev")
      else
        _run_each "${DEV_ROOT_MODULES[@]}"
        _run_each "${DEV_USER_MODULES[@]}"
      fi
      ;;
    docker)
      if _runtime_needs_defer; then
        log "Deferring docker until after the WSL reopen — base just enabled systemd."
        DEFERRED+=("--docker"); REOPEN_REQUIRED=1
      else
        _run_each "${DOCKER_MODULES[@]}"
      fi
      ;;
    podman)
      if _runtime_needs_defer; then
        log "Deferring podman until after the WSL reopen — base just enabled systemd."
        DEFERRED+=("--podman"); REOPEN_REQUIRED=1
      else
        _run_each "${PODMAN_MODULES[@]}"
      fi
      ;;
    claude)
      if is_root; then
        DEFERRED+=("--claude")
      else
        _run_each "${CLAUDE_MODULES[@]}"
      fi
      ;;
    tailscale)
      if _runtime_needs_defer; then
        log "Deferring tailscale until after the WSL reopen — base just enabled systemd."
        DEFERRED+=("--tailscale"); REOPEN_REQUIRED=1
      else
        _run_each "${TAILSCALE_MODULES[@]}"
      fi
      ;;
    stack) ;;
    workflow)
      if is_root; then
        DEFERRED+=("--workflow")
      else
        _run_each "${WORKFLOW_MODULES[@]}"
      fi
      ;;
    herdr)
      if is_root; then
        DEFERRED+=("--herdr")
      else
        _run_each "${HERDR_MODULES[@]}"
      fi
      ;;
    workbench)
      if is_root; then
        DEFERRED+=("--workbench")
      else
        _run_each "${WORKBENCH_MODULES[@]}"
      fi
      ;;
    logins)
      if is_root; then
        DEFERRED+=("--logins")
      else
        _run_each "${LOGINS_MODULES[@]}"
      fi
      ;;
    cleanup) run_module 99-cleanup ;;
    *) die "Unknown group: $1" ;;
  esac
}

MODE=""
SINGLE=""
SELECTED=()
PRINT_PLAN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base)             SELECTED+=(base core) ;;
    --dev)              SELECTED+=(dev) ;;
    --docker)           SELECTED+=(docker) ;;
    --podman)           SELECTED+=(podman) ;;
    --claude)           SELECTED+=(claude) ;;
    --tailscale)        SELECTED+=(tailscale) ;;
    --workflow)         SELECTED+=(workflow) ;;
    --herdr)            SELECTED+=(herdr) ;;
    --workbench)        SELECTED+=(workbench) ;;
    --preset)
      MODE="${MODE:-groups}"; apply_preset "${2:-none}"; shift ;;
    --print-plan)       PRINT_PLAN=1 ;;
    --logins)           SELECTED+=(logins) ;;
    --module)
      [ -z "$SINGLE" ] || die "--module specified twice (got '$SINGLE' then '${2:-}'). Pick one."
      MODE=single; SINGLE="${2:-}"; shift ;;
    --list)             list_modules; exit 0 ;;
    --rollback)
      # --rollback is exclusive — earlier group flags would be silently dropped
      # (we exit before they execute). Catch the common mistake `--base --rollback`;
      # `--rollback --base` is already covered because we exit before that token.
      if [ -n "$MODE" ] || [ ${#SELECTED[@]} -gt 0 ]; then
        die "--rollback cannot be combined with other group flags. Use '--rollback <module-name>' for a single module."
      fi
      # Optional positional arg: module name. Don't consume the next token if it
      # starts with `-` (any flag form — `--foo`, `-h`, etc.).
      _rb_target=""
      if [ $# -ge 2 ] && [ "${2:0:1}" != "-" ]; then
        _rb_target="$2"; shift
      fi
      print_rollback "$_rb_target"; exit 0 ;;
    --non-interactive)  export NON_INTERACTIVE=1 ;;
    --dry-run)          export DRY_RUN=1 ;;
    -h|--help)          usage; exit 0 ;;
    *) die "Unknown flag: $1 (see --help)" ;;
  esac
  shift || true
done

# --module is exclusive with group flags.
if [ "$MODE" = "single" ]; then
  [ ${#SELECTED[@]} -eq 0 ] || die "--module can't be combined with --preset or a group flag (--base, --dev, ...)."
fi

[ "$MODE" = "" ] && [ ${#SELECTED[@]} -gt 0 ] && MODE=groups
if [ -z "$MODE" ]; then
  # Refuse to drop into the interactive menu under --non-interactive — `read`
  # would block on the closed stdin (CI, sudo handoff). Operator must say
  # explicitly which group(s) to run.
  [ "$NON_INTERACTIVE" = "1" ] && die "--non-interactive requires --module, --preset or a group flag (--base, --dev, ...)."
  interactive_menu
fi

if [ "$MODE" = menu ]; then
  MODE=groups
  resolve_plan
  show_plan
  confirm "Run this plan?" y || exit 0
elif [ "$MODE" = groups ]; then
  resolve_plan
  show_plan
elif [ "$MODE" = single ]; then
  case "$SINGLE" in
    25-docker-engine) _warn_vm_service Docker docker0 docker ;;
    28-tailscale)     _warn_vm_service Tailscale tailscale0 tailscaled ;;
  esac
fi
[ "$PRINT_PLAN" = 0 ] || exit 0

case "$MODE" in
  groups)
    for g in "${SELECTED[@]}"; do run_group "$g"; done
    ;;
  single)
    [ -n "$SINGLE" ] || die "--module needs a name. See --list."
    run_module "$SINGLE"
    ;;
esac

# Auto-fire 27 only when this invocation ran a runtime module AND that module
# wrote $RUNTIME_STAMP (i.e. install actually happened, not DOCKER_MODE=skip).
# RAN_MODULES gates re-fire across the user-phase tail; stamp gates skip.
if { [ -n "${RAN_MODULES[25-docker-engine]:-}" ] || [ -n "${RAN_MODULES[26-podman]:-}" ]; } \
   && [ -f "$RUNTIME_STAMP" ]; then
  run_module 27-wsl-network
fi

if is_root && [ ${#DEFERRED[@]} -gt 0 ]; then
  echo
  warn "Root-phase done. User-phase modules (${DEFERRED[*]}) still need to run as your new user."

  # 00-wsl-base writes /run/wsl-starter-handoff with USER/HOME/REPO. Prefer it;
  # fall back to WSL_USER if the file isn't there (e.g. operator skipped --base
  # and is invoking a deferred group against an already-prepared distro).
  TARGET_USER=""; TARGET_HOME=""; TARGET_REPO=""
  if [ -r /run/wsl-starter-handoff ]; then
    # shellcheck disable=SC1091
    while IFS='=' read -r k v; do
      case "$k" in
        USER) TARGET_USER="$v" ;;
        HOME) TARGET_HOME="$v" ;;
        REPO) TARGET_REPO="$v" ;;
      esac
    done < /run/wsl-starter-handoff
  fi
  if [ -z "$TARGET_USER" ] && [ -n "${WSL_USER:-}" ] && id "$WSL_USER" >/dev/null 2>&1; then
    TARGET_USER="$WSL_USER"
    TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || true)"
    [ -n "$TARGET_HOME" ] && TARGET_REPO="$TARGET_HOME/$(basename "$REPO_ROOT")"
  fi

  CAN_CONTINUE=0
  if [ -n "$TARGET_USER" ] && [ -d "$TARGET_REPO" ] && [ -x "$TARGET_REPO/install.sh" ]; then
    CAN_CONTINUE=1
  fi

  if [ "$CAN_CONTINUE" = "1" ] && [ "$REOPEN_REQUIRED" = "0" ] \
     && confirm "Continue as '$TARGET_USER' now in this WSL session (skips reopen for ${DEFERRED[*]})?" y; then
    log "Handing off to $TARGET_USER via sudo -iu"
    # sudo -i + bash -lc → login shell, rc files re-sourced (picks up mid-run
    # mise/atuin wiring). FORWARD_ASSIGNS is %q-quoted so [*] join is shell-safe;
    # see _sudo_with_forwards for the argv-vs-string split.
    _collect_forward_assigns
    sudo -iu "$TARGET_USER" bash -lc "cd $(printf '%q' "$TARGET_REPO") && env ${FORWARD_ASSIGNS[*]} ./install.sh ${DEFERRED[*]}"
    echo
    warn "In-session handoff complete. You're still root in *this* shell, though."
    warn "Finish up from Windows PowerShell so the distro default user takes effect:"
    warn "  wsl --terminate ${WSL_DISTRO_NAME:-<your-distro>}"
  else
    if [ "$REOPEN_REQUIRED" = "1" ]; then
      warn "In-session handoff isn't an option: docker/podman were queued but"
      warn "systemd was just enabled and only becomes PID 1 after a WSL restart."
    fi
    warn "From Windows PowerShell:  wsl --terminate ${WSL_DISTRO_NAME:-<your-distro>}"
    warn "Reopen the distro (it will log you in as the user 00-wsl-base just created), then:"
    warn "  cd ~/$(basename "$REPO_ROOT") && ./install.sh ${DEFERRED[*]}"
    warn "(00-wsl-base copies this repo into the new user's \$HOME so it's already there.)"
  fi
fi
