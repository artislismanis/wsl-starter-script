#!/usr/bin/env bash
# wsl-starter-script — modular WSL bootstrap.
# Usage: ./install.sh [--all|--base|--dev|--claude|--module NAME] [--non-interactive] [--dry-run]
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
  ./install.sh --all                 Run every module in order.
  ./install.sh --base                Root-phase only: 00-wsl-base + 10-apt-core.
  ./install.sh --dev                 cli-modern (root, auto-escalates) + zsh + history + mise.
                                     If invoked as root the user-phase is deferred to the
                                     post-handoff/reopen user run.
  ./install.sh --docker              Docker Engine (classic or rootless).
  ./install.sh --podman              Podman (rootless, daemonless).
  ./install.sh --claude              Claude Code CLI + user-global config.
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
                      DOCKER_MODE, DOCKER_USER, DOCKER_ROOTLESS_PASTA,
                      DOCKER_ROOTLESS_HOST_SYMLINK,
                      PODMAN_COMPOSE, PODMAN_DOCKER_SHIM,
                      ZSH_THEME, ZSH_PLUGINS, CLAUDE_PERMISSION_MODE.
                      Full list and defaults in README.md.
  --dry-run           Print what would happen, make no changes.
  -h, --help          This message.

Note: --all runs base → dev → docker → claude → cleanup. Podman is excluded
(it's an alternative to Docker, not a complement); pass --podman explicitly.
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

BASE_MODULES=(00-wsl-base 10-apt-core)
DEV_ROOT_MODULES=(20-cli-modern)
DEV_USER_MODULES=(30-shell-zsh 31-shell-history 40-mise)
DOCKER_MODULES=(25-docker-engine)
PODMAN_MODULES=(26-podman)
CLAUDE_MODULES=(50-claude-code)
# 27-wsl-network is fired once at the bottom of the script (see the gate after
# the case block) when a container-runtime module ran AND actually installed.
# Combining --docker --podman in one invocation runs it once via RAN_MODULES.

interactive_menu() {
  echo "Select what to run:"
  echo "  1) Guided setup    (ask about each group: base / dev / docker / podman / claude)"
  echo "  2) Full setup      (base → dev → docker → claude → cleanup; excludes podman)"
  echo "  3) Base only       (root: systemd, user, hostname, DNS)"
  echo "  4) Dev only        (CLI tools, zsh, history, mise)"
  echo "  5) Docker only     (Docker Engine: classic or rootless)"
  echo "  6) Podman only     (rootless, daemonless)"
  echo "  7) Claude only     (claude-code + config)"
  echo "  8) Single module"
  echo "  9) List modules"
  echo "  q) Quit"
  read -r -p "$(fmt_prompt "Choice >")" sel
  case "$sel" in
    1) MODE=guided ;;
    2) MODE=all ;;
    3) MODE=groups; SELECTED=(base) ;;
    4) MODE=groups; SELECTED=(dev) ;;
    5) MODE=groups; SELECTED=(docker) ;;
    6) MODE=groups; SELECTED=(podman) ;;
    7) MODE=groups; SELECTED=(claude) ;;
    8) list_modules; read -r -p "$(fmt_prompt "Module name:")" SINGLE; MODE=single ;;
    9) list_modules; exit 0 ;;
    q|Q) exit 0 ;;
    *) die "Invalid selection" ;;
  esac
}

# ----- group runners ----------------------------------------------------------
# Each runs one logical group. User-phase modules are silently deferred when
# the group is invoked as root; they surface in the handoff banner at the end.
DEFERRED=()

_run_each() { for m in "$@"; do run_module "$m"; done; }

run_group() {
  case "$1" in
    base)    _run_each "${BASE_MODULES[@]}" ;;
    dev)
      # Root-phase always runs (run_module auto-escalates if non-root). User-phase
      # is deferred to post-handoff/reopen when invoked as root. Under --all as
      # root the dev root-phase runs twice (here + in the deferred re-invocation);
      # idempotent and cheap, just a duplicate log line.
      _run_each "${DEV_ROOT_MODULES[@]}"
      if is_root; then
        DEFERRED+=("--dev")
      else
        _run_each "${DEV_USER_MODULES[@]}"
      fi
      ;;
    docker)  _run_each "${DOCKER_MODULES[@]}" ;;
    podman)  _run_each "${PODMAN_MODULES[@]}" ;;
    claude)
      if is_root; then
        DEFERRED+=("--claude")
      else
        _run_each "${CLAUDE_MODULES[@]}"
      fi
      ;;
    cleanup) run_module 99-cleanup ;;
    *) die "Unknown group: $1" ;;
  esac
}

MODE=""
SINGLE=""
SELECTED=()
while [ $# -gt 0 ]; do
  case "$1" in
    --all)              MODE=all ;;
    --base)             SELECTED+=(base) ;;
    --dev)              SELECTED+=(dev) ;;
    --docker)           SELECTED+=(docker) ;;
    --podman)           SELECTED+=(podman) ;;
    --claude)           SELECTED+=(claude) ;;
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

# --all and --module are exclusive with group flags.
if [ "$MODE" = "all" ] || [ "$MODE" = "single" ]; then
  [ ${#SELECTED[@]} -eq 0 ] || die "--all/--module can't be combined with --base/--dev/--docker/--podman/--claude."
fi

[ "$MODE" = "" ] && [ ${#SELECTED[@]} -gt 0 ] && MODE=groups
if [ -z "$MODE" ]; then
  # Refuse to drop into the interactive menu under --non-interactive — `read`
  # would block on the closed stdin (CI, sudo handoff). Operator must say
  # explicitly which group(s) to run.
  [ "$NON_INTERACTIVE" = "1" ] && die "--non-interactive requires --all, --module, or one of --base/--dev/--docker/--podman/--claude."
  interactive_menu
fi

case "$MODE" in
  all)
    run_group base
    run_group dev
    run_group docker
    run_group claude
    # Cleanup is root-only; skip when we're running the user-phase tail of --all.
    if is_root; then run_group cleanup; fi
    ;;
  groups)
    for g in "${SELECTED[@]}"; do run_group "$g"; done
    ;;
  guided)
    confirm "Run base setup (systemd, user, hostname, DNS)?" y && run_group base
    confirm "Install dev tools (CLI modern, zsh, history, mise)?" y && run_group dev
    confirm "Install Docker Engine?" n && run_group docker
    confirm "Install Podman (daemonless, rootless — co-installable with docker)?" n && run_group podman
    confirm "Install Claude Code?" y && run_group claude
    ;;
  single)
    [ -n "$SINGLE" ] || die "--module needs a name. See --list."
    run_module "$SINGLE"
    ;;
esac

# Auto-fire 27 only when this invocation ran a runtime module AND that module
# wrote $RUNTIME_STAMP (i.e. install actually happened, not DOCKER_MODE=skip).
# RAN_MODULES gates re-fire across the user-phase --all tail; stamp gates skip.
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

  if [ "$CAN_CONTINUE" = "1" ] && confirm "Continue as '$TARGET_USER' now in this WSL session (skips reopen for ${DEFERRED[*]})?" y; then
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
    warn "From Windows PowerShell:  wsl --terminate ${WSL_DISTRO_NAME:-<your-distro>}"
    warn "Reopen the distro (it will log you in as the user 00-wsl-base just created), then:"
    warn "  cd ~/$(basename "$REPO_ROOT") && ./install.sh ${DEFERRED[*]}"
    warn "(00-wsl-base copies this repo into the new user's \$HOME so it's already there.)"
  fi
fi
