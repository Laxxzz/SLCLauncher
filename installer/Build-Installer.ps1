<#
.SYNOPSIS
    Builds dist\SLCLauncher-Setup-<version>.exe from SLCLauncher.iss.

.DESCRIPTION
    Needs Inno Setup 6 on the machine that builds, and only there: the Setup.exe
    it makes is self-contained. Install it with

        winget install --id JRSoftware.InnoSetup -e --scope user

    The version comes from $SLCLauncherVersion in SLCWatcher.ps1, the same place
    Install.ps1 and ViewLog.cmd read it from, so the three cannot disagree.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\installer\Build-Installer.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$iss  = Join-Path $PSScriptRoot 'SLCLauncher.iss'

$iscc = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
    $onPath = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($onPath) { $iscc = $onPath.Source }
}
if (-not $iscc) {
    throw 'Inno Setup 6 (ISCC.exe) not found. Install it: winget install --id JRSoftware.InnoSetup -e --scope user'
}

$vMatch = Select-String -Path (Join-Path $root 'SLCWatcher.ps1') `
                        -Pattern "SLCLauncherVersion\s*=\s*'([^']+)'" | Select-Object -First 1
if (-not $vMatch) { throw 'no $SLCLauncherVersion found in SLCWatcher.ps1' }
$version = $vMatch.Matches[0].Groups[1].Value

Write-Host "Building SLCLauncher $version installer..." -ForegroundColor Cyan
& $iscc /Q "/DAppVersion=$version" $iss
if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE" }

$out = Join-Path $root "dist\SLCLauncher-Setup-$version.exe"
Write-Host "  built -> $out" -ForegroundColor Green
