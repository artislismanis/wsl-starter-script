# Scenario 11a — Docker. Needs systemd, which means a
# mid-install `wsl --terminate` after --base so [boot] systemd=true takes
# effect before --docker runs.

& "$PSScriptRoot/../run-scenario.ps1" `
  -Name 'docker' `
  -InstallSteps @(
    @{ User='root';   Command='WSL_USER=tester WSL_PASSWORD=testpass123 WSL_HOSTNAME=testbox WSL_DNS="1.1.1.1" WSL_APT_UPGRADE=0 ./install.sh --base --non-interactive' }
    @{ Shutdown=$true }
    @{ User='tester'; Command='cp -r /root/wsl-starter-script ~/wsl-starter-script && sudo chown -R tester:tester ~/wsl-starter-script' }
    @{ User='tester'; Command='cd ~/wsl-starter-script && sudo -n DOCKER_MODE=classic ./install.sh --docker --non-interactive' }
    # Idempotence re-run.
    @{ User='tester'; Command='cd ~/wsl-starter-script && sudo -n DOCKER_MODE=classic ./install.sh --docker --non-interactive' }
  ) `
  -GossFile 'tests/tier2-3/goss/docker.yaml' `
  -GossUser 'tester'
