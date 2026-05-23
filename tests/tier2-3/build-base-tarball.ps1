<#
.SYNOPSIS
  One-time builder for tests/fixtures/base.tar.

.DESCRIPTION
  Imports the canonical Ubuntu-24.04 image and exports its rootfs to a tarball
  the scenario driver re-imports for each test run. ~30s vs ~3min for a real
  `wsl --install`, and pins the image we test against.

  In CI this script is replaced by actions/cache restoring a previously-built
  tarball — re-running is only needed when bumping the base image.
#>

[CmdletBinding()]
param(
  [string]$Distro = 'Ubuntu-24.04',
  [string]$Out = 'tests/fixtures/base.tar'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
$outAbs   = Join-Path $repoRoot $Out

if (Test-Path $outAbs) {
  Write-Host "Tarball already exists at $outAbs — delete it to rebuild." -ForegroundColor Yellow
  exit 0
}

$tmpName = "wsl-starter-base-$(Get-Random -Maximum 99999)"
$tmpDir  = Join-Path $env:TEMP $tmpName

Write-Host "Installing $Distro as $tmpName..." -ForegroundColor Cyan
# --no-launch keeps it offline; we only need it long enough to export.
& wsl --install -d $Distro --name $tmpName --no-launch
if ($LASTEXITCODE -ne 0) { throw "wsl --install failed" }

try {
  New-Item -ItemType Directory -Force -Path (Split-Path $outAbs) | Out-Null
  Write-Host "Exporting rootfs to $outAbs..." -ForegroundColor Cyan
  & wsl --export $tmpName $outAbs
  if ($LASTEXITCODE -ne 0) { throw "wsl --export failed" }
}
finally {
  & wsl --unregister $tmpName 2>$null | Out-Null
  Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
}

Write-Host "Wrote $outAbs ($([Math]::Round((Get-Item $outAbs).Length / 1MB)) MB)" -ForegroundColor Green
