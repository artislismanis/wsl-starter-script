# Scenario 11a sub — DOCKER_MODE=skip suppresses the 27-wsl-network auto-fire.

& "$PSScriptRoot/../run-scenario.ps1" `
  -Name 'docker-skip' `
  -InstallSteps @(
    @{ User='root'; Command='WSL_USER=tester WSL_PASSWORD=testpass123 WSL_HOSTNAME=testbox WSL_DNS="1.1.1.1" WSL_APT_UPGRADE=0 ./install.sh --base --non-interactive' }
    @{ Shutdown=$true }
    # Belt-and-braces: clear any prior 27 install before the skip run.
    @{ User='root'; Command='rm -f /etc/sysctl.d/99-wsl-network.conf /usr/local/bin/wsl-port-check' }
    @{ User='root'; Command='DOCKER_MODE=skip ./install.sh --docker --non-interactive | tee /tmp/out; grep -q "Docker install skipped" /tmp/out' }
  ) `
  -GossFile 'tests/tier2-3/goss/docker-skip.yaml' `
  -GossUser 'root'
