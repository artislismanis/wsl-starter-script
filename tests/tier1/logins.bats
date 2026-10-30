#!/usr/bin/env bats
# 60-logins: checks each installed tool, logs in only what's missing, and
# defaults git identity from GitHub. Stub CLIs stand in for the real ones.

load helpers

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$HOME" "$STUBS"
  # gh: logged in, profile id 1 / octo / "Octo Cat".
  cat > "$STUBS/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "auth status") exit 0 ;;
  "api user") printf '1\tocto\tOcto Cat\n' ;;
esac
EOF
  # az: not logged in.
  printf '#!/bin/sh\nexit 1\n' > "$STUBS/az"
  chmod +x "$STUBS"/*
  export PATH="$STUBS:$PATH"
}

@test "non-interactive reports what's missing and runs no logins" {
  cd "$REPO_ROOT"
  run ./install.sh --logins --non-interactive --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '━━ 60-logins ━━'
  echo "$output" | grep -q 'GitHub: logged in'
  echo "$output" | grep -q 'Azure: az login --use-device-code'
  ! echo "$output" | grep -q '\$ .*auth login'
  # No WSL_GIT_* and no prompting, so identity is left as a to-do.
  echo "$output" | grep -q 'git identity: git config'
  ! echo "$output" | grep -q '\$ git config'
}

@test "non-interactive writes git identity only from WSL_GIT_*" {
  cd "$REPO_ROOT"
  WSL_GIT_NAME="Test User" WSL_GIT_EMAIL=t@example.invalid run ./install.sh --logins --non-interactive --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF '$ git config --global user.name Test\ User'
  echo "$output" | grep -qF '$ git config --global user.email t@example.invalid'
}

@test "interactive identity defaults to the GitHub name and no-reply email" {
  cd "$REPO_ROOT"
  # Enter twice to take both defaults; later prompts read EOF and take theirs.
  run bash -c 'printf "\n\n" | ./install.sh --logins --dry-run'
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF '$ git config --global user.name Octo\ Cat'
  echo "$output" | grep -qF '$ git config --global user.email 1+octo@users.noreply.github.com'
}

@test "existing git identity is left alone" {
  git config --global user.name "Already Set"
  git config --global user.email set@example.invalid
  cd "$REPO_ROOT"
  run ./install.sh --logins --non-interactive --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'git identity: Already Set <set@example.invalid>'
  ! echo "$output" | grep -q '\$ git config'
}
