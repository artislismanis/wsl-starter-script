#!/usr/bin/env bats
# Regression for the double-run of 20-cli-modern: `--dev` invoked as root used
# to run the root-phase array unconditionally *and* defer the whole group,
# so the deferred child re-ran it — a second sudo password prompt + duplicate
# work in real use. The dev group must now defer wholesale when root, so the
# root-phase banner appears zero times in the parent process (it only runs in
# the deferred child/reopen).

load helpers

sudo_or_skip() {
  command -v sudo >/dev/null 2>&1 || skip "sudo not available"
  sudo -n true 2>/dev/null      || skip "passwordless sudo not available"
}

@test "root --dev defers cli-modern wholesale instead of running it in the parent" {
  sudo_or_skip
  cd "$REPO_ROOT"
  # No /run/wsl-starter-handoff and no WSL_USER in this environment, so
  # CAN_CONTINUE stays 0 and the script just prints the deferral banner
  # instead of attempting the in-session sudo -iu handoff.
  run sudo -n -E env NON_INTERACTIVE=1 ./install.sh --dev --dry-run --non-interactive
  local banner_count
  banner_count="$(echo "$output" | grep -c '━━ 20-cli-modern ━━' || true)"
  [ "$banner_count" -eq 0 ]
  echo "$output" | grep -q -- '--dev'
}
