<#
.SYNOPSIS
    The watcher: starts the Archon App -- and optionally WowUp, CurseForge, Raider.IO,
    WowUtils Bridge and programs of your own -- when World of Warcraft launches.

.DESCRIPTION
    Archon's built-in "launch with game" setting only opens the window of an
    already-running instance -- there is no resident component to cold-start it.
    This watcher fills that gap: it polls for the WoW process and starts Archon
    when it appears.

    The same gap applies to the addon managers and the other companion apps,
    which have no launch-with-game feature at all, so the watcher can start them
    alongside Archon. Each is launched only if it is installed and not already
    running; one that is not installed is simply skipped. Any other program can
    be added by path, through the settings app or the CustomApps key.

    This is the part that runs in the background, with no window and no tray
    icon, started at logon by the scheduled task. It is not what you open to
    change settings -- that is ArchonLauncher.exe.

    Settings are read from config.json next to this script, if present, and
    re-read whenever that file changes -- the settings app relies on this, so
    saving there needs no restart. Command-line parameters override config.json,
    which overrides the defaults.

.PARAMETER ArchonExe
    Full path to "Archon App.exe". Auto-detected if omitted.

.PARAMETER WowUpExe
    Full path to "WowUp-CF.exe" or "WowUp.exe". Auto-detected if omitted.

.PARAMETER CurseForgeExe
    Full path to "CurseForge.exe". Auto-detected if omitted.

.PARAMETER RaiderIOExe
    Full path to "RaiderIO.exe". Auto-detected if omitted.

.PARAMETER WowUtilsBridgeExe
    Full path to "WowUtils.Bridge.App.exe". Auto-detected if omitted.

.PARAMETER NoWowUp
    Never start WowUp, even when it is installed.

.PARAMETER NoCurseForge
    Never start CurseForge, even when it is installed.

.PARAMETER NoRaiderIO
    Never start the Raider.IO client, even when it is installed.

.PARAMETER NoWowUtilsBridge
    Never start WowUtils Bridge, even when it is installed.

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

.PARAMETER QuitGraceSeconds
    With QuitWithWow, how long to let an app close on its own before stopping
    it. Default 5. Set to 0 to only ever ask, which leaves apps that treat a
    close as "hide to the tray" -- WowUp by default -- still running.

.EXAMPLE
    .\ArchonWatcher.ps1
    .\ArchonWatcher.ps1 -GamePattern '^Wow$' -QuitWithWow
    .\ArchonWatcher.ps1 -NoCurseForge
#>
[CmdletBinding()]
param(
    [string] $ArchonExe,
    [string] $WowUpExe,
    [string] $CurseForgeExe,
    [string] $RaiderIOExe,
    [string] $WowUtilsBridgeExe,
    [switch] $NoWowUp,
    [switch] $NoCurseForge,
    [switch] $NoRaiderIO,
    [switch] $NoWowUtilsBridge,
    [string] $GamePattern,
    [int]    $PollSeconds,
    [int]    $LaunchDelaySeconds = -1,
    [switch] $QuitWithWow,
    [int]    $QuitGraceSeconds = -1
)

$ErrorActionPreference = 'Stop'

# The single source of truth for the version. Install.ps1 and ViewLog.cmd read
# it back out of this file rather than keeping copies that can drift.
$ArchonLauncherVersion = '1.5.0'

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

# Read-Config runs again on every reload, from inside a function, where
# $PSBoundParameters would describe that function rather than this script.
$script:CliParams  = $PSBoundParameters
$script:ConfigPath = Join-Path $PSScriptRoot 'config.json'

function ConvertTo-Bool {
    # JSON gives real booleans, but a hand-edited config can just as easily say
    # "false" as a string -- and every non-empty string is truthy in PowerShell,
    # so a plain cast would turn every attempt to switch something off into
    # switching it on. Read the word rather than the type.
    param($Value)
    if ($Value -is [bool]) { return $Value }
    return (@('1', 'true', 'yes', 'on') -contains "$Value".Trim().ToLowerInvariant())
}

function Read-Config {
    # Defaults, then config.json, then the command line. Throws when config.json
    # exists but cannot be parsed, and leaves the caller to decide what that
    # means: at startup it is ignored, on a reload the current settings stand.
    param([switch]$IgnoreFile)

    # ------------------------------------------------------------ defaults --
    $c = @{
        ArchonExe            = ''
        WowUpExe             = ''
        CurseForgeExe        = ''
        RaiderIOExe          = ''
        WowUtilsBridgeExe    = ''
        LaunchWowUp          = $true
        LaunchCurseForge     = $true
        LaunchRaiderIO       = $true
        LaunchWowUtilsBridge = $true
        CustomApps           = @()
        GamePattern          = '^Wow(Classic|T|B)?$'
        PollSeconds          = 1
        LaunchDelaySeconds   = 3
        QuitWithWow          = $false
        QuitGraceSeconds     = 5
        LogFile              = Join-Path $env:LOCALAPPDATA 'ArchonLauncher\launcher.log'
        MaxLogBytes          = 1MB
    }

    # --------------------------------------------------------- config.json --
    if (-not $IgnoreFile -and (Test-Path $script:ConfigPath)) {
        $fromFile = Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
        if ($fromFile) {
            foreach ($p in $fromFile.PSObject.Properties) {
                if ($c.ContainsKey($p.Name) -and $null -ne $p.Value -and "$($p.Value)" -ne '') {
                    $c[$p.Name] = $p.Value
                }
            }
        }
    }

    # --------------------------------------------- parameter overrides ------
    $cli = $script:CliParams
    foreach ($k in @('ArchonExe', 'WowUpExe', 'CurseForgeExe', 'RaiderIOExe',
                     'WowUtilsBridgeExe', 'GamePattern', 'PollSeconds')) {
        if ($cli.ContainsKey($k)) { $c[$k] = $cli[$k] }
    }
    if ($LaunchDelaySeconds -ge 0) { $c.LaunchDelaySeconds   = $LaunchDelaySeconds }
    if ($QuitGraceSeconds -ge 0)   { $c.QuitGraceSeconds     = $QuitGraceSeconds }
    if ($QuitWithWow)              { $c.QuitWithWow          = $true }
    if ($NoWowUp)                  { $c.LaunchWowUp          = $false }
    if ($NoCurseForge)             { $c.LaunchCurseForge     = $false }
    if ($NoRaiderIO)               { $c.LaunchRaiderIO       = $false }
    if ($NoWowUtilsBridge)         { $c.LaunchWowUtilsBridge = $false }

    # -------------------------------------------------------- sanity check --
    # Start-Sleep -Seconds 0 returns instantly, which would spin a core at 100%.
    # A negative value throws outright. Clamp both rather than trusting the file.
    if ($c.PollSeconds        -lt 1) { $c.PollSeconds        = 1 }
    if ($c.LaunchDelaySeconds -lt 0) { $c.LaunchDelaySeconds = 0 }
    if ($c.QuitGraceSeconds   -lt 0) { $c.QuitGraceSeconds   = 0 }

    foreach ($k in @('QuitWithWow', 'LaunchWowUp', 'LaunchCurseForge',
                     'LaunchRaiderIO', 'LaunchWowUtilsBridge')) {
        $c[$k] = ConvertTo-Bool $c[$k]
    }

    # Your own programs: { "Name": ..., "Path": ..., "Enabled": ... }. An entry
    # with no path is meaningless and one switched off is simply left out, so
    # everything downstream sees only the programs it should start.
    $custom = @()
    foreach ($a in @($c.CustomApps)) {
        if ($null -eq $a -or -not "$($a.Path)".Trim()) { continue }
        if ($null -ne $a.Enabled -and -not (ConvertTo-Bool $a.Enabled)) { continue }
        $path = "$($a.Path)".Trim()
        $name = "$($a.Name)".Trim()
        if (-not $name) { $name = [System.IO.Path]::GetFileNameWithoutExtension($path) }
        $custom += @{ Name = $name; Path = $path }
    }
    $c.CustomApps = $custom

    return $c
}

function Get-ConfigStamp {
    # Cheap enough to take every poll: one file stat, no read. Size is included
    # because a quick save can land inside the same timestamp tick.
    $item = Get-Item -LiteralPath $script:ConfigPath -ErrorAction SilentlyContinue
    if ($item) { return "$($item.LastWriteTimeUtc.Ticks):$($item.Length)" }
    return ''
}

# Taken before the read, so a save that lands during it is seen next poll.
$script:ConfigStamp = Get-ConfigStamp
$configError = $null
try {
    $cfg = Read-Config
} catch {
    # A malformed config must not stop the watcher from running.
    $configError = "$_"
    $cfg = Read-Config -IgnoreFile
}

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
# Archon, WowUp, CurseForge and Raider.IO are electron-builder installs and
# describe themselves identically in the uninstall registry -- empty
# InstallLocation, a "<exe>,0" DisplayIcon. WowUtils Bridge is an Inno Setup
# install, which fills InstallLocation in. One resolver serves all of them. A
# companion is a plain record: how to find it, how to recognise its process,
# and, once resolved, where it actually is.
function New-Companion {
    param(
        [string]   $Name,
        [string[]] $ExeNames,
        [string]   $RegistryPattern,
        [string]   $ProcessPrefix,
        [string[]] $Fallbacks,
        [string]   $Configured,
        [bool]     $Required,
        [bool]     $Custom
    )
    @{
        Name            = $Name
        ExeNames        = $ExeNames
        RegistryPattern = $RegistryPattern
        ProcessPrefix   = $ProcessPrefix
        Fallbacks       = @($Fallbacks | Where-Object { $_ })
        Configured      = $Configured
        Required        = $Required
        Custom          = $Custom
        Exe             = $null
        Pattern         = $null
        LaunchedByUs    = $false
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
            # Cleanest source, but the electron-builder apps ship this empty.
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

    # A program you added yourself is known only by the path you gave. The
    # searches below need a name to look for, and an empty pattern would match
    # every uninstall entry and every process on the machine.
    if ($App.Custom) { return $null }

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

function New-CompanionSet {
    # Everything the watcher manages under one set of settings, resolved.
    # Archon is always first, and always present.
    param([hashtable]$Config)

    $set = @(New-Companion `
        -Name 'Archon' `
        -ExeNames @('Archon App.exe') `
        -RegistryPattern 'Archon App' `
        -ProcessPrefix 'Archon' `
        -Configured $Config.ArchonExe `
        -Required $true `
        -Fallbacks @(
            (Join-Path $env:ProgramFiles        'Archon App\Archon App.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Archon App\Archon App.exe'),
            (Join-Path $env:LOCALAPPDATA        'Programs\Archon App\Archon App.exe')
        ))

    if ($Config.LaunchWowUp) {
        # WowUp-CF is the maintained build and plain WowUp the older one. Either
        # will do; the CF build is tried first because it is what anyone still
        # running WowUp today is running.
        $set += New-Companion `
            -Name 'WowUp' `
            -ExeNames @('WowUp-CF.exe', 'WowUp.exe') `
            -RegistryPattern '^WowUp' `
            -ProcessPrefix 'WowUp' `
            -Configured $Config.WowUpExe `
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

    if ($Config.LaunchCurseForge) {
        $set += New-Companion `
            -Name 'CurseForge' `
            -ExeNames @('CurseForge.exe') `
            -RegistryPattern '^CurseForge' `
            -ProcessPrefix 'CurseForge' `
            -Configured $Config.CurseForgeExe `
            -Required $false `
            -Fallbacks @(
                (Join-Path $env:LOCALAPPDATA        'Programs\CurseForge Windows\CurseForge.exe'),
                (Join-Path $env:ProgramFiles        'CurseForge Windows\CurseForge.exe'),
                (Join-Path ${env:ProgramFiles(x86)} 'CurseForge Windows\CurseForge.exe')
            )
    }

    if ($Config.LaunchRaiderIO) {
        # The uninstall entry reads "RaiderIO 4.x"; the dot is optional so a
        # rename back to the site's own spelling still matches.
        $set += New-Companion `
            -Name 'Raider.IO' `
            -ExeNames @('RaiderIO.exe') `
            -RegistryPattern '^Raider\.?IO' `
            -ProcessPrefix 'RaiderIO' `
            -Configured $Config.RaiderIOExe `
            -Required $false `
            -Fallbacks @(
                (Join-Path $env:ProgramFiles        'RaiderIO\RaiderIO.exe'),
                (Join-Path ${env:ProgramFiles(x86)} 'RaiderIO\RaiderIO.exe'),
                (Join-Path $env:LOCALAPPDATA        'Programs\RaiderIO\RaiderIO.exe')
            )
    }

    if ($Config.LaunchWowUtilsBridge) {
        $set += New-Companion `
            -Name 'WowUtils Bridge' `
            -ExeNames @('WowUtils.Bridge.App.exe') `
            -RegistryPattern '^WowUtils Bridge' `
            -ProcessPrefix 'WowUtils' `
            -Configured $Config.WowUtilsBridgeExe `
            -Required $false `
            -Fallbacks @(
                (Join-Path $env:LOCALAPPDATA        'Programs\WowUtils Bridge\WowUtils.Bridge.App.exe'),
                (Join-Path $env:ProgramFiles        'WowUtils Bridge\WowUtils.Bridge.App.exe'),
                (Join-Path ${env:ProgramFiles(x86)} 'WowUtils Bridge\WowUtils.Bridge.App.exe')
            )
    }

    foreach ($a in $Config.CustomApps) {
        $set += New-Companion `
            -Name $a.Name `
            -ExeNames @() `
            -Configured $a.Path `
            -Required $false `
            -Custom $true
    }

    foreach ($app in $set) {
        $found = Resolve-CompanionExe $app
        if ($found) { Set-CompanionExe $app $found }
    }
    return ,$set
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
        # Started from its own folder, as a shortcut would: a program of your
        # own may look for files beside itself relative to where it is run.
        Start-Process -FilePath $App.Exe -WorkingDirectory (Split-Path $App.Exe -Parent)
        $App.LaunchedByUs = $true
        Write-Log "launched $($App.Exe)"
    } catch {
        Write-Log "$($App.Name) launch FAILED: $_"
    }
}

function Stop-Companions {
    # Asking means a WM_CLOSE to the main window -- the same message clicking
    # the X sends. An app is free to read that as "hide to the tray" rather
    # than "exit", which is precisely what WowUp does by default: it obeys the
    # request and stays running, leaving quit-with-wow half honoured. So
    # anything still alive at the end of the grace window is stopped outright.
    #
    # Everything is asked first and the grace window then serves the whole set,
    # rather than one wait per app. The game has just exited, but a watcher
    # asleep for three consecutive waits is three launches it cannot see.
    #
    # A program of your own is closed only if this watcher started it. It is
    # matched by executable name, and closing every process called, say,
    # "chrome" because WoW exited would take the browser you had open anyway.
    param([int]$GraceSeconds)

    $asked = @()
    foreach ($app in $script:Companions) {
        if (-not $app.Exe) { continue }
        if ($app.Custom -and -not $app.LaunchedByUs) { continue }
        $app.LaunchedByUs = $false
        $procs = @(Get-Process -ErrorAction SilentlyContinue |
                   Where-Object { $_.ProcessName -match $app.Pattern })
        if ($procs.Count -eq 0) { continue }
        foreach ($p in $procs) {
            try { $null = $p.CloseMainWindow() } catch { }
        }
        Write-Log "asked $($app.Name) to close"
        $asked += $app
    }

    if ($asked.Count -eq 0 -or $GraceSeconds -le 0) { return }

    # Give them the chance to go quietly; most will, and that is the better exit.
    $deadline = (Get-Date).AddSeconds($GraceSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        $stillUp = @($asked | Where-Object { Test-ProcessRunning $_.Pattern })
        if ($stillUp.Count -eq 0) { return }
    }

    foreach ($app in $asked) {
        $left = @(Get-Process -ErrorAction SilentlyContinue |
                  Where-Object { $_.ProcessName -match $app.Pattern })
        if ($left.Count -eq 0) { continue }
        foreach ($p in $left) {
            try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { }
        }
        Write-Log "$($app.Name) ignored the close request - stopped it"
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

    # A program of your own can name the same executable as a built-in one --
    # Raider.IO added by hand as well as ticked, say. Start it once.
    $started = @{}
    foreach ($app in $pending) {
        if (Test-NameMatch $names $app.Pattern) {
            Write-Log "$($app.Name) started on its own during the delay - skipping"
            continue
        }
        if ($started.ContainsKey($app.Pattern)) { continue }
        $started[$app.Pattern] = $true
        Start-Companion $app
    }
}

function Write-Settings {
    foreach ($app in $script:Companions) {
        if ($app.Exe) {
            Write-Log ("{0,-10}: {1}" -f $app.Name, $app.Exe)
        } elseif ($app.Custom) {
            Write-Log ("{0,-10}: not found at {1} - skipping" -f $app.Name, $app.Configured)
        } else {
            # Not a fault: the companion apps are launched only if you have them.
            Write-Log ("{0,-10}: not installed - skipping" -f $app.Name)
        }
    }
    Write-Log "watching  : $($cfg.GamePattern)  every $($cfg.PollSeconds)s"
    Write-Log "delay     : $($cfg.LaunchDelaySeconds)s after the game is spotted"
    if ($cfg.QuitWithWow) {
        if ($cfg.QuitGraceSeconds -gt 0) {
            Write-Log "quit-with-wow: enabled, stopping anything still up after $($cfg.QuitGraceSeconds)s"
        } else {
            Write-Log 'quit-with-wow: enabled, asking only'
        }
    } else {
        Write-Log 'quit-with-wow: off'
    }
}

function Test-GamePattern {
    param([string]$Pattern)
    try { $null = [regex]::new($Pattern); return $true } catch { return $false }
}

function Update-Settings {
    # config.json changed underneath us -- most likely the settings app
    # saving. Anything wrong with the new settings leaves the current ones in
    # force, rather than a watcher that falls back to defaults or stops dead
    # because of one bad save.
    param([string]$Stamp)

    # Recorded whatever the outcome, so a file that stays broken is reported
    # once rather than once a second. The next save changes the stamp again.
    $script:ConfigStamp = $Stamp

    try {
        $new = Read-Config
    } catch {
        Write-Log "config.json changed but cannot be read - keeping the current settings: $_"
        return
    }
    if (-not (Test-GamePattern $new.GamePattern)) {
        Write-Log "config.json changed but GamePattern is not a valid regex - keeping the current settings"
        return
    }
    $set = New-CompanionSet $new
    if (-not $set[0].Exe) {
        Write-Log 'config.json changed but Archon cannot be located with it - keeping the current settings'
        return
    }

    # Carry over which programs of your own this watcher started, so that
    # saving mid-session does not stop quit-with-wow closing them afterwards.
    foreach ($app in $set) {
        foreach ($old in $script:Companions) {
            if ($old.LaunchedByUs -and $old.Custom -and $app.Custom -and $old.Exe -eq $app.Exe) {
                $app.LaunchedByUs = $true
            }
        }
    }

    $script:cfg        = $new
    $script:Companions = $set
    New-Item -ItemType Directory -Force -Path (Split-Path $cfg.LogFile) | Out-Null
    Write-Log 'settings changed - reloaded config.json, effective from the next game launch'
    Write-Settings
}

# -------------------------------------------------------------------- main --
if ($configError) {
    Write-Log "ignoring unreadable config.json: $configError"
}

# Validate the pattern before the loop, or a typo throws once a second forever.
if (-not (Test-GamePattern $cfg.GamePattern)) {
    Write-Log "FATAL: GamePattern is not a valid regex: $($cfg.GamePattern)"
    exit 1
}

$script:Companions = New-CompanionSet $cfg

if (-not $script:Companions[0].Exe) {
    Write-Log 'FATAL: could not locate "Archon App.exe" - set ArchonExe in config.json'
    exit 1
}

Write-Log "watcher started (pid $PID)"
Write-Log "version   : $ArchonLauncherVersion"
Write-Settings

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

    $stamp = Get-ConfigStamp
    if ($stamp -ne $script:ConfigStamp) { Update-Settings $stamp }

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
            Stop-Companions -GraceSeconds $cfg.QuitGraceSeconds
        }
    }

    $knownGamePids = @{}
    foreach ($id in $currentIds) { $knownGamePids[$id] = $true }
    $wasRunning = $isRunning
}
