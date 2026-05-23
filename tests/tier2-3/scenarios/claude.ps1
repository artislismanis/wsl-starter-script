# Scenarios 5 + 6 — Claude Code module + config preservation.

& "$PSScriptRoot/../run-scenario.ps1" `
  -Name 'claude' `
  -InstallSteps @(
    @{ User='root';   Command='WSL_USER=tester WSL_PASSWORD=testpass123 WSL_HOSTNAME=testbox WSL_DNS="1.1.1.1" WSL_APT_UPGRADE=0 ./install.sh --base --non-interactive' }
    @{ User='tester'; Command='cp -r /root/wsl-starter-script ~/wsl-starter-script && chown -R tester:tester ~/wsl-starter-script' }
    @{ User='tester'; Command='cd ~/wsl-starter-script && CLAUDE_PERMISSION_MODE=acceptEdits ./install.sh --claude --non-interactive' }
    # Preservation: edit CLAUDE.md, re-run, marker must survive.
    @{ User='tester'; Command='echo "# MY CUSTOM MARKER" >> ~/.claude/CLAUDE.md' }
    @{ User='tester'; Command='cd ~/wsl-starter-script && CLAUDE_PERMISSION_MODE=acceptEdits ./install.sh --claude --non-interactive' }
    @{ User='tester'; Command='grep "MY CUSTOM MARKER" ~/.claude/CLAUDE.md' }
  ) `
  -GossFile 'tests/tier2-3/goss/claude.yaml' `
  -GossUser 'tester'
