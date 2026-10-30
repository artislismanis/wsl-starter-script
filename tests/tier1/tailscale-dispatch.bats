#!/usr/bin/env bats
# 28-tailscale is opt-in: --tailscale or the full preset runs it.

load helpers

sudo_or_skip() {
  command -v sudo >/dev/null 2>&1 || skip "sudo not available"
  sudo -n true 2>/dev/null      || skip "passwordless sudo not available"
}

@test "--tailscale dispatches 28-tailscale" {
  sudo_or_skip
  [ -d /run/systemd/system ] || skip "systemd not running"
  cd "$REPO_ROOT"
  run sudo -n -E env NON_INTERACTIVE=1 ./install.sh --tailscale --dry-run --non-interactive
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '━━ 28-tailscale ━━'
  echo "$output" | grep -q 'systemctl enable --now tailscaled\|tailscaled already enabled'
}

@test "rollback 28-tailscale removes the repo, key and service" {
  cd "$REPO_ROOT"
  run ./install.sh --rollback 28-tailscale
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '/etc/apt/sources.list.d/tailscale.list'
  echo "$output" | grep -q '/etc/apt/keyrings/tailscale.gpg'
  echo "$output" | grep -q 'disable --now tailscaled'
}

