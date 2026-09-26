<#
.SYNOPSIS
    Installs SLC Launcher as a hidden logon scheduled task for the current user.

.DESCRIPTION
    Copies the watcher into %LOCALAPPDATA%\SLCLauncher, registers a scheduled
    task that starts it at logon, and starts it immediately. Also builds
    SLCLauncher.exe -- the settings app -- beside it and adds that to the
    Start menu as "SLC Launcher".

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
$shortcut   = Join-Path ([Environment]::GetFolderPath('Programs')) 'SLC Launcher.lnk'

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

Write-Host "Installing SLC Launcher $version..." -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $installDir | Out-Null

# ------------------------------------------- taking over Archon Launcher --
# Up to 1.5.0 this tool was Archon Launcher: installed in
# %LOCALAPPDATA%\ArchonLauncher, run by a task called ArchonLauncher, and in the
# Start menu under that name. Left in place it would go on watching for the
# game alongside this one and every app would be launched twice, so it is
# taken over: its settings and log come across, and then it is removed.
$legacyDir  = Join-Path $env:LOCALAPPDATA 'ArchonLauncher'
$legacyArgs = ''
$legacyTask = Get-ScheduledTask -TaskName 'ArchonLauncher' -ErrorAction SilentlyContinue
if ($legacyTask) {
    # Read before unregistering: up to 1.4.1 the installer's answers lived on
    # this command line, and they are migrated into config.json below.
    $legacyArgs = " $(@($legacyTask.Actions)[0].Arguments) "
    try { Stop-ScheduledTask -TaskName 'ArchonLauncher' -ErrorAction Stop } catch { }
    Unregister-ScheduledTask -TaskName 'ArchonLauncher' -Confirm:$false
    Write-Host "  removed -> the old ArchonLauncher task"
}

# Its watcher ran as ArchonWatcher.ps1 in 1.5.0 and ArchonLauncher.ps1 before.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { ($_.CommandLine -like '*ArchonWatcher.ps1*' -or
                    $_.CommandLine -like '*ArchonLauncher.ps1*') -and $_.ProcessId -ne $PID } |
    ForEach-Object {
        Write-Host "  stopping the old Archon Launcher watcher (pid $($_.ProcessId))"
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
Get-Process -Name 'ArchonLauncher' -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like "$legacyDir\*" } |
    ForEach-Object {
        Write-Host "  closing the old Archon Launcher window (pid $($_.Id))"
        Stop-Process -Id $_.Id -Force
        $null = $_.WaitForExit(5000)
    }

if (Test-Path $legacyDir) {
    # Only into an install that has none of its own yet, so running this
    # installer twice cannot overwrite newer settings with the old ones.
    foreach ($f in 'config.json', 'launcher.log', 'launcher.log.1') {
        $from = Join-Path $legacyDir $f
        $to   = Join-Path $installDir $f
        if ((Test-Path $from) -and -not (Test-Path $to)) { Copy-Item $from $to }
    }
    Remove-Item -LiteralPath $legacyDir -Recurse -Force
    Write-Host "  moved   -> settings and log from $legacyDir"
}

foreach ($name in 'Archon Launcher.lnk', 'Archon Launcher Options.lnk') {
    $old = Join-Path ([Environment]::GetFolderPath('Programs')) $name
    if (Test-Path $old) { Remove-Item -LiteralPath $old -Force }
}

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
#   3. switches baked into Archon Launcher 1.4.x's task (migrated, see below)
#   4. switches given to this install
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

# Up to 1.4.1 the installer's answers were switches on the old task's command
# line, where they outranked config.json. That task is gone and the new one
# has none, so carry them into the file -- otherwise an upgrade would quietly
# turn back on an app you had said no to.
$legacy = @{
    '-NoWowUp'      = @('LaunchWowUp',      $false)
    '-NoCurseForge' = @('LaunchCurseForge', $false)
    '-QuitWithWow'  = @('QuitWithWow',      $true)
}
foreach ($switch in $legacy.Keys) {
    if ($legacyArgs -like "* $switch *") { Set-Setting $legacy[$switch][0] $legacy[$switch][1] }
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
    $line = 'nothing yet - choose in SLC Launcher'
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
    -Description 'Runs the SLC Launcher watcher, which starts the World of Warcraft tools chosen in SLC Launcher when the game launches.' `
    -Force | Out-Null

Write-Host "  task    -> $TaskName (at logon, hidden, self-healing every ${HeartbeatMinutes}m)"

# --------------------------------------------------------- Start menu entry --
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($shortcut)
$lnk.TargetPath       = $appTarget
$lnk.WorkingDirectory = $installDir
$lnk.Description      = 'Choose what starts with World of Warcraft'
$lnk.Save()
Write-Host "  menu    -> Start menu, 'SLC Launcher'"

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
    Write-Host "Choose what starts with WoW in the SLC Launcher window that just opened." -ForegroundColor Cyan
    Write-Host "Open it again any time from the Start menu: SLC Launcher." -ForegroundColor Cyan
} else {
    Write-Host "Launch WoW to test. Change settings from the Start menu: SLC Launcher." -ForegroundColor Cyan
}

if ($LogPath) { Stop-Transcript | Out-Null }
