# Scenarios 3 + 4 — dev modules + idempotence. Tier 2 (no shutdown needed).

& "$PSScriptRoot/../run-scenario.ps1" `
  -Name 'dev' `
  -InstallSteps @(
    @{ User='root';   Command='WSL_USER=tester WSL_PASSWORD=testpass123 WSL_HOSTNAME=testbox WSL_DNS="1.1.1.1" WSL_APT_UPGRADE=0 ./install.sh --base --non-interactive' }
    @{ User='tester'; Command='cp -r /root/wsl-starter-script ~/wsl-starter-script && chown -R tester:tester ~/wsl-starter-script' }
    @{ User='tester'; Command='cd ~/wsl-starter-script && MISE_LANGUAGES=node,python ZSH_DEFAULT_SHELL=0 ./install.sh --dev --non-interactive' }
    @{ User='tester'; Command='cd ~/wsl-starter-script && MISE_LANGUAGES=node,python ZSH_DEFAULT_SHELL=0 ./install.sh --dev --non-interactive' }
  ) `
  -GossFile 'tests/tier2-3/goss/dev.yaml' `
  -GossUser 'tester'
