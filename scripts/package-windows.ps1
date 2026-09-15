<#
.SYNOPSIS
  Packages the Windows release build for distribution: a portable .zip, and a
  setup .exe when Inno Setup is installed.

.DESCRIPTION
  Run this on a Windows machine with the Flutter Windows toolchain (Visual
  Studio with "Desktop development with C++"). Flutter cannot cross-compile the
  Windows target from Linux, so this is the one release artifact that isn't
  produced by scripts/release.sh — build it here, copy the files into the
  repo's dist\ folder on the release machine, and release.sh will attach
  whatever it finds there for the current version to the GitHub release.

  Output (dist\ by default):
    streamio-<version>-windows-x64.zip         portable, unzip and run
    streamio-<version>-windows-x64-setup.exe   installer (needs Inno Setup 6)

.PARAMETER SkipBuild
  Reuse the existing build\windows\x64\runner\Release folder.

.PARAMETER NoInstaller
  Only produce the .zip, even if Inno Setup is available.

.PARAMETER OutDir
  Output directory, relative to the repo root unless absolute. Default: dist

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\package-windows.ps1
#>
[CmdletBinding()]
param(
  [switch]$SkipBuild,
  [switch]$NoInstaller,
  [string]$OutDir = 'dist'
)

$ErrorActionPreference = 'Stop'

function Die([string]$msg) {
  Write-Host "error: $msg" -ForegroundColor Red
  exit 1
}

# Repo root is the parent of scripts\.
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

if (-not (Test-Path 'pubspec.yaml')) { Die "pubspec.yaml not found — expected to run from the app checkout." }

$versionLine = (Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(.+)$' | Select-Object -First 1)
if (-not $versionLine) { Die "couldn't find a 'version:' line in pubspec.yaml." }
$fullVersion = $versionLine.Matches[0].Groups[1].Value.Trim()
$semver = ($fullVersion -split '\+')[0]
$buildNumber = if ($fullVersion -match '\+') { ($fullVersion -split '\+')[1] } else { '0' }

Write-Host "Streamio $semver (build $buildNumber)" -ForegroundColor Cyan

$releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'

if (-not $SkipBuild) {
  if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Die "'flutter' is required but not found in PATH."
  }
  Write-Host 'Building Windows release...'
  # See scripts/release.sh for what STREAMIO_PROXY_HOSTS is; empty is fine.
  $buildArgs = @('build', 'windows', '--release')
  if ($env:STREAMIO_PROXY_HOSTS) {
    $buildArgs += "--dart-define=STREAMIO_PROXY_HOSTS=$($env:STREAMIO_PROXY_HOSTS)"
  }
  & flutter @buildArgs
  if ($LASTEXITCODE -ne 0) { Die "flutter build windows failed." }
}

$exePath = Join-Path $releaseDir 'streamio.exe'
if (-not (Test-Path $exePath)) { Die "'$exePath' missing — run without -SkipBuild." }

if (-not [System.IO.Path]::IsPathRooted($OutDir)) { $OutDir = Join-Path $repoRoot $OutDir }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# ── portable zip ────────────────────────────────────────────────
$pkgName = "streamio-$semver-windows-x64"
$stageRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("streamio-pkg-" + [System.Guid]::NewGuid().ToString('N'))
$stage = Join-Path $stageRoot $pkgName
New-Item -ItemType Directory -Force -Path $stage | Out-Null

try {
  Copy-Item -Path (Join-Path $releaseDir '*') -Destination $stage -Recurse -Force

  $readme = @"
Streamio $semver (build $buildNumber) - Windows x64

Portable build: no installation needed. Keep these files together in one
folder - streamio.exe needs the DLLs and the data\ folder next to it - and
run streamio.exe.

Windows SmartScreen may warn that the publisher is unknown, because this
build is not code-signed. "More info" -> "Run anyway".

You will be asked for your Streamio server address the first time you run it.

Requires 64-bit Windows 10 or later.
"@
  Set-Content -Path (Join-Path $stage 'README.txt') -Value $readme -Encoding UTF8

  $zipPath = Join-Path $OutDir "$pkgName.zip"
  if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
  Compress-Archive -Path $stage -DestinationPath $zipPath -CompressionLevel Optimal
  $zipSize = '{0:N1} MB' -f ((Get-Item $zipPath).Length / 1MB)
  Write-Host "Wrote $zipPath ($zipSize)" -ForegroundColor Green

  # ── installer ─────────────────────────────────────────────────
  if (-not $NoInstaller) {
    $isccCmd = Get-Command iscc -ErrorAction SilentlyContinue
    $iscc = if ($isccCmd) { $isccCmd.Source } else { $null }
    if (-not $iscc) {
      $candidates = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
      )
      $iscc = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    }

    if (-not $iscc) {
      Write-Host "Skipping installer - Inno Setup (ISCC.exe) not found." -ForegroundColor Yellow
      Write-Host "  Install it with 'winget install JRSoftware.InnoSetup' and re-run." -ForegroundColor Yellow
    } else {
      $iss = Join-Path $repoRoot 'scripts\packaging\windows\streamio.iss'
      $iconFile = Join-Path $repoRoot 'windows\runner\resources\app_icon.ico'
      $isccArgs = @(
        "/DAppVersion=$semver",
        "/DSourceDir=$releaseDir",
        "/DOutputDir=$OutDir",
        "/DOutputName=$pkgName-setup"
      )
      if (Test-Path $iconFile) { $isccArgs += "/DIconFile=$iconFile" }
      $isccArgs += $iss

      Write-Host 'Building installer...'
      & $iscc @isccArgs | Out-Null
      if ($LASTEXITCODE -ne 0) { Die "Inno Setup failed (exit $LASTEXITCODE)." }

      $setupPath = Join-Path $OutDir "$pkgName-setup.exe"
      if (-not (Test-Path $setupPath)) { Die "Inno Setup reported success but $setupPath is missing." }
      $setupSize = '{0:N1} MB' -f ((Get-Item $setupPath).Length / 1MB)
      Write-Host "Wrote $setupPath ($setupSize)" -ForegroundColor Green
    }
  }
} finally {
  if (Test-Path $stageRoot) { Remove-Item $stageRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host 'Done. Copy the files from dist\ to the machine that runs scripts/release.sh' -ForegroundColor Cyan
Write-Host 'so they get attached to the GitHub release.' -ForegroundColor Cyan
