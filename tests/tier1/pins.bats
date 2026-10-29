#!/usr/bin/env bats
# Supply chain: every mise-installed version is an exact pin, never latest.

load helpers

@test "40-mise pins no tool or runtime to latest" {
  cd "$REPO_ROOT"
  ! grep -nE '@latest|:-latest\}|:-lts\}' modules/40-mise.sh
}

@test "every pinned default is one bump-pins.sh can resolve to a tool" {
  cd "$REPO_ROOT"
  local n
  n="$(grep -cE '\$\{MISE_[A-Z_]+_VERSION:-' modules/40-mise.sh)"
  [ "$n" -gt 0 ]
  # Every pin line names its tool before the @ or carries a `# bump:` spec.
  ! grep -E '\$\{MISE_[A-Z_]+_VERSION:-' modules/40-mise.sh \
    | grep -vE '[^]["@[:space:]]+(\[[^]]*\])?@\$\{MISE_|# bump: '
}
