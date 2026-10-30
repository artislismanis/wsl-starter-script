# Workbench opt-in + idempotence (run twice). Nothing but --workbench is asked
# for, so this also proves NEEDS pulls in dev, workflow and herdr.

& "$PSScriptRoot/../run-scenario.ps1" `
  -Name 'workbench' `
  -InstallSteps @(
    @{ User='root';   Command='WSL_USER=tester WSL_PASSWORD=testpass123 WSL_HOSTNAME=testbox WSL_DNS="1.1.1.1" WSL_APT_UPGRADE=0 ./install.sh --base --non-interactive' }
    @{ User='tester'; Command='cp -r /root/wsl-starter-script ~/wsl-starter-script && chown -R tester:tester ~/wsl-starter-script' }
    @{ User='tester'; Command='cd ~/wsl-starter-script && ./install.sh --workbench --non-interactive' }
    @{ User='tester'; Command='cd ~/wsl-starter-script && ./install.sh --workbench --non-interactive' }
  ) `
  -GossFile 'tests/tier2-3/goss/workbench.yaml' `
  -GossUser 'tester'
