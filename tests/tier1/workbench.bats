#!/usr/bin/env bats
# 55-workbench: opt-in dispatch, dry-run, rollback, and pins that bump-pins.sh
# can move.

load helpers

MOD=modules/55-workbench.sh

@test "--workbench --dry-run previews a verified download, the clone and the install" {
  cd "$REPO_ROOT"
  HOME="$BATS_TEST_TMPDIR" run ./install.sh --workbench --dry-run --non-interactive
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '━━ 55-workbench ━━'
  echo "$output" | grep -q '_install_release https://github.com/max-sixty/worktrunk/releases/download/'
  echo "$output" | grep -q '_install_release https://github.com/modem-dev/hunk/releases/download/'
  echo "$output" | grep -q 'git clone --quiet https://github.com/artislismanis/herdr-workbench.git'
  echo "$output" | grep -q "herdr-workbench/install.sh'"
  [ ! -e "$BATS_TEST_TMPDIR/.local" ]
  [ ! -e "$BATS_TEST_TMPDIR/.config/worktrunk" ]
}

@test "--all never runs 55-workbench" {
  cd "$REPO_ROOT"
  local branch
  branch="$(sed -n '/^  all)$/,/^    ;;$/p' install.sh)"
  echo "$branch" | grep -q 'run_group claude'
  ! echo "$branch" | grep -q workbench
}

@test "rollback 55-workbench undoes herdr-workbench before removing the binaries" {
  cd "$REPO_ROOT"
  run ./install.sh --rollback 55-workbench
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'herdr-workbench/install.sh" --rollback | bash'
  echo "$output" | grep -q 'rm -f "$HOME/.local/bin/wt"'
  [ "$(echo "$output" | grep -n 'install.sh" --rollback' | cut -d: -f1)" -lt \
    "$(echo "$output" | grep -n 'local/bin/wt' | cut -d: -f1)" ]
}

@test "every binary pin has a sha256 and a bump spec; the workbench pin is a full commit" {
  cd "$REPO_ROOT"
  grep -qE '^WT_VERSION=[0-9.]+  # bump: github:max-sixty/worktrunk [^ ]+$' "$MOD"
  grep -qE '^WT_SHA256=[0-9a-f]{64}$' "$MOD"
  grep -qE '^HUNK_VERSION=[0-9.]+  # bump: github:modem-dev/hunk [^ ]+$' "$MOD"
  grep -qE '^HUNK_SHA256=[0-9a-f]{64}$' "$MOD"
  grep -qE '^WORKBENCH_COMMIT=[0-9a-f]{40}  # bump: git:artislismanis/herdr-workbench$' "$MOD"
}

@test "bump-binaries.sh moves a version with its sha256, and a commit" {
  local stubs="$BATS_TEST_TMPDIR/bin" f="$BATS_TEST_TMPDIR/mod.sh"
  mkdir -p "$stubs"
  cat >"$stubs/gh" <<'STUB'
#!/usr/bin/env bash
case "$2" in
  repos/o/tool/releases/latest) echo v2.0.0 ;;
  repos/o/cfg/commits/HEAD) printf 'b%.0s' {1..40}; echo ;;
esac
STUB
  # curl -fsSL -o <file> <url>: the "asset" is the URL itself.
  printf '#!/usr/bin/env bash\nprintf %%s "$4" >"$3"\n' >"$stubs/curl"
  chmod +x "$stubs/gh" "$stubs/curl"
  printf 'X_VERSION=1.0.0  # bump: github:o/tool tool.tar.gz\nX_SHA256=old\nC_COMMIT=%s  # bump: git:o/cfg\n' \
    "$(printf 'a%.0s' {1..40})" >"$f"
  PATH="$stubs:$PATH" run "$REPO_ROOT/.github/bump-binaries.sh" "$f"
  [ "$status" -eq 0 ]
  grep -qx 'X_VERSION=2.0.0  # bump: github:o/tool tool.tar.gz' "$f"
  want="$(printf %s https://github.com/o/tool/releases/download/v2.0.0/tool.tar.gz | sha256sum | cut -d' ' -f1)"
  grep -qx "X_SHA256=$want" "$f"
  grep -qx "C_COMMIT=$(printf 'b%.0s' {1..40})  # bump: git:o/cfg" "$f"
  echo "$output" | grep -q 'o/tool: 1.0.0 -> 2.0.0'
}
