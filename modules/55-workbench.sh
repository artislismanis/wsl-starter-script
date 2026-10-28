#!/usr/bin/env bash
# REQUIRES_ROOT=0
# DESCRIPTION=Workbench: worktrunk + hunk as pinned release binaries, then herdr-workbench config at a pinned commit
# ROLLBACK=# herdr-workbench first: its own recipe strips its block from ~/.config/worktrunk/config.toml and removes its hooks.
# ROLLBACK=[ -x "$HOME/.local/share/herdr-workbench/install.sh" ] && "$HOME/.local/share/herdr-workbench/install.sh" --rollback | bash
# ROLLBACK=rm -rf "$HOME/.local/share/herdr-workbench"
# ROLLBACK=rm -f "$HOME/.local/bin/wt" "$HOME/.local/bin/git-wt" "$HOME/.local/bin/hunk"
# ROLLBACK=rm -rf "$HOME/.local/share/hunkdiff-linux-x64"
# ROLLBACK=# wsl-starter:worktrunk rc block: covered by the cross-cutting rc-block strip.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_user

# Plain binaries in ~/.local/bin rather than mise tools: herdr, its popups and
# git hooks don't always start from a shell that ran `mise activate`.
# .github/bump-pins.sh moves each pin to upstream's latest and recomputes its
# sha256; reviewing the upstream diff and merging that PR is the approval.
WT_VERSION=0.81.0  # bump: github:max-sixty/worktrunk worktrunk-x86_64-unknown-linux-musl.tar.xz
WT_SHA256=0c253f216985ce9cd7b202a11606b5ce6aa934b1019fd1fbb9b7ce2b47b1c74a
HUNK_VERSION=0.24.1  # bump: github:modem-dev/hunk hunkdiff-linux-x64.tar.gz
HUNK_SHA256=4b8c98f8d97745499916cc1e1d2f27ffd258c6d6358dd4532f61e41c5eb19692
WORKBENCH_COMMIT=71ffea59c45a7cbe165ce03ab1e78fe3c5913cb8  # bump: git:artislismanis/herdr-workbench

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

_has_version() { [ -x "$1" ] && "$1" --version 2>/dev/null | grep -qF "$2"; }

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

ok "Workbench ready: wt $WT_VERSION, hunk $HUNK_VERSION, herdr-workbench ${WORKBENCH_COMMIT:0:12}."
