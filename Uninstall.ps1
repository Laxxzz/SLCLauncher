<#
.SYNOPSIS
    Removes the ArchonLauncher scheduled task and stops the watcher.

.PARAMETER TaskName
    Scheduled task name. Default "ArchonLauncher".

.PARAMETER KeepFiles
    Leave %LOCALAPPDATA%\ArchonLauncher (script, settings and log) in place.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Uninstall.ps1
#>
[CmdletBinding()]
param(
    [string] $TaskName = 'ArchonLauncher',
    [switch] $KeepFiles
)

$ErrorActionPreference = 'Stop'

$installDir = Join-Path $env:LOCALAPPDATA 'ArchonLauncher'

Write-Host "Removing ArchonLauncher..." -ForegroundColor Cyan

# ------------------------------------------------------------ the task ------
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    try { Stop-ScheduledTask -TaskName $TaskName -ErrorAction Stop } catch {}
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "  task removed: $TaskName"
} else {
    Write-Host "  no scheduled task named '$TaskName'"
}

# ------------------------------------------------- any running watcher ------
$running = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
           Where-Object { ($_.CommandLine -like '*ArchonWatcher.ps1*' -or
                           $_.CommandLine -like '*ArchonLauncher.ps1*') -and $_.ProcessId -ne $PID }

if ($running) {
    foreach ($p in $running) {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host "  stopped watcher (pid $($p.ProcessId))"
    }
} else {
    Write-Host "  no watcher process running"
}

# -------------------------------------------------------- the settings app --
# An open settings window holds ArchonLauncher.exe, which would stop the
# folder being deleted -- and would go on offering settings for nothing.
Get-Process -Name 'ArchonLauncher' -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq (Join-Path $installDir 'ArchonLauncher.exe') } |
    ForEach-Object {
        Stop-Process -Id $_.Id -Force
        $null = $_.WaitForExit(5000)
        Write-Host "  closed the settings window (pid $($_.Id))"
    }

# Removed even with -KeepFiles: it opens settings for a watcher that no
# longer runs, so leaving it would only suggest the tool is still installed.
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Archon Launcher.lnk'
if (Test-Path $shortcut) {
    Remove-Item $shortcut -Force
    Write-Host "  Start menu shortcut removed"
}

# ------------------------------------------------------------- the files ----
if ($KeepFiles) {
    Write-Host "  files kept at $installDir"
} elseif (Test-Path $installDir) {
    Remove-Item $installDir -Recurse -Force
    Write-Host "  files removed: $installDir"
}

Write-Host ""
Write-Host "Done. The apps it started were not touched." -ForegroundColor Green
