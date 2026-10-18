#!/usr/bin/env bats
# worktrunk pre-start hook (modules/files/herdr-workbench/worktrunk-setup):
# stack detection against fixture repos, with every install command stubbed to
# log its argv instead of running.

bats_require_minimum_version 1.5.0
load helpers

HOOK="$REPO_ROOT/modules/files/herdr-workbench/worktrunk-setup"

setup() {
  STUBS="$BATS_TEST_TMPDIR/bin"
  STUB_LOG="$BATS_TEST_TMPDIR/calls.log"
  # The hook appends ~/.local/bin to PATH; keep the real mise out of reach.
  HOME="$BATS_TEST_TMPDIR"
  export STUB_LOG HOME
  mkdir -p "$STUBS"
  : >"$STUB_LOG"
  stub wt uv poetry npm terraform dbt
  # mise: `env` prints nothing; `tasks info setup` succeeds only when the
  # fixture's mise.toml defines a setup task.
  cat >"$STUBS/mise" <<'EOF'
#!/usr/bin/env bash
echo "mise $*" >>"$STUB_LOG"
case "$1" in
  tasks) grep -q '^\[tasks\.setup\]' mise.toml 2>/dev/null ;;
esac
EOF
  chmod +x "$STUBS/mise"

  PRIMARY="$BATS_TEST_TMPDIR/primary"
  WT="$BATS_TEST_TMPDIR/wt"
  mkdir -p "$PRIMARY" "$WT"
  git -C "$WT" init -q
}

stub() {
  local c
  for c in "$@"; do
    printf '#!/usr/bin/env bash\necho "%s $*" >>"$STUB_LOG"\n' "$c" >"$STUBS/$c"
    chmod +x "$STUBS/$c"
  done
}

run_hook() {
  cd "$WT"
  PATH="$STUBS:/usr/bin:/bin" run --separate-stderr bash "$HOOK" "$PRIMARY"
}

called() { grep -qx "$1" "$STUB_LOG"; }

@test "uv repo runs uv sync" {
  touch "$WT/uv.lock"
  run_hook
  [ "$status" -eq 0 ]
  called "uv sync"
  ! grep -q '^poetry' "$STUB_LOG"
}

@test "poetry repo runs poetry install and points mise at the in-project venv" {
  touch "$WT/poetry.lock"
  run_hook
  [ "$status" -eq 0 ]
  called "poetry install"
  grep -q '_.python.venv = ".venv"' "$WT/mise.local.toml"
  git -C "$WT" check-ignore -q mise.local.toml
}

@test "poetry repo without poetry warns and skips" {
  rm "$STUBS/poetry"
  touch "$WT/poetry.lock"
  run_hook
  [ "$status" -eq 0 ]
  echo "$stderr" | grep -q "poetry isn't installed"
  [ ! -f "$WT/mise.local.toml" ]
}

@test "mixed repo with [tool.poetry] follows poetry" {
  touch "$WT/uv.lock" "$WT/poetry.lock"
  printf '[tool.poetry]\nname = "x"\n' >"$WT/pyproject.toml"
  run_hook
  called "poetry install"
  ! called "uv sync"
}

@test "mixed repo without [tool.poetry] follows uv" {
  touch "$WT/uv.lock" "$WT/poetry.lock"
  printf '[project]\nname = "x"\n' >"$WT/pyproject.toml"
  run_hook
  called "uv sync"
  ! grep -q '^poetry' "$STUB_LOG"
}

@test "npm, dbt and terraform files each trigger their install" {
  touch "$WT/package-lock.json" "$WT/dbt_project.yml" "$WT/.terraform.lock.hcl"
  run_hook
  [ "$status" -eq 0 ]
  called "npm ci"
  called "dbt deps"
  called "terraform init -input=false"
}

@test "mise setup task wins over file detection" {
  touch "$WT/uv.lock" "$WT/package-lock.json"
  printf '[tasks.setup]\nrun = "make"\n' >"$WT/mise.toml"
  run_hook
  [ "$status" -eq 0 ]
  called "mise trust --quiet"
  called "mise install"
  called "mise run setup"
  ! called "uv sync"
  ! called "npm ci"
}

@test "copy-ignored runs only when the primary worktree has .worktreeinclude" {
  run_hook
  ! called "wt step copy-ignored"
  touch "$PRIMARY/.worktreeinclude"
  run_hook
  called "wt step copy-ignored"
}

@test "a failing step warns and the hook still exits 0" {
  printf '#!/usr/bin/env bash\necho "npm $*" >>"$STUB_LOG"\nexit 1\n' >"$STUBS/npm"
  touch "$WT/package-lock.json" "$WT/.terraform.lock.hcl"
  run_hook
  [ "$status" -eq 0 ]
  echo "$stderr" | grep -q "'npm ci' failed"
  called "terraform init -input=false"
}
