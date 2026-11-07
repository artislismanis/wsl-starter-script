#!/usr/bin/env bats
# `--dev` invoked as root: the root module (20-cli-modern) runs once, in the
# root phase, and only the user modules wait for the handoff, by name. Before
# layers the whole group was deferred and 20 ran via sudo from the user phase.

load helpers

sudo_or_skip() {
  command -v sudo >/dev/null 2>&1 || skip "sudo not available"
  sudo -n true 2>/dev/null      || skip "passwordless sudo not available"
}

@test "root --dev runs cli-modern in the root phase and hands off only the user modules" {
  sudo_or_skip
  cd "$REPO_ROOT"
  # No /run/wsl-starter-handoff and no WSL_USER in this environment, so
  # CAN_CONTINUE stays 0 and the script just prints the deferral banner
  # instead of attempting the in-session sudo -iu handoff.
  run sudo -n -E env NON_INTERACTIVE=1 ./install.sh --dev --dry-run --non-interactive
  [ "$(echo "$output" | grep -c '━━ 20-cli-modern ━━' || true)" -eq 1 ]
  ! echo "$output" | grep -q '━━ 30-shell-zsh ━━'
  echo "$output" | grep -q -- '--module 30-shell-zsh,31-shell-history,32-git-config,40-mise'
}
