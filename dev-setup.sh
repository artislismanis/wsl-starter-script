#!/usr/bin/env bash
# dev-setup.sh — install the host tools contributors to this repo need.
#
# Re-runnable. The runtime install (bootstrap.sh / install.sh) needs nothing
# beyond stock Ubuntu bash; this script covers the contributor-only extras
# (lint, test harness, pre-commit hook) that sit outside that line.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

command -v apt-get >/dev/null 2>&1 \
  || { echo "dev-setup.sh: apt-get not found — this script targets Debian/Ubuntu." >&2; exit 1; }

PKGS=(bats shellcheck dos2unix)
missing=()
for p in "${PKGS[@]}"; do
  dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "Installing: ${missing[*]}"
  sudo apt-get update
  sudo apt-get install -y "${missing[@]}"
else
  echo "All dev packages already installed: ${PKGS[*]}"
fi

if [ "$(git config --get core.hooksPath || true)" = ".githooks" ]; then
  echo "Pre-commit hook already enabled (core.hooksPath=.githooks)."
else
  echo "Enabling pre-commit hook (git config core.hooksPath .githooks)."
  git config core.hooksPath .githooks
fi

echo "Done. Verify with: ./lint.sh && ./tests/tier1/run.sh"
