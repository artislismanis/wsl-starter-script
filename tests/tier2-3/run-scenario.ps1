<#
.SYNOPSIS
  Lifecycle driver for a single Tier 2/3 scenario.

.DESCRIPTION
  Imports a fresh Ubuntu rootfs to a uniquely-named WSL distro, copies the
  repo into the distro, executes user-supplied install + verify steps, and
  unregisters the distro at the end (always, even on failure).

  Designed to be called by per-scenario scripts under tests/tier2-3/scenarios/.

.PARAMETER Name
  Scenario name. Used to derive the distro name and label log output.

.PARAMETER InstallSteps
  Hashtable[] of { User; Command } or { Shutdown=$true }. Command steps run
  `wsl -d <distro> -u <user> -- bash -lc <command>`. A Shutdown step runs
  `wsl --terminate <distro>` (forces a systemd reboot mid-flow — needed
  between --base and --docker so [boot] systemd=true takes effect).

.PARAMETER GossFile
  Optional path (relative to repo root) of the goss yaml to validate after
  install steps. If omitted, no goss validation runs.

.PARAMETER GossUser
  Which user inside the distro runs `goss validate`. Default: tester.

.PARAMETER GossEnv
  Hashtable of env vars to export before goss validate (e.g. TEST_USER, TEST_HOST).

.PARAMETER Tarball
  Path to the Ubuntu rootfs tarball. Default: tests/fixtures/base.tar.

.PARAMETER ShutdownBeforeVerify
  If $true, runs `wsl --terminate <distro>` between install and verify steps.
  Use this for Tier 3 (reopen-as-user) scenarios.

.PARAMETER KeepDistroOnFailure
  If $true, leave the distro registered on failure for post-mortem.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Name,
  [Parameter(Mandatory=$true)][hashtable[]]$InstallSteps,
  [string]$GossFile,
  [string]$GossUser = 'tester',
  [hashtable]$GossEnv = @{},
  [string]$Tarball = 'tests/fixtures/base.tar',
  [switch]$ShutdownBeforeVerify,
  [switch]$KeepDistroOnFailure
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
$distro   = "wsl-starter-test-$Name-$(Get-Random -Maximum 99999)"
$rootfs   = Join-Path $repoRoot $Tarball
$instDir  = Join-Path $env:TEMP "wsl-$distro"

function Write-Step($msg) { Write-Host "==> [$Name] $msg" -ForegroundColor Cyan }
function Fail($msg)       { Write-Host "FAIL [$Name] $msg" -ForegroundColor Red; exit 1 }

if (-not (Test-Path $rootfs)) {
  Fail "Rootfs tarball not found: $rootfs. Run 'pwsh tests/tier2-3/build-base-tarball.ps1' first."
}

Write-Step "Importing $distro from $rootfs"
New-Item -ItemType Directory -Force -Path $instDir | Out-Null
& wsl --import $distro $instDir $rootfs --version 2
if ($LASTEXITCODE -ne 0) { Fail "wsl --import failed" }

# Always unregister on exit, unless KeepDistroOnFailure asked otherwise.
$script:keep = $false
trap {
  if (-not $script:keep) {
    Write-Step "Cleaning up $distro"
    & wsl --unregister $distro 2>$null | Out-Null
    Remove-Item -Recurse -Force $instDir -ErrorAction SilentlyContinue
  } else {
    Write-Host "Leaving $distro registered for inspection (KeepDistroOnFailure)" -ForegroundColor Yellow
  }
  break
}

try {
  # Seed the repo into the distro via a tar pipe — more robust than relying on
  # /mnt/c automounts working in a freshly-imported distro.
  Write-Step "Seeding repo into distro"
  $linuxRepo = '/root/wsl-starter-script'
  $tarTmp    = Join-Path $env:TEMP "wsl-starter-$([guid]::NewGuid()).tar"
  Push-Location $repoRoot
  & tar --exclude-vcs --exclude='./tests/fixtures/base.tar' -cf $tarTmp .
  Pop-Location
  & wsl -d $distro -u root -- bash -lc "mkdir -p $linuxRepo"
  Get-Content -Raw -AsByteStream $tarTmp | & wsl -d $distro -u root -- bash -lc "cat > /tmp/repo.tar"
  & wsl -d $distro -u root -- bash -lc "tar -xf /tmp/repo.tar -C $linuxRepo && rm /tmp/repo.tar"
  Remove-Item $tarTmp -ErrorAction SilentlyContinue

  # tar from a Windows host doesn't preserve Unix exec bits (NTFS + Git for
  # Windows defaults), so re-set +x on all shell scripts and hook helpers.
  & wsl -d $distro -u root -- bash -lc @"
set -e
cd $linuxRepo
find . -type f \( -name '*.sh' -o -path './.githooks/*' \) -exec chmod +x {} +
"@

  foreach ($step in $InstallSteps) {
    if ($step.Shutdown) {
      Write-Step "wsl --terminate $distro (mid-install)"
      & wsl --terminate $distro
      Start-Sleep -Seconds 2
      continue
    }
    $u   = $step.User
    $cmd = $step.Command
    Write-Step "[$u] $cmd"
    & wsl -d $distro -u $u -- bash -lc "cd $linuxRepo && $cmd"
    if ($LASTEXITCODE -ne 0) {
      $script:keep = $KeepDistroOnFailure.IsPresent
      Fail "install step failed (user=$u): $cmd"
    }
  }

  if ($ShutdownBeforeVerify) {
    Write-Step "wsl --terminate $distro (Tier 3 round-trip)"
    & wsl --terminate $distro
    Start-Sleep -Seconds 2
  }

  if ($GossFile) {
    $gossPath = "$linuxRepo/$GossFile"
    Write-Step "Validating against $GossFile (as $GossUser)"

    # Ensure goss is installed inside the distro. Cheap and idempotent.
    & wsl -d $distro -u root -- bash -lc @'
if ! command -v goss >/dev/null 2>&1; then
  curl -fsSL https://goss.rocks/install | sh
fi
'@
    if ($LASTEXITCODE -ne 0) { $script:keep = $KeepDistroOnFailure.IsPresent; Fail "goss install failed" }

    $envExports = ($GossEnv.GetEnumerator() | ForEach-Object { "export $($_.Key)=$($_.Value);" }) -join ' '
    & wsl -d $distro -u $GossUser -- bash -lc "$envExports goss -g $gossPath validate --format documentation"
    if ($LASTEXITCODE -ne 0) {
      $script:keep = $KeepDistroOnFailure.IsPresent
      Fail "goss validate failed"
    }
  }

  Write-Step "PASS"
}
finally {
  if (-not $script:keep) {
    & wsl --unregister $distro 2>$null | Out-Null
    Remove-Item -Recurse -Force $instDir -ErrorAction SilentlyContinue
  }
}
