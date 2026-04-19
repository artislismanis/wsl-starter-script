#!/usr/bin/env bash
# REQUIRES_ROOT=1
# DESCRIPTION=apt autoremove + next-steps banner
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
require_root

log "apt autoremove + clean"
run "DEBIAN_FRONTEND=noninteractive apt-get autoremove -y"
run "DEBIAN_FRONTEND=noninteractive apt-get clean"

cat <<BANNER

  Done. Suggested next steps:

    1. From Windows PowerShell:   wsl --terminate ${WSL_DISTRO_NAME:-<your-distro>}
    2. Reopen your WSL distro (you'll land as the new user).
    3. In a project dir:          claude
    4. Review user-global config: \${EDITOR:-nano} ~/.claude/CLAUDE.md

BANNER
