# Scenario 12 — full E2E. Long. Exercises every module end-to-end with a
# real wsl --terminate round-trip in the middle.

& "$PSScriptRoot/../run-scenario.ps1" `
  -Name 'full-e2e' `
  -InstallSteps @(
    @{ User='root';   Command='WSL_USER=tester WSL_PASSWORD=testpass123 WSL_HOSTNAME=testbox WSL_DNS="1.1.1.1" WSL_APT_UPGRADE=0 ./install.sh --base --non-interactive' }
    @{ Shutdown=$true }
    @{ User='tester'; Command='cp -r /root/wsl-starter-script ~/wsl-starter-script && sudo chown -R tester:tester ~/wsl-starter-script' }
    @{ User='tester'; Command='cd ~/wsl-starter-script && MISE_LANGUAGES=node,python CLAUDE_PERMISSION_MODE=acceptEdits ZSH_DEFAULT_SHELL=0 ./install.sh --dev --claude --non-interactive' }
  ) `
  -GossFile 'tests/tier2-3/goss/dev.yaml' `
  -GossUser 'tester'
