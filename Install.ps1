<#
.SYNOPSIS
    Installs SLCLauncher as a hidden logon scheduled task for the current user.

.DESCRIPTION
    Copies the watcher into %LOCALAPPDATA%\SLCLauncher, registers a scheduled
    task that starts it at logon, and starts it immediately. Also builds
    SLCLauncher.exe -- the settings app -- beside it and adds that to the
    Start menu as "SLCLauncher".

    No administrator rights are required -- the task runs as the current user
    only. Re-running this script safely overwrites a previous install, and keeps
    the settings already chosen in the settings app.

.PARAMETER TaskName
    Scheduled task name. Default "SLCLauncher".

.PARAMETER QuitWithWow
    Also close the apps when WoW exits.

.PARAMETER NoArchon
    Never start the Archon App, even when it is installed.

.PARAMETER NoWowUp
    Never start WowUp, even when it is installed.

.PARAMETER NoCurseForge
    Never start CurseForge, even when it is installed.

.PARAMETER NoRaiderIO
    Never start the Raider.IO client, even when it is installed.

.PARAMETER NoWowUtilsBridge
    Never start WowUtils Bridge, even when it is installed.

.PARAMETER OpenSettings
    Open the settings app once installed. Install.cmd passes this.

.PARAMETER HeartbeatMinutes
    How often Task Scheduler re-checks that the watcher is alive, restarting it
    if it isn't. Default 5.

.PARAMETER LogPath
    Also write everything this install prints to this file. The Setup.exe
    installer passes this, since it runs the install with no window to show
    the output in.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install.ps1
    powershell -ExecutionPolicy Bypass -File .\Install.ps1 -NoCurseForge
#>
[CmdletBinding()]
param(
    [string] $TaskName = 'SLCLauncher',
    [switch] $QuitWithWow,
    [switch] $NoArchon,
    [switch] $NoWowUp,
    [switch] $NoCurseForge,
    [switch] $NoRaiderIO,
    [switch] $NoWowUtilsBridge,
    [switch] $OpenSettings,
    [int]    $HeartbeatMinutes = 5,
    [string] $LogPath
)

$ErrorActionPreference = 'Stop'

# A transcript, unlike redirecting the output, also catches Write-Host, which
# is how everything below reports what it did.
if ($LogPath) { Start-Transcript -LiteralPath $LogPath -Force | Out-Null }

$installDir = Join-Path $env:LOCALAPPDATA 'SLCLauncher'
$source     = Join-Path $PSScriptRoot 'SLCWatcher.ps1'
$shimTarget = Join-Path $installDir 'RunHidden.vbs'
$cfgTarget  = Join-Path $installDir 'config.json'
$appSource  = Join-Path $PSScriptRoot 'SLCLauncher.cs'
$appTarget  = Join-Path $installDir 'SLCLauncher.exe'
$iconSource = Join-Path $PSScriptRoot 'SLCLauncher.ico'
$shortcut   = Join-Path ([Environment]::GetFolderPath('Programs')) 'SLCLauncher.lnk'

# The .cs files are compiled rather than copied, and the icon is both embedded
# in the program and copied beside it for the window to use.
$payload = @('SLCWatcher.ps1', 'RunHidden.vbs', 'SLCLauncherSettings.ps1', 'SLCLauncher.ico')
foreach ($f in ($payload + 'SLCLauncher.cs', 'SLCTheme.cs')) {
    if (-not (Test-Path (Join-Path $PSScriptRoot $f))) {
        throw "$f not found next to this installer ($PSScriptRoot)"
    }
}

$version = 'unknown'
$vMatch = Select-String -Path $source -Pattern "SLCLauncherVersion\s*=\s*'([^']+)'" |
          Select-Object -First 1
if ($vMatch) { $version = $vMatch.Matches[0].Groups[1].Value }

Write-Host "Installing SLCLauncher $version..." -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $installDir | Out-Null

# Up to 2.0.0 the Start menu entry was "SLC Launcher", with a space. An update
# would otherwise leave it beside the new one.
$oldShortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'SLC Launcher.lnk'
if (Test-Path $oldShortcut) { Remove-Item -LiteralPath $oldShortcut -Force }

# ------------------------------------------------------------ copy payload --
# An open settings window holds SLCLauncher.exe open, and the build below
# has to replace it. Close it rather than fail halfway through an install.
Get-Process -Name 'SLCLauncher' -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq $appTarget } |
    ForEach-Object {
        Write-Host "  closing the open settings window (pid $($_.Id))"
        Stop-Process -Id $_.Id -Force
        $null = $_.WaitForExit(5000)
    }

foreach ($f in $payload) {
    Copy-Item (Join-Path $PSScriptRoot $f) (Join-Path $installDir $f) -Force
}

# Troubleshooting help, so it is where the README says whichever way this was
# installed. Setup puts it there itself and does not pass it here.
$viewLog = Join-Path $PSScriptRoot 'ViewLog.cmd'
if (Test-Path $viewLog) { Copy-Item $viewLog (Join-Path $installDir 'ViewLog.cmd') -Force }
Write-Host "  files   -> $installDir"

# ------------------------------------------------------------- settings app --
# Built here rather than shipped: a compiled program downloaded from the
# internet is exactly what SmartScreen and antivirus look hardest at, while
# one built on this machine from the .cs file beside this installer is plainly
# what it says it is. The compiler is part of the .NET Framework that every
# copy of Windows 10 and 11 includes.
# Indexed rather than Select-Object -First 1, which stops the pipeline early:
# harmless, but a -LogPath transcript records it as a TerminatingError.
$csc = @(@('Framework64', 'Framework') |
         ForEach-Object { Join-Path $env:WINDIR "Microsoft.NET\$_\v4.0.30319\csc.exe" } |
         Where-Object { Test-Path $_ })[0]
if (-not $csc) {
    throw 'cannot build SLCLauncher.exe: the .NET Framework 4 compiler (csc.exe) was not found'
}

# Compiled against the PowerShell this machine actually has, since the settings
# window runs inside the program.
$sma = [System.Management.Automation.PSObject].Assembly.Location
$cscOut = & $csc /nologo /target:winexe /optimize+ "/out:$appTarget" "/win32icon:$iconSource" `
              "/reference:$sma" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll `
              $appSource (Join-Path $PSScriptRoot 'SLCTheme.cs') 2>&1
if ($LASTEXITCODE -ne 0) {
    $cscOut | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
    throw "building SLCLauncher.exe failed (csc exit code $LASTEXITCODE)"
}
Write-Host "  app     -> $appTarget"

# ---------------------------------------------------------------- settings --
# The installed config.json is where the settings app keeps your choices, so
# a reinstall edits it rather than replacing it: anything set there survives,
# and only what this install actually says overrides it. In order:
#
#   1. the installed config.json, as the settings app last left it
#   2. a config.json next to this installer, key by key
#   3. switches given to this install
function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try {
        return (Get-Content $Path -Raw | ConvertFrom-Json)
    } catch {
        Write-Host "  ignoring unreadable $Path" -ForegroundColor Yellow
        return $null
    }
}

$config = Read-JsonFile $cfgTarget
if (-not $config) { $config = New-Object PSObject }

function Set-Setting {
    param([string]$Name, $Value)
    $config | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

$srcCfg  = Join-Path $PSScriptRoot 'config.json'
$fromSrc = Read-JsonFile $srcCfg
if ($fromSrc) {
    foreach ($p in $fromSrc.PSObject.Properties) { Set-Setting $p.Name $p.Value }
    Write-Host "  applied -> settings from $srcCfg"
}

if ($QuitWithWow)      { Set-Setting 'QuitWithWow'          $true }
if ($NoWowUp)          { Set-Setting 'LaunchWowUp'          $false }
if ($NoArchon)         { Set-Setting 'LaunchArchon'         $false }
if ($NoCurseForge)     { Set-Setting 'LaunchCurseForge'     $false }
if ($NoRaiderIO)       { Set-Setting 'LaunchRaiderIO'       $false }
if ($NoWowUtilsBridge) { Set-Setting 'LaunchWowUtilsBridge' $false }

[System.IO.File]::WriteAllText($cfgTarget, (ConvertTo-Json -InputObject $config -Depth 5),
                               (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  config  -> $cfgTarget"

# ------------------------------------------------------ what will be started --
# Report the outcome from the file just written, read the way the watcher reads
# it, so this line cannot disagree with what actually happens.
function Test-On {
    param($Value, [bool]$Default)
    if ($null -eq $Value -or "$Value" -eq '') { return $Default }
    if ($Value -is [bool]) { return $Value }
    return (@('1', 'true', 'yes', 'on') -contains "$Value".Trim().ToLowerInvariant())
}

$chosen = @()
foreach ($a in @(@('Archon', 'LaunchArchon'), @('WowUp', 'LaunchWowUp'),
                 @('CurseForge', 'LaunchCurseForge'), @('Raider.IO', 'LaunchRaiderIO'),
                 @('WowUtils Bridge', 'LaunchWowUtilsBridge'))) {
    if (Test-On $config.($a[1]) $true) { $chosen += $a[0] }
}
$ownCount = @($config.CustomApps | Where-Object {
    $_ -and "$($_.Path)".Trim() -and (Test-On $_.Enabled $true)
}).Count
if ($ownCount -eq 1)     { $chosen += '1 program of your own' }
elseif ($ownCount -gt 1) { $chosen += "$ownCount programs of your own" }

if ($chosen.Count -eq 0) {
    $line = 'nothing yet - choose in SLCLauncher'
} elseif ($chosen.Count -eq 1) {
    $line = "$($chosen[0]), if installed"
} else {
    $line = ($chosen[0..($chosen.Count - 2)] -join ', ') + " and $($chosen[-1]), if installed"
}
Write-Host "  starts  -> $line"
if (Test-On $config.QuitWithWow $false) { Write-Host '  closes  -> all of them when WoW closes' }

# --------------------------------------------------- stop any running copy --
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*SLCWatcher.ps1*' -and $_.ProcessId -ne $PID } |
    ForEach-Object {
        Write-Host "  stopping running watcher (pid $($_.ProcessId))"
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }

# -------------------------------------------------------- register the task --
# Launch through the VBS shim rather than powershell.exe directly: Task
# Scheduler gives a console-subsystem process a console window every time it
# fires, which flashes on screen. wscript.exe starts PowerShell with no window
# at all. See the comments in RunHidden.vbs.
#
# No switches follow the shim any more. Every setting lives in config.json,
# which the settings app edits and the watcher rereads when it changes; a
# switch here would outrank the file and silently undo whatever was chosen there.
$wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'

$action = New-ScheduledTaskAction -Execute $wscript -Argument "`"$shimTarget`""

# Two triggers, deliberately.
#
# Task Scheduler's "restart on failure" only covers a task that fails to START,
# not one whose process is killed later. Without a heartbeat, anything that
# terminates the watcher (a manual kill, a reinstall, an overzealous security
# tool) leaves it dead until the next logon -- silently.
#
# Attaching repetition to the logon trigger does NOT work: it only repeats
# within that trigger's own window and will not revive a task mid-session.
# An independent Once trigger with its own repetition does. MultipleInstances
# is IgnoreNew, so a heartbeat that fires while the watcher is healthy is a
# no-op.
$triggers = @(
    (New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"),
    (New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes $HeartbeatMinutes))
)

$principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Limited

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -Hidden

# The watcher is a long-running loop; without this the task is killed after 72h.
$settings.ExecutionTimeLimit = 'PT0S'

Register-ScheduledTask `
    -TaskName    $TaskName `
    -Action      $action `
    -Trigger     $triggers `
    -Principal   $principal `
    -Settings    $settings `
    -Description 'Runs the SLCLauncher watcher, which starts the World of Warcraft tools chosen in SLCLauncher when the game launches.' `
    -Force | Out-Null

Write-Host "  task    -> $TaskName (at logon, hidden, self-healing every ${HeartbeatMinutes}m)"

# --------------------------------------------------------- Start menu entry --
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($shortcut)
$lnk.TargetPath       = $appTarget
$lnk.WorkingDirectory = $installDir
$lnk.Description      = 'Choose what starts with World of Warcraft'
$lnk.Save()
Write-Host "  menu    -> Start menu, 'SLCLauncher'"

Start-ScheduledTask -TaskName $TaskName

# The shim exits as soon as it has spawned PowerShell, so the task returns to
# Ready immediately and its state says nothing about health. Check for the
# watcher process itself.
$watcher = $null
foreach ($attempt in 1..10) {
    Start-Sleep -Milliseconds 700
    $watcher = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
               Where-Object { $_.CommandLine -like '*SLCWatcher.ps1*' } |
               Select-Object -First 1
    if ($watcher) { break }
}

Write-Host ""
if ($watcher) {
    Write-Host "Installed and running." -ForegroundColor Green
    Write-Host "  watcher  : pid $($watcher.ProcessId)"
} else {
    Write-Host "Installed, but the watcher did not start." -ForegroundColor Yellow
    Write-Host "  check $installDir\launcher.log, then run this installer again."
}
Write-Host "  log      : $installDir\launcher.log"
Write-Host ""

if ($OpenSettings) {
    Start-Process -FilePath $appTarget
    Write-Host "Choose what starts with WoW in the SLCLauncher window that just opened." -ForegroundColor Cyan
    Write-Host "Open it again any time from the Start menu: SLCLauncher." -ForegroundColor Cyan
} else {
    Write-Host "Launch WoW to test. Change settings from the Start menu: SLCLauncher." -ForegroundColor Cyan
}

if ($LogPath) { Stop-Transcript | Out-Null }
