#!/usr/bin/env bash
# REQUIRES_ROOT=0
# DESCRIPTION=Workbench: herdr + worktrunk + hunk as pinned release binaries, gh-stack + its agent skill, then herdr-workbench config at a pinned commit
# ROLLBACK=# herdr-workbench first: its own recipe strips its block from ~/.config/worktrunk/config.toml and removes its hooks.
# ROLLBACK=[ -x "$HOME/.local/share/herdr-workbench/install.sh" ] && "$HOME/.local/share/herdr-workbench/install.sh" --rollback | bash
# ROLLBACK=rm -rf "$HOME/.local/share/herdr-workbench"
# ROLLBACK=rm -f "$HOME/.local/bin/herdr" "$HOME/.local/bin/wt" "$HOME/.local/bin/git-wt" "$HOME/.local/bin/hunk"
# ROLLBACK=rm -rf "$HOME/.local/share/hunkdiff-linux-x64"
# ROLLBACK=gh extension remove stack 2>/dev/null || true
# ROLLBACK=rm -rf "$HOME/.claude/skills/gh-stack"
# ROLLBACK=# wsl-starter:worktrunk rc block: covered by the cross-cutting rc-block strip.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_user

# Plain binaries in ~/.local/bin rather than mise tools: herdr, its popups and
# git hooks don't always start from a shell that ran `mise activate`.
# .github/bump-pins.sh moves each pin to upstream's latest and recomputes its
# sha256; reviewing the upstream diff and merging that PR is the approval.
HERDR_VERSION=0.9.5  # bump: github:herdrdev/herdr herdr-linux-x86_64
HERDR_SHA256=14d9e8bc8b4a9e0118d77c32266f76d461f09b40342eb23752960bd89f59929d
WT_VERSION=0.81.0  # bump: github:max-sixty/worktrunk worktrunk-x86_64-unknown-linux-musl.tar.xz
WT_SHA256=0c253f216985ce9cd7b202a11606b5ce6aa934b1019fd1fbb9b7ce2b47b1c74a
HUNK_VERSION=0.24.1  # bump: github:modem-dev/hunk hunkdiff-linux-x64.tar.gz
HUNK_SHA256=4b8c98f8d97745499916cc1e1d2f27ffd258c6d6358dd4532f61e41c5eb19692
GH_STACK_VERSION=0.3.0  # bump: github:github/gh-stack linux-amd64
GH_STACK_SHA256=957e822cfa7e435cd84a297cd96c419b58e51e3ac58be249762c24bd9e45099b
WORKBENCH_COMMIT=babfb4b29b92e4bc5ea8cfb61234f57831a62c3f  # bump: git:artislismanis/herdr-workbench

BIN="$HOME/.local/bin"
SHARE="$HOME/.local/share"
WB_DIR="$SHARE/herdr-workbench"

# _install_release <url> <sha256> <dest-dir> <path>...: fetch the tarball,
# refuse it unless its sha256 matches the pin, then copy each <path> inside it
# into <dest-dir>. Called through run/retry_run so dry-run stays total.
_install_release() {
  local url="$1" sha="$2" dest="$3" t rc=0 p
  shift 3
  t="$(mktemp -d)"
  if curl -fsSL -o "$t/pkg" "$url" && echo "$sha  $t/pkg" | sha256sum -c --quiet - && tar -xf "$t/pkg" -C "$t"; then
    mkdir -p "$dest"
    for p in "$@"; do
      rm -rf "${dest:?}/$(basename "$p")"
      cp -a "$t/$p" "$dest/" || rc=1
    done
  else
    rc=1
  fi
  rm -rf "$t"
  return "$rc"
}

# _install_binary <url> <sha256> <dest>: like _install_release for a release
# that is a bare binary rather than a tarball.
_install_binary() {
  local url="$1" sha="$2" dest="$3" t rc=0
  t="$(mktemp)"
  if curl -fsSL -o "$t" "$url" && echo "$sha  $t" | sha256sum -c --quiet -; then
    mkdir -p "$(dirname "$dest")"
    install -m 755 "$t" "$dest" || rc=1
  else
    rc=1
  fi
  rm -f "$t"
  return "$rc"
}

_has_version() { [ -x "$1" ] && "$1" --version 2>/dev/null | grep -qF "$2"; }

# herdr updates itself unless told not to; herdr-workbench's config turns the
# version check off, so this pin is the only thing that moves it.
if _has_version "$BIN/herdr" "$HERDR_VERSION"; then
  skip "herdr $HERDR_VERSION already installed"
else
  log "Installing herdr $HERDR_VERSION"
  retry_run 3 "_install_binary https://github.com/herdrdev/herdr/releases/download/v$HERDR_VERSION/herdr-linux-x86_64 $HERDR_SHA256 '$BIN/herdr'"
fi

if _has_version "$BIN/wt" "$WT_VERSION"; then
  skip "worktrunk $WT_VERSION already installed"
else
  log "Installing worktrunk $WT_VERSION"
  retry_run 3 "_install_release https://github.com/max-sixty/worktrunk/releases/download/v$WT_VERSION/worktrunk-x86_64-unknown-linux-musl.tar.xz $WT_SHA256 '$BIN' worktrunk-x86_64-unknown-linux-musl/wt worktrunk-x86_64-unknown-linux-musl/git-wt"
fi

# hunk keeps its bundled skills next to the binary, so the whole directory
# goes under ~/.local/share and ~/.local/bin gets a symlink.
if _has_version "$BIN/hunk" "$HUNK_VERSION"; then
  skip "hunk $HUNK_VERSION already installed"
else
  log "Installing hunk $HUNK_VERSION"
  retry_run 3 "_install_release https://github.com/modem-dev/hunk/releases/download/v$HUNK_VERSION/hunkdiff-linux-x64.tar.gz $HUNK_SHA256 '$SHARE' hunkdiff-linux-x64"
  run "ln -sfn '$SHARE/hunkdiff-linux-x64/hunk' '$BIN/hunk'"
fi

# ---- gh-stack ----------------------------------------------------------------
# GitHub's native stacked PRs. A gh extension rather than a binary in
# ~/.local/bin, since it runs as `gh stack`; the sha256 is checked after gh
# installs it. Its agent skill is pinned to the same tag so the two agree.
GH_STACK_BIN="${XDG_DATA_HOME:-$HOME/.local/share}/gh/extensions/gh-stack/gh-stack"
if ! command_exists gh; then
  warn "gh not installed (it comes with --dev); skipping gh-stack."
else
  if echo "$GH_STACK_SHA256  $GH_STACK_BIN" | sha256sum -c --quiet - >/dev/null 2>&1; then
    skip "gh-stack $GH_STACK_VERSION already installed"
  else
    log "Installing gh-stack $GH_STACK_VERSION"
    run "gh extension remove stack >/dev/null 2>&1 || true"
    retry_run 3 "gh extension install github/gh-stack --pin v$GH_STACK_VERSION"
    if [ "$DRY_RUN" != "1" ] && ! echo "$GH_STACK_SHA256  $GH_STACK_BIN" | sha256sum -c --quiet - >/dev/null 2>&1; then
      gh extension remove stack >/dev/null 2>&1 || true
      die "gh-stack $GH_STACK_VERSION doesn't match its pinned sha256; removed it."
    fi
  fi
  if grep -qx "    github-pinned: v$GH_STACK_VERSION" "$HOME/.claude/skills/gh-stack/SKILL.md" 2>/dev/null; then
    skip "gh-stack skill $GH_STACK_VERSION already installed"
  else
    retry_run 3 "gh skill install github/gh-stack gh-stack --pin v$GH_STACK_VERSION --agent claude-code --scope user --force"
  fi
fi

# Shell integration lets `wt switch` cd. Our own block rather than
# `wt config shell install`, which writes outside the wsl-starter fences.
ensure_block_per_shell "wsl-starter:worktrunk" "$HOME" \
  'command -v wt >/dev/null 2>&1 && eval "$(wt config shell init bash)"' \
  'command -v wt >/dev/null 2>&1 && eval "$(wt config shell init zsh)"'

# ---- herdr-workbench ----------------------------------------------------------
# Public repo, so no gh login needed. Detached at the pin; install.sh copies
# what it needs, so the clone changes nothing until it runs.
if [ ! -d "$WB_DIR/.git" ]; then
  retry_run 3 "git clone --quiet https://github.com/artislismanis/herdr-workbench.git '$WB_DIR'"
fi
if [ "$(git -C "$WB_DIR" rev-parse HEAD 2>/dev/null || true)" = "$WORKBENCH_COMMIT" ]; then
  skip "herdr-workbench already at ${WORKBENCH_COMMIT:0:12}"
else
  if ! git -C "$WB_DIR" cat-file -e "$WORKBENCH_COMMIT^{commit}" 2>/dev/null; then
    retry_run 3 "git -C '$WB_DIR' fetch --quiet origin"
  fi
  run "git -C '$WB_DIR' checkout --quiet --detach '$WORKBENCH_COMMIT'"
fi
if [ "$DRY_RUN" != "1" ] && [ "$(git -C "$WB_DIR" rev-parse HEAD)" != "$WORKBENCH_COMMIT" ]; then
  die "herdr-workbench is at $(git -C "$WB_DIR" rev-parse HEAD), expected $WORKBENCH_COMMIT"
fi
run "'$WB_DIR/install.sh'"

ok "Workbench ready: herdr $HERDR_VERSION, wt $WT_VERSION, hunk $HUNK_VERSION, gh-stack $GH_STACK_VERSION, herdr-workbench ${WORKBENCH_COMMIT:0:12}."
