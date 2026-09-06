<#
.SYNOPSIS
    Starts the Archon App -- and optionally WowUp and CurseForge -- when World
    of Warcraft launches.

.DESCRIPTION
    Archon's built-in "launch with game" setting only opens the window of an
    already-running instance -- there is no resident component to cold-start it.
    This watcher fills that gap: it polls for the WoW process and starts Archon
    when it appears.

    The same gap applies to the addon managers, which have no launch-with-game
    feature at all, so the watcher can start WowUp and CurseForge alongside
    Archon. Each is launched only if it is installed and not already running;
    one that is not installed is simply skipped.

    Settings are read from config.json next to this script, if present.
    Command-line parameters override config.json, which overrides the defaults.

.PARAMETER ArchonExe
    Full path to "Archon App.exe". Auto-detected if omitted.

.PARAMETER WowUpExe
    Full path to "WowUp-CF.exe" or "WowUp.exe". Auto-detected if omitted.

.PARAMETER CurseForgeExe
    Full path to "CurseForge.exe". Auto-detected if omitted.

.PARAMETER NoWowUp
    Never start WowUp, even when it is installed.

.PARAMETER NoCurseForge
    Never start CurseForge, even when it is installed.

.PARAMETER GamePattern
    Regex matched against process names (no .exe). Default covers retail,
    Classic, PTR and beta.

.PARAMETER PollSeconds
    Seconds between checks. Default 1.

.PARAMETER LaunchDelaySeconds
    Seconds to wait after spotting the game before starting the apps. Default 3.
    Set to 0 to launch immediately.

.PARAMETER QuitWithWow
    Also close the apps when WoW exits.

.EXAMPLE
    .\ArchonLauncher.ps1
    .\ArchonLauncher.ps1 -GamePattern '^Wow$' -QuitWithWow
    .\ArchonLauncher.ps1 -NoCurseForge
#>
[CmdletBinding()]
param(
    [string] $ArchonExe,
    [string] $WowUpExe,
    [string] $CurseForgeExe,
    [switch] $NoWowUp,
    [switch] $NoCurseForge,
    [string] $GamePattern,
    [int]    $PollSeconds,
    [int]    $LaunchDelaySeconds = -1,
    [switch] $QuitWithWow
)

$ErrorActionPreference = 'Stop'

# The single source of truth for the version. Install.ps1 and ViewLog.cmd read
# it back out of this file rather than keeping copies that can drift.
$ArchonLauncherVersion = '1.4.0'

# ------------------------------------------------------------- single copy --
# Only one watcher may run at a time. The task starts this script from both a
# logon trigger and a repeating heartbeat, and the launcher shim means the task
# itself does not stay resident to block duplicates. Whoever creates the mutex
# owns the job; later starts exit silently rather than stacking up extra
# pollers and spamming the log.
$createdNew = $false
$script:SingletonMutex = New-Object System.Threading.Mutex(
    $true, 'Local\ArchonLauncherWatcher', [ref]$createdNew)
if (-not $createdNew) { exit 0 }

# ---------------------------------------------------------------- defaults --
$cfg = @{
    ArchonExe          = ''
    WowUpExe           = ''
    CurseForgeExe      = ''
    LaunchWowUp        = $true
    LaunchCurseForge   = $true
    GamePattern        = '^Wow(Classic|T|B)?$'
    PollSeconds        = 1
    LaunchDelaySeconds = 3
    QuitWithWow        = $false
    LogFile            = Join-Path $env:LOCALAPPDATA 'ArchonLauncher\launcher.log'
    MaxLogBytes        = 1MB
}

# ------------------------------------------------------------- config.json --
$configPath = Join-Path $PSScriptRoot 'config.json'
if (Test-Path $configPath) {
    try {
        $fromFile = Get-Content $configPath -Raw | ConvertFrom-Json
        foreach ($p in $fromFile.PSObject.Properties) {
            if ($cfg.ContainsKey($p.Name) -and $null -ne $p.Value -and "$($p.Value)" -ne '') {
                $cfg[$p.Name] = $p.Value
            }
        }
    } catch {
        # A malformed config must not stop the watcher from running.
        Write-Warning "ignoring unreadable config.json: $_"
    }
}

# ------------------------------------------------- parameter overrides ------
if ($PSBoundParameters.ContainsKey('ArchonExe'))     { $cfg.ArchonExe     = $ArchonExe }
if ($PSBoundParameters.ContainsKey('WowUpExe'))      { $cfg.WowUpExe      = $WowUpExe }
if ($PSBoundParameters.ContainsKey('CurseForgeExe')) { $cfg.CurseForgeExe = $CurseForgeExe }
if ($PSBoundParameters.ContainsKey('GamePattern'))   { $cfg.GamePattern   = $GamePattern }
if ($PSBoundParameters.ContainsKey('PollSeconds'))   { $cfg.PollSeconds   = $PollSeconds }
if ($LaunchDelaySeconds -ge 0)                       { $cfg.LaunchDelaySeconds = $LaunchDelaySeconds }
if ($QuitWithWow)                                    { $cfg.QuitWithWow      = $true }
if ($NoWowUp)                                        { $cfg.LaunchWowUp      = $false }
if ($NoCurseForge)                                   { $cfg.LaunchCurseForge = $false }

# ------------------------------------------------------------ sanity check --
# Start-Sleep -Seconds 0 returns instantly, which would spin a core at 100%.
# A negative value throws outright. Clamp both rather than trusting the file.
if ($cfg.PollSeconds        -lt 1) { $cfg.PollSeconds        = 1 }
if ($cfg.LaunchDelaySeconds -lt 0) { $cfg.LaunchDelaySeconds = 0 }

function ConvertTo-Bool {
    # JSON gives real booleans, but a hand-edited config can just as easily say
    # "false" as a string -- and every non-empty string is truthy in PowerShell,
    # so a plain cast would turn every attempt to switch something off into
    # switching it on. Read the word rather than the type.
    param($Value)
    if ($Value -is [bool]) { return $Value }
    return (@('1', 'true', 'yes', 'on') -contains "$Value".Trim().ToLowerInvariant())
}

$cfg.QuitWithWow      = ConvertTo-Bool $cfg.QuitWithWow
$cfg.LaunchWowUp      = ConvertTo-Bool $cfg.LaunchWowUp
$cfg.LaunchCurseForge = ConvertTo-Bool $cfg.LaunchCurseForge

New-Item -ItemType Directory -Force -Path (Split-Path $cfg.LogFile) | Out-Null

# ------------------------------------------------------------------- utils --
function Write-Log {
    param([string]$Message)
    $line = "[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $Message
    Write-Verbose $line
    try {
        $item = Get-Item $cfg.LogFile -ErrorAction SilentlyContinue
        if ($item -and $item.Length -gt $cfg.MaxLogBytes) {
            Move-Item $cfg.LogFile "$($cfg.LogFile).1" -Force
        }
        Add-Content -Path $cfg.LogFile -Value $line -Encoding utf8
    } catch {
        # Never let logging failures kill the loop.
    }
}

# -------------------------------------------------------------- companions --
# Archon, WowUp and CurseForge are all electron-builder installs and describe
# themselves identically in the uninstall registry -- empty InstallLocation, a
# "<exe>,0" DisplayIcon -- so one resolver serves all three. A companion is a
# plain record: how to find it, how to recognise its process, and, once
# resolved, where it actually is.
function New-Companion {
    param(
        [string]   $Name,
        [string[]] $ExeNames,
        [string]   $RegistryPattern,
        [string]   $ProcessPrefix,
        [string[]] $Fallbacks,
        [string]   $Configured,
        [bool]     $Required
    )
    @{
        Name            = $Name
        ExeNames        = $ExeNames
        RegistryPattern = $RegistryPattern
        ProcessPrefix   = $ProcessPrefix
        Fallbacks       = @($Fallbacks | Where-Object { $_ })
        Configured      = $Configured
        Required        = $Required
        Exe             = $null
        Pattern         = $null
    }
}

function Get-CompanionFromRegistry {
    param([hashtable]$App)

    $keys = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($k in $keys) {
        $entries = Get-ItemProperty $k -ErrorAction SilentlyContinue |
                   Where-Object { $_.DisplayName -match $App.RegistryPattern }

        foreach ($e in $entries) {
            # Cleanest source, but all three ship this empty.
            if ($e.InstallLocation) {
                foreach ($n in $App.ExeNames) {
                    $c = Join-Path $e.InstallLocation $n
                    if (Test-Path $c) { return $c }
                }
            }
            # DisplayIcon is the executable followed by an icon index: "...\x.exe,0"
            if ($e.DisplayIcon) {
                $c = ($e.DisplayIcon -replace ',\s*\d+\s*$', '').Trim('"', ' ')
                if ($c -and $c -match '\.exe$' -and (Test-Path $c)) {
                    # Prefer the app's own executable if the icon happens to name
                    # something else in the same folder, such as an uninstaller.
                    if ($App.ExeNames -contains (Split-Path $c -Leaf)) { return $c }
                    $dir = Split-Path $c -Parent
                    foreach ($n in $App.ExeNames) {
                        $sibling = Join-Path $dir $n
                        if (Test-Path $sibling) { return $sibling }
                    }
                    return $c
                }
            }
            # UninstallString sits in the install directory alongside the app.
            if ($e.UninstallString) {
                $u = $e.UninstallString
                if ($u -match '^\s*"([^"]+)"') { $u = $matches[1] }
                else { $u = ($u -split '\s+/')[0].Trim() }
                if ($u) {
                    $dir = Split-Path $u -Parent
                    if ($dir) {
                        foreach ($n in $App.ExeNames) {
                            $c = Join-Path $dir $n
                            if (Test-Path $c) { return $c }
                        }
                    }
                }
            }
        }
    }
    return $null
}

function Get-CompanionFromRunningProcess {
    param([hashtable]$App)
    # If the app happens to be running, its own image path is ground truth --
    # useful when the registry no longer describes the install correctly.
    foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
        if ($p.ProcessName -notlike "$($App.ProcessPrefix)*") { continue }
        try {
            # Path is inaccessible for processes we cannot open; skip those
            # rather than giving up on the ones we can read.
            if ($p.Path -and (Test-Path $p.Path)) { return $p.Path }
        } catch {
        }
    }
    return $null
}

function Resolve-CompanionExe {
    param([hashtable]$App)

    if ($App.Configured -and (Test-Path $App.Configured)) { return $App.Configured }

    $fromRegistry = Get-CompanionFromRegistry $App
    if ($fromRegistry) { return $fromRegistry }

    $fromProcess = Get-CompanionFromRunningProcess $App
    if ($fromProcess) { return $fromProcess }

    # Last resort: the locations these apps have historically installed to.
    foreach ($f in $App.Fallbacks) {
        if (Test-Path $f) { return $f }
    }

    return $null
}

function Get-ExeNamePattern {
    param([string]$Path)
    '^' + [regex]::Escape([System.IO.Path]::GetFileNameWithoutExtension($Path)) + '$'
}

function Set-CompanionExe {
    param([hashtable]$App, [string]$Path)
    $App.Exe     = $Path
    $App.Pattern = Get-ExeNamePattern $Path
}

function Test-ProcessRunning {
    param([string]$Pattern)
    $procs = Get-Process -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        if ($p.ProcessName -match $Pattern) { return $true }
    }
    return $false
}

function Get-ProcessNameSnapshot {
    # One enumeration answers "is it running?" for every companion at once,
    # rather than walking the whole process table once per app.
    $names = @()
    foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) { $names += $p.ProcessName }
    return ,$names
}

function Test-NameMatch {
    param([string[]]$Names, [string]$Pattern)
    foreach ($n in $Names) {
        if ($n -match $Pattern) { return $true }
    }
    return $false
}

function Get-MatchingProcessIds {
    # Identity matters, not just presence. A game that restarts can have the old
    # process still shutting down as the new one starts, leaving no moment where
    # nothing matched -- so "is the game running" never goes false and a
    # presence-only check sees no launch at all. Comparing process IDs catches
    # the new instance even when the two overlap.
    param([string]$Pattern)
    $ids = @()
    foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
        if ($p.ProcessName -match $Pattern) { $ids += $p.Id }
    }
    return ,$ids
}

function Start-Companion {
    param([hashtable]$App)

    # An update can relocate the executable long after we resolved it at
    # startup, so re-resolve rather than launching a path that is no longer there.
    if (-not (Test-Path $App.Exe)) {
        Write-Log "$($App.Name) no longer at $($App.Exe) - re-resolving"
        $found = Resolve-CompanionExe $App
        if ($found) {
            Set-CompanionExe $App $found
            Write-Log ("{0,-10}: {1}" -f $App.Name, $App.Exe)
        } else {
            Write-Log "FAILED: cannot locate $($App.Name) anywhere - skipping this launch"
            return
        }
    }

    try {
        Start-Process -FilePath $App.Exe
        Write-Log "launched $($App.Exe)"
    } catch {
        Write-Log "$($App.Name) launch FAILED: $_"
    }
}

function Invoke-CompanionLaunch {
    # Shared by the startup catch-up and the poll loop. Immediate skips the
    # delay: at startup the game has already been up for a while, so there is
    # nothing left to wait for.
    param([switch]$Immediate)

    $names   = Get-ProcessNameSnapshot
    $pending = @()
    $running = @()

    foreach ($app in $script:Companions) {
        if (-not $app.Exe) {
            # Installed since the watcher started, most likely. Cheap to check
            # here: this runs once per game launch, not once per poll.
            $found = Resolve-CompanionExe $app
            if (-not $found) { continue }
            Set-CompanionExe $app $found
            Write-Log "$($app.Name) is now installed at $($app.Exe)"
        }
        if (Test-NameMatch $names $app.Pattern) { $running += $app.Name }
        else                                    { $pending += $app }
    }

    if ($running.Count -gt 0) {
        Write-Log "already running: $($running -join ', ')"
    }
    if ($pending.Count -eq 0) {
        Write-Log 'nothing left to launch'
        return
    }

    if (-not $Immediate -and $cfg.LaunchDelaySeconds -gt 0) {
        Write-Log "waiting $($cfg.LaunchDelaySeconds)s before launching"
        Start-Sleep -Seconds $cfg.LaunchDelaySeconds
        # The game can disappear during the wait (crash, wrong client, instant alt-F4).
        if (-not (Test-ProcessRunning $cfg.GamePattern)) {
            Write-Log 'game gone during the delay - not launching'
            return
        }
        # The user can equally have opened one of these by hand while we waited.
        $names = Get-ProcessNameSnapshot
    }

    foreach ($app in $pending) {
        if (Test-NameMatch $names $app.Pattern) {
            Write-Log "$($app.Name) started on its own during the delay - skipping"
            continue
        }
        Start-Companion $app
    }
}

# -------------------------------------------------------------------- main --
# Validate the pattern before the loop, or a typo throws once a second forever.
try {
    $null = [regex]::new($cfg.GamePattern)
} catch {
    Write-Log "FATAL: GamePattern is not a valid regex: $($cfg.GamePattern)"
    exit 1
}

$archon = New-Companion `
    -Name 'Archon' `
    -ExeNames @('Archon App.exe') `
    -RegistryPattern 'Archon App' `
    -ProcessPrefix 'Archon' `
    -Configured $cfg.ArchonExe `
    -Required $true `
    -Fallbacks @(
        (Join-Path $env:ProgramFiles        'Archon App\Archon App.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Archon App\Archon App.exe'),
        (Join-Path $env:LOCALAPPDATA        'Programs\Archon App\Archon App.exe')
    )

$script:Companions = @($archon)

if ($cfg.LaunchWowUp) {
    # WowUp-CF is the maintained build and plain WowUp the older one. Either
    # will do; the CF build is tried first because it is what anyone still
    # running WowUp today is running.
    $script:Companions += New-Companion `
        -Name 'WowUp' `
        -ExeNames @('WowUp-CF.exe', 'WowUp.exe') `
        -RegistryPattern '^WowUp' `
        -ProcessPrefix 'WowUp' `
        -Configured $cfg.WowUpExe `
        -Required $false `
        -Fallbacks @(
            (Join-Path $env:LOCALAPPDATA        'Programs\wowup-cf\WowUp-CF.exe'),
            (Join-Path $env:LOCALAPPDATA        'Programs\wowup\WowUp.exe'),
            (Join-Path $env:ProgramFiles        'WowUp-CF\WowUp-CF.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'WowUp-CF\WowUp-CF.exe'),
            (Join-Path $env:ProgramFiles        'WowUp\WowUp.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'WowUp\WowUp.exe')
        )
}

if ($cfg.LaunchCurseForge) {
    $script:Companions += New-Companion `
        -Name 'CurseForge' `
        -ExeNames @('CurseForge.exe') `
        -RegistryPattern '^CurseForge' `
        -ProcessPrefix 'CurseForge' `
        -Configured $cfg.CurseForgeExe `
        -Required $false `
        -Fallbacks @(
            (Join-Path $env:LOCALAPPDATA        'Programs\CurseForge Windows\CurseForge.exe'),
            (Join-Path $env:ProgramFiles        'CurseForge Windows\CurseForge.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'CurseForge Windows\CurseForge.exe')
        )
}

foreach ($app in $script:Companions) {
    $found = Resolve-CompanionExe $app
    if ($found) { Set-CompanionExe $app $found }
}

if (-not $archon.Exe) {
    Write-Log 'FATAL: could not locate "Archon App.exe" - set ArchonExe in config.json'
    exit 1
}

Write-Log "watcher started (pid $PID)"
Write-Log "version   : $ArchonLauncherVersion"
foreach ($app in $script:Companions) {
    if ($app.Exe) {
        Write-Log ("{0,-10}: {1}" -f $app.Name, $app.Exe)
    } else {
        # Not a fault: the addon managers are launched only if you have them.
        Write-Log ("{0,-10}: not installed - skipping" -f $app.Name)
    }
}
Write-Log "watching  : $($cfg.GamePattern)  every $($cfg.PollSeconds)s"
Write-Log "delay     : $($cfg.LaunchDelaySeconds)s after the game is spotted"
if ($cfg.QuitWithWow) { Write-Log 'quit-with-wow: enabled' }

# The watcher can start mid-session: at logon with the game already up, or when
# the heartbeat revives it after a kill. Waiting for a fresh launch that already
# happened would leave it dormant for the rest of the session, so catch up
# instead -- game up and the apps down is the state this tool exists to fix.
$knownGamePids = @{}
foreach ($id in (Get-MatchingProcessIds $cfg.GamePattern)) { $knownGamePids[$id] = $true }
$wasRunning = $knownGamePids.Count -gt 0

if ($wasRunning) {
    Write-Log 'game already running at startup'
    Invoke-CompanionLaunch -Immediate
}

while ($true) {
    Start-Sleep -Seconds $cfg.PollSeconds

    try {
        $currentIds = Get-MatchingProcessIds $cfg.GamePattern
    } catch {
        Write-Log "process query failed: $_"
        continue
    }

    $isRunning = $currentIds.Count -gt 0
    $newIds    = @($currentIds | Where-Object { -not $knownGamePids.ContainsKey($_) })

    if ($newIds.Count -gt 0) {
        Write-Log "game detected (pid $($newIds -join ', '))"
        Invoke-CompanionLaunch
    }
    elseif (-not $isRunning -and $wasRunning) {
        Write-Log 'game exited'
        if ($cfg.QuitWithWow) {
            foreach ($app in $script:Companions) {
                if (-not $app.Exe) { continue }
                $procs = @(Get-Process -ErrorAction SilentlyContinue |
                           Where-Object { $_.ProcessName -match $app.Pattern })
                if ($procs.Count -eq 0) { continue }
                $procs | ForEach-Object { $null = $_.CloseMainWindow() }
                Write-Log "asked $($app.Name) to close"
            }
        }
    }

    $knownGamePids = @{}
    foreach ($id in $currentIds) { $knownGamePids[$id] = $true }
    $wasRunning = $isRunning
}
