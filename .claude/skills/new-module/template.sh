#!/usr/bin/env bash
# REQUIRES_ROOT=__REQUIRES_ROOT__
# DESCRIPTION=__DESCRIPTION__
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
__GUARD__

# TODO: install logic goes here.
# Conventions:
#   - apt_install pkg1 pkg2
#   - apt_add_signed_repo name key-url deb-line
#   - ensure_block "wsl-starter:<topic>" "$HOME/.bashrc" 'export FOO=bar'
#   - wrap mutations in run "…" so --dry-run honours them
#   - guard every step (command_exists, pkg_installed, file existence)

ok "__DESCRIPTION__ done."
