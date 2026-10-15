<#
.SYNOPSIS
    The SLCLauncher settings window.

.DESCRIPTION
    Edits config.json in %LOCALAPPDATA%\SLCLauncher: which apps start with
    World of Warcraft, whether they close with it, and any programs of your own.

    Its header says whether a newer SLCLauncher has been released, and
    installs it when asked: the installer is downloaded from the GitHub
    release, checked against the SHA-256 GitHub publishes for it, and run.
    The check is the same once-a-day request the watcher makes, and shares its
    answer through update.json, so between them it is still made once a day.

    The watcher notices the saved file within a second and reloads it without a
    restart; the new settings take effect the next time the game starts. Keys
    this window does not show -- GamePattern, the *Exe paths and so on -- are
    written back exactly as they were found.

    Drawn in SimpleLootCouncil's palette by the controls in SLCTheme.cs.

    SLCLauncher.exe runs this inside its own process; that is what the Start
    menu shortcut opens. It can equally be run with powershell.exe -STA -File,
    at the cost of a console window behind it.

.PARAMETER InstallDir
    The folder holding the watcher and its config.json. Defaults to where the
    installer puts them; pointing it elsewhere is for trying the window out
    without touching a real install.
#>
[CmdletBinding()]
param(
    [string] $InstallDir = (Join-Path $env:LOCALAPPDATA 'SLCLauncher')
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

# The themed controls are compiled into SLCLauncher.exe, so inside it they are
# already loaded. Run any other way, they are compiled from the source beside
# this script -- which takes a second, and is why the exe carries them.
if (-not ('SLCLauncher.Theme.Palette' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'SLCTheme.cs') `
             -ReferencedAssemblies System.Windows.Forms, System.Drawing
}

# Without this Windows draws the window at 96 DPI and stretches the bitmap,
# which reads as blurry text on any display scaled above 100%.
$null = [SLCLauncher.Theme.Native]::SetProcessDPIAware()
[System.Windows.Forms.Application]::EnableVisualStyles()

$installDir = $InstallDir
$configPath = Join-Path $installDir 'config.json'

function Show-Message {
    param([string]$Text, [string]$Icon = 'Information')
    $null = [System.Windows.Forms.MessageBox]::Show($Text, 'SLCLauncher', 'OK', $Icon)
}

if (-not (Test-Path (Join-Path $installDir 'SLCWatcher.ps1'))) {
    Show-Message "SLCLauncher is not installed.`n`nRun the SLCLauncher installer first, then open SLCLauncher again." 'Warning'
    exit 1
}

function ConvertTo-Bool {
    # Same reading as the watcher's, so "false" typed into the file by hand
    # shows as unticked here rather than as the non-empty string it is.
    param($Value)
    if ($Value -is [bool]) { return $Value }
    return (@('1', 'true', 'yes', 'on') -contains "$Value".Trim().ToLowerInvariant())
}

# ------------------------------------------------------------ current state --
$config = $null
if (Test-Path $configPath) {
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
    } catch {
        Show-Message ("config.json could not be read, so these options start from the defaults. " +
                      "Saving will replace it.`n`n$_") 'Warning'
    }
}
if (-not $config) { $config = New-Object PSObject }

function Get-Setting {
    # Missing or empty means the watcher's default, exactly as the watcher reads it.
    param([string]$Name, $Default)
    $p = $config.PSObject.Properties[$Name]
    if ($p -and $null -ne $p.Value -and "$($p.Value)" -ne '') { return $p.Value }
    return $Default
}

# The built-in apps, in the order they are shown: down the left column, then
# down the right.
$builtIns = @(
    @{ Key = 'LaunchArchon';         Label = 'Archon App' },
    @{ Key = 'LaunchWowUp';          Label = 'WowUp' },
    @{ Key = 'LaunchCurseForge';     Label = 'CurseForge' },
    @{ Key = 'LaunchRaiderIO';       Label = 'Raider.IO' },
    @{ Key = 'LaunchWowUtilsBridge'; Label = 'WowUtils Bridge' },
    @{ Key = 'LaunchWowAudit';       Label = 'wowaudit' },
    @{ Key = 'LaunchGuildsOfWow';    Label = 'Guilds of WoW' },
    @{ Key = 'LaunchTSM';            Label = 'TSM Desktop App' }
)

# The installed version, from the one place it is written down.
$currentVersion = '0.0.0'
$vMatch = Select-String -LiteralPath (Join-Path $installDir 'SLCWatcher.ps1') `
                        -Pattern "SLCLauncherVersion\s*=\s*'([^']+)'" | Select-Object -First 1
if ($vMatch) { $currentVersion = $vMatch.Matches[0].Groups[1].Value }

# ------------------------------------------------------------------ window --
$P = [SLCLauncher.Theme.Palette]

$form = New-Object System.Windows.Forms.Form
$form.Text            = 'SLCLauncher'
$form.Font            = New-Object System.Drawing.Font('Segoe UI', 9.5)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox     = $false
$form.StartPosition   = 'CenterScreen'
$form.AutoSize        = $true
$form.AutoSizeMode    = 'GrowAndShrink'
$form.BackColor       = $P::Canvas
$form.ForeColor       = $P::Text

# Fixed sizes are given at 96 DPI and scaled; text sizes itself from the font,
# which is already the right size for the display.
$scale = $form.CreateGraphics().DpiX / 96
function S { param([double]$Px) [int][math]::Round($Px * $scale) }

$pad      = S 18                  # window edge -> content
$cardPad  = S 14                  # card edge -> its contents
$contentW = S 470                 # the width every card shares
$innerW   = $contentW - 2 * $cardPad

# The title bar follows the window's colours rather than the system's. Done
# when the handle exists, before the window is first drawn, so it never
# flashes white.
$form.Add_HandleCreated({ [SLCLauncher.Theme.Native]::ThemeTitleBar($form) })

# The taskbar shows the window's icon, not the file's, so the icon embedded in
# SLCLauncher.exe has to be given to the window as well. The .ico carries
# every size, and Windows picks the one each place needs.
$iconPath = Join-Path $PSScriptRoot 'SLCLauncher.ico'
$appIcon  = $null
if (Test-Path $iconPath) {
    $appIcon   = New-Object System.Drawing.Icon($iconPath)
    $form.Icon = $appIcon
}

$fontTitle   = New-Object System.Drawing.Font('Segoe UI Semibold', 14)
$fontHeading = New-Object System.Drawing.Font('Segoe UI Semibold', 8.25)
$fontSmall   = New-Object System.Drawing.Font('Segoe UI', 8.75)

function New-Label {
    param([string]$Text, $Font = $form.Font, $Color = $P::Text, [int]$Width = 0)
    $l = New-Object System.Windows.Forms.Label
    $l.Text      = $Text
    $l.Font      = $Font
    $l.ForeColor = $Color
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.AutoSize  = $true
    if ($Width -gt 0) { $l.MaximumSize = New-Object System.Drawing.Size($Width, 0) }
    return $l
}

function New-Stack {
    # A top-to-bottom column that sizes itself to what is in it.
    param([int]$Padding = 0)
    $f = New-Object System.Windows.Forms.FlowLayoutPanel
    $f.FlowDirection = 'TopDown'
    $f.WrapContents  = $false
    $f.AutoSize      = $true
    $f.AutoSizeMode  = 'GrowAndShrink'
    $f.BackColor     = [System.Drawing.Color]::Transparent
    $f.Padding       = New-Object System.Windows.Forms.Padding($Padding)
    $f.Margin        = New-Object System.Windows.Forms.Padding(0)
    return $f
}

function Add-Section {
    # A tracked-caps heading over a card, as SLC's settings lay out a group.
    # Returns the column inside the card for the section's rows.
    param([string]$Title)
    $h = New-Label $Title.ToUpperInvariant() $fontHeading $P::TextFaint
    $h.Margin = New-Object System.Windows.Forms.Padding((S 2), (S 14), 0, (S 6))
    $body.Controls.Add($h)

    $card = New-Object SLCLauncher.Theme.Card
    $card.AutoSize     = $true
    $card.AutoSizeMode = 'GrowAndShrink'
    $card.Margin       = New-Object System.Windows.Forms.Padding(0)
    $stack = New-Stack $cardPad
    $stack.MinimumSize = New-Object System.Drawing.Size($contentW, 0)
    $card.Controls.Add($stack)
    $body.Controls.Add($card)
    return $stack
}

function New-Check {
    param([string]$Text, [bool]$Checked)
    $c = New-Object SLCLauncher.Theme.ThemedCheckBox
    $c.Text    = $Text
    $c.Checked = $Checked
    $c.Margin  = New-Object System.Windows.Forms.Padding(0, 0, 0, (S 2))
    return $c
}

function New-Hint {
    param([string]$Text)
    $h = New-Label $Text $fontSmall $P::TextFaint $innerW
    $h.Margin = New-Object System.Windows.Forms.Padding(0, (S 6), 0, 0)
    return $h
}

# The window is three bands stacked: header, body, footer.
$page = New-Stack
$form.Controls.Add($page)

# ------------------------------------------------------------------ header --
$header = New-Object SLCLauncher.Theme.HeaderBand
$header.Size   = New-Object System.Drawing.Size(($contentW + 2 * $pad), (S 72))
$header.Margin = New-Object System.Windows.Forms.Padding(0)
$page.Controls.Add($header)

$titleX = $pad
if ($appIcon) {
    $logo = New-Object System.Windows.Forms.PictureBox
    $logo.Size      = New-Object System.Drawing.Size((S 40), (S 40))
    $logo.Location  = New-Object System.Drawing.Point($pad, (S 16))
    $logo.SizeMode  = 'Zoom'
    $logo.BackColor = [System.Drawing.Color]::Transparent
    # The .ico's largest frame is stored as a PNG, which Icon.ToBitmap cannot
    # unpack on the .NET Framework. Read that PNG straight out of the file:
    # a 6-byte header, then 16 bytes per frame giving its size and offset.
    $ico   = [System.IO.File]::ReadAllBytes($iconPath)
    $count = [BitConverter]::ToUInt16($ico, 4)
    $best  = 0; $bestSize = 0; $bestOffset = 0
    for ($i = 0; $i -lt $count; $i++) {
        $e = 6 + 16 * $i
        $dim = if ($ico[$e] -eq 0) { 256 } else { $ico[$e] }
        if ($dim -gt $best) {
            $best = $dim
            $bestSize   = [BitConverter]::ToInt32($ico, $e + 8)
            $bestOffset = [BitConverter]::ToInt32($ico, $e + 12)
        }
    }
    $logo.Image = [System.Drawing.Image]::FromStream(
        (New-Object System.IO.MemoryStream(, [byte[]]$ico[$bestOffset..($bestOffset + $bestSize - 1)])))
    $header.Controls.Add($logo)
    $titleX = $pad + (S 52)
}
$title = New-Label 'SLCLauncher' $fontTitle $P::Text
$title.Location = New-Object System.Drawing.Point($titleX, (S 12))
$header.Controls.Add($title)
$subtitle = New-Label 'Your World of Warcraft tools, started with the game.' $fontSmall $P::TextMuted
$subtitle.Location = New-Object System.Drawing.Point(($titleX + (S 2)), (S 42))
$header.Controls.Add($subtitle)

# Top right: whether this is the latest version, and the version itself under
# it. Both right-aligned by hand, since their text changes as a check runs.
$updateLabel = New-Label '' $fontSmall $P::TextFaint
$header.Controls.Add($updateLabel)
$versionLabel = New-Label "v$currentVersion" $fontSmall $P::TextFaint
$header.Controls.Add($versionLabel)

function Set-HeaderRight {
    param($Label, [int]$Y)
    $Label.Location = New-Object System.Drawing.Point(($header.Width - $pad - $Label.PreferredWidth), $Y)
}
Set-HeaderRight $versionLabel (S 42)

# -------------------------------------------------------------------- body --
$body = New-Stack
$body.Padding = New-Object System.Windows.Forms.Padding($pad, (S 4), $pad, $pad)
$page.Controls.Add($body)

# ------------------------------------------------------- the built-in apps --
$apps = Add-Section 'Start with World of Warcraft'

# Two columns: the names are short, and one long column left most of the
# card empty.
$grid = New-Object System.Windows.Forms.TableLayoutPanel
$grid.ColumnCount  = 2
$grid.RowCount     = [math]::Ceiling($builtIns.Count / 2)
$grid.AutoSize     = $true
$grid.AutoSizeMode = 'GrowAndShrink'
$grid.BackColor    = [System.Drawing.Color]::Transparent
$grid.Margin       = New-Object System.Windows.Forms.Padding(0)
$colW = [int]($innerW / 2)
foreach ($i in 0..1) {
    $null = $grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', $colW)))
}
$apps.Controls.Add($grid)

$appBoxes = @{}
for ($i = 0; $i -lt $builtIns.Count; $i++) {
    $b = $builtIns[$i]
    $box = New-Check $b.Label (ConvertTo-Bool (Get-Setting $b.Key $true))
    $grid.Controls.Add($box, [int][math]::Floor($i / $grid.RowCount), $i % $grid.RowCount)
    $appBoxes[$b.Key] = $box
}
$apps.Controls.Add((New-Hint 'Anything ticked that is not installed is skipped.'))

# ------------------------------------------------------ your own programs ---
$own = Add-Section 'Your own programs'

$rows = New-Stack
$own.Controls.Add($rows)
$empty = New-Label 'None yet. Add any program to start it with WoW.' $form.Font $P::TextMuted
$empty.Margin = New-Object System.Windows.Forms.Padding(0, (S 2), 0, (S 6))
$rows.Controls.Add($empty)

$tips = New-Object System.Windows.Forms.ToolTip

# One entry per program: its tick box, its path, and a button to drop it.
# The list IS the controls -- saving reads them back -- so there is no second
# copy of it to fall out of step.
$customRows = New-Object System.Collections.ArrayList

function Update-Empty { $empty.Visible = $customRows.Count -eq 0 }

function Get-ShortPath {
    # One line, however long the path. The folders in the middle go first,
    # because the drive says where it lives and the file name says what it is:
    # "C:\...\bin\64bit\obs64.exe", not "C:\Program Files\obs-st...".
    param([string]$Path, $Font, [int]$Width)
    $fits = { param($s) [System.Windows.Forms.TextRenderer]::MeasureText($s, $Font).Width -le $Width }
    if (& $fits $Path) { return $Path }
    $parts = $Path.Split('\')
    for ($drop = 1; $drop -lt $parts.Count - 1; $drop++) {
        $keep = $parts.Count - 1 - $drop
        $s = $parts[0] + '\...\' + (($parts[($parts.Count - $keep)..($parts.Count - 1)]) -join '\')
        if ($keep -eq 0) { $s = $parts[0] + '\...\' + $parts[-1] }
        if (& $fits $s) { return $s }
    }
    return '...\' + $parts[-1]
}

function Add-CustomRow {
    param([string]$Name, [string]$Path, [bool]$Enabled)

    $row = New-Object System.Windows.Forms.Panel
    $row.Size      = New-Object System.Drawing.Size($innerW, (S 32))
    $row.Margin    = New-Object System.Windows.Forms.Padding(0)
    $row.BackColor = [System.Drawing.Color]::Transparent

    $box = New-Check $Name $Enabled
    $box.AutoSize = $false
    $box.Size     = New-Object System.Drawing.Size((S 170), (S 32))
    $box.Location = New-Object System.Drawing.Point(0, 0)
    $row.Controls.Add($box)

    $pathW = $innerW - (S 178) - (S 36)
    $pathLabel = New-Object System.Windows.Forms.Label
    $pathLabel.Text      = Get-ShortPath $Path $fontSmall $pathW
    $pathLabel.Font      = $fontSmall
    $pathLabel.ForeColor = $P::TextMuted
    $pathLabel.BackColor = [System.Drawing.Color]::Transparent
    $pathLabel.AutoSize  = $false
    $pathLabel.TextAlign = 'MiddleLeft'
    $pathLabel.Location  = New-Object System.Drawing.Point((S 178), 0)
    $pathLabel.Size      = New-Object System.Drawing.Size($pathW, (S 32))
    $tips.SetToolTip($pathLabel, $Path)
    $row.Controls.Add($pathLabel)

    $remove = New-Object SLCLauncher.Theme.ThemedButton
    $remove.Text     = [string][char]0x00D7   # a multiplication sign; Segoe UI has it, so no emoji fallback
    $remove.Font     = New-Object System.Drawing.Font('Segoe UI', 12)
    $remove.AutoSize = $false
    $remove.Size     = New-Object System.Drawing.Size((S 26), (S 26))
    $remove.Location = New-Object System.Drawing.Point(($innerW - (S 26)), (S 3))
    $tips.SetToolTip($remove, "Remove $Name")
    $row.Controls.Add($remove)

    # The entry rides on the button rather than in a closure: a closure would
    # cut the handler off from $rows, $customRows and Update-Empty.
    $entry = @{ Name = $Name; Path = $Path; Box = $box; Row = $row }
    $remove.Tag = $entry
    $remove.Add_Click({
        param($sender)
        $rows.Controls.Remove($sender.Tag.Row)
        $customRows.Remove($sender.Tag)
        Update-Empty
    })

    $rows.Controls.Add($row)
    $null = $customRows.Add($entry)
    Update-Empty
    return $entry
}

foreach ($a in @(Get-Setting 'CustomApps' @())) {
    if ($null -eq $a -or -not "$($a.Path)".Trim()) { continue }
    $path = "$($a.Path)".Trim()
    $name = "$($a.Name)".Trim()
    if (-not $name) { $name = [System.IO.Path]::GetFileNameWithoutExtension($path) }
    $enabled = ($null -eq $a.Enabled) -or (ConvertTo-Bool $a.Enabled)
    $null = Add-CustomRow $name $path $enabled
}

$addButton = New-Object SLCLauncher.Theme.ThemedButton
$addButton.Text   = 'Add program...'
$addButton.Margin = New-Object System.Windows.Forms.Padding(0, (S 8), 0, 0)
$own.Controls.Add($addButton)

$own.Controls.Add((New-Hint ('Ticked programs start with WoW unless they are already running. ' +
    'Pick the program itself, not a launcher or updater that starts it.')))

$addButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title  = 'Choose a program to start with World of Warcraft'
    $dialog.Filter = 'Programs (*.exe)|*.exe'
    $dialog.InitialDirectory = $env:ProgramFiles
    if ($dialog.ShowDialog($form) -ne 'OK') { return }
    $path = $dialog.FileName

    foreach ($existing in $customRows) {
        if ($existing.Path -eq $path) {
            $existing.Box.Checked = $true
            $existing.Box.Focus()
            return
        }
    }

    # The name the program gives itself reads better than its file name:
    # "Microsoft Edge" rather than "msedge".
    $name = $null
    try { $name = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path).FileDescription } catch { }
    if (-not "$name".Trim()) { $name = [System.IO.Path]::GetFileNameWithoutExtension($path) }

    $null = Add-CustomRow "$name".Trim() $path $true
})

# ---------------------------------------------------------- close with WoW --
$closing = Add-Section 'When WoW closes'
$quitBox = New-Check 'Close them all when WoW closes' (ConvertTo-Bool (Get-Setting 'QuitWithWow' $false))
$closing.Controls.Add($quitBox)
$closing.Controls.Add((New-Hint ('Each app is asked to close first. Anything still running a few seconds ' +
    'later - an app that hides in the tray instead - is stopped. Programs of your own are closed only ' +
    'if SLCLauncher started them.')))

# ----------------------------------------------------------------- updates --
$updates = Add-Section 'Updates'
$updateBox = New-Check 'Check for a new version once a day' (ConvertTo-Bool (Get-Setting 'CheckForUpdates' $true))
$updates.Controls.Add($updateBox)
$updates.Controls.Add((New-Hint ('Asks GitHub for the number of the latest release, and shows a notification ' +
    'when there is a newer one. Nothing about you or your settings is sent.')))

# ------------------------------------------------------------------ footer --
$footer = New-Object SLCLauncher.Theme.FooterBand
$footer.Size   = New-Object System.Drawing.Size(($contentW + 2 * $pad), (S 60))
$footer.Margin = New-Object System.Windows.Forms.Padding(0)
$page.Controls.Add($footer)

$cancelButton = New-Object SLCLauncher.Theme.ThemedButton
$cancelButton.Text         = 'Cancel'
$cancelButton.DialogResult = 'Cancel'
$footer.Controls.Add($cancelButton)

$saveButton = New-Object SLCLauncher.Theme.ThemedButton
$saveButton.Text    = 'Save'
$saveButton.Primary = $true
$footer.Controls.Add($saveButton)

# Right-aligned by hand: the buttons size themselves to their text, so their
# positions are known only once they exist.
$cancelSize = $cancelButton.GetPreferredSize([System.Drawing.Size]::Empty)
$saveSize   = $saveButton.GetPreferredSize([System.Drawing.Size]::Empty)
$saveSize   = New-Object System.Drawing.Size([math]::Max($saveSize.Width, $cancelSize.Width), $saveSize.Height)
$buttonY    = [int](($footer.Height - $saveSize.Height) / 2)
$saveButton.AutoSize   = $false
$saveButton.Size       = $saveSize
$saveButton.Location   = New-Object System.Drawing.Point(($footer.Width - $pad - $saveSize.Width), $buttonY)
$cancelButton.AutoSize = $false
$cancelButton.Size     = $saveSize
$cancelButton.Location = New-Object System.Drawing.Point(($saveButton.Left - (S 8) - $saveSize.Width), $buttonY)

# The same check ViewLog.cmd makes.
$watcher = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
           Where-Object { $_.CommandLine -like '*SLCWatcher.ps1*' } |
           Select-Object -First 1
if ($watcher) {
    $status = New-Label 'Changes apply the next time WoW starts.' $fontSmall $P::TextMuted
} else {
    $status = New-Label 'The watcher is not running right now.' $fontSmall $P::Bad
}
$status.Location = New-Object System.Drawing.Point($pad, [int](($footer.Height - $status.PreferredHeight) / 2))
$footer.Controls.Add($status)

$form.AcceptButton = $saveButton
$form.CancelButton = $cancelButton

function Set-Setting {
    param([string]$Name, $Value)
    $config | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

$saveButton.Add_Click({
    foreach ($b in $builtIns) { Set-Setting $b.Key $appBoxes[$b.Key].Checked }
    Set-Setting 'QuitWithWow' $quitBox.Checked
    Set-Setting 'CheckForUpdates' $updateBox.Checked

    $custom = @()
    foreach ($entry in $customRows) {
        $custom += [pscustomobject][ordered]@{
            Name    = $entry.Name
            Path    = $entry.Path
            Enabled = $entry.Box.Checked
        }
    }
    Set-Setting 'CustomApps' $custom

    # Written beside the real file and then moved over it, so the watcher --
    # which rereads the file the moment it changes -- never sees half of it.
    $json = ConvertTo-Json -InputObject $config -Depth 5
    $temp = "$configPath.saving"
    try {
        [System.IO.File]::WriteAllText($temp, $json, (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temp -Destination $configPath -Force
    } catch {
        Show-Message "Your settings could not be saved.`n`n$_" 'Error'
        return
    }
    $form.DialogResult = 'OK'
})

# ----------------------------------------------------------------- updates --
# The same request the watcher makes, to the same address, sharing its answer
# through update.json: a check either of them made in the last day stands.
# Requests run asynchronously and a timer looks in on them, so the window never
# waits on the network; everything below runs on the window's own thread.
$releaseApi      = 'https://api.github.com/repos/Laxxzz/SLCLauncher/releases/latest'
$updateStatePath = Join-Path $installDir 'update.json'

# One record the handlers change in place: a handler that assigned to a plain
# variable would only make its own copy.
$upd = @{
    Action  = $null   # what clicking the header line does: 'check', 'install' or nothing
    Release = $null   # the release as GitHub last described it
    Job     = $null   # the request in flight: Client, Task, Deadline, Kind
    InstallWhenChecked = $false
}

function Read-UpdateState {
    $s = $null
    if (Test-Path -LiteralPath $updateStatePath) {
        try { $s = Get-Content -LiteralPath $updateStatePath -Raw | ConvertFrom-Json } catch { }
    }
    if (-not $s) { $s = New-Object PSObject }
    foreach ($k in 'LastCheck', 'LatestVersion', 'ReleaseUrl', 'NotifiedVersion') {
        if (-not $s.PSObject.Properties[$k]) { $s | Add-Member -NotePropertyName $k -NotePropertyValue '' }
    }
    return $s
}

function Write-UpdateState {
    param($State)
    try {
        $temp = "$updateStatePath.saving"
        [System.IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $State),
                                       (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temp -Destination $updateStatePath -Force
    } catch { }
}

function Test-Newer {
    param([string]$Latest)
    $v = $null; $mine = $null
    if (-not [version]::TryParse($Latest, [ref]$v)) { return $false }
    if (-not [version]::TryParse($currentVersion, [ref]$mine)) { return $true }
    return $v -gt $mine
}

function Set-UpdateStatus {
    param([string]$Text, $Color, [string]$Action, [string]$Tip)
    $updateLabel.Text      = $Text
    $updateLabel.ForeColor = $Color
    $updateLabel.Cursor    = if ($Action) { [System.Windows.Forms.Cursors]::Hand } else { [System.Windows.Forms.Cursors]::Default }
    $upd.Action = $Action
    $tips.SetToolTip($updateLabel, $Tip)
    Set-HeaderRight $updateLabel (S 18)
}

function Show-Latest {
    # The header for a known latest version. Seeing it here counts as being
    # told, so the watcher does not announce the same version again.
    param($State)
    if (Test-Newer $State.LatestVersion) {
        Set-UpdateStatus 'Update available' $P::Notice 'install' `
            "SLCLauncher $($State.LatestVersion) is out. Click to install it - your settings are kept."
        if ($State.NotifiedVersion -ne $State.LatestVersion) {
            $State.NotifiedVersion = $State.LatestVersion
            Write-UpdateState $State
        }
    } else {
        Set-UpdateStatus 'Up to date' $P::Accent 'check' 'This is the latest version. Click to check again.'
    }
}

function Start-Request {
    param([string]$Kind, [string]$Url, [string]$File, [int]$Seconds)
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $client = New-Object System.Net.WebClient
    $client.Headers['User-Agent'] = "SLCLauncher/$currentVersion"
    if ($Kind -eq 'check') {
        $client.Headers['Accept'] = 'application/vnd.github+json'
        $task = $client.DownloadStringTaskAsync($Url)
    } else {
        $task = $client.DownloadFileTaskAsync($Url, $File)
    }
    $upd.Job = @{ Kind = $Kind; Client = $client; Task = $task; File = $File
                  Deadline = (Get-Date).AddSeconds($Seconds) }
    $pollTimer.Start()
}

function Start-UpdateCheck {
    if ($upd.Job) { return }
    Set-UpdateStatus 'Checking for updates...' $P::TextFaint $null ''
    try {
        Start-Request 'check' $releaseApi $null 20
    } catch {
        Set-UpdateStatus 'Could not check for updates' $P::TextFaint 'check' "$_`nClick to try again."
    }
}

function Complete-UpdateCheck {
    param($Job)
    $failed = $Job.Task.IsFaulted -or $Job.Task.IsCanceled
    $release = $null
    if (-not $failed) {
        try { $release = $Job.Task.Result | ConvertFrom-Json } catch { $failed = $true }
    }
    if ($failed -or -not $release.tag_name) {
        $why = if ($Job.Task.Exception) { $Job.Task.Exception.GetBaseException().Message } else { 'No answer from GitHub.' }
        Set-UpdateStatus 'Could not check for updates' $P::TextFaint 'check' "$why`nClick to try again."
        $upd.InstallWhenChecked = $false
        return
    }
    $upd.Release = $release
    $state = Read-UpdateState
    $state.LastCheck     = (Get-Date).ToUniversalTime().ToString('o')
    $state.LatestVersion = "$($release.tag_name)" -replace '^[vV]', ''
    $state.ReleaseUrl    = "$($release.html_url)"
    Write-UpdateState $state
    Show-Latest $state

    if ($upd.InstallWhenChecked) {
        $upd.InstallWhenChecked = $false
        if (Test-Newer $state.LatestVersion) { Invoke-Update }
    }
}

function Invoke-Update {
    # Installing needs the release's files and their checksums, which only a
    # fresh answer from GitHub has; a day-old note in update.json does not.
    if (-not $upd.Release) {
        $upd.InstallWhenChecked = $true
        Start-UpdateCheck
        return
    }
    $latest = "$($upd.Release.tag_name)" -replace '^[vV]', ''
    $answer = [System.Windows.Forms.MessageBox]::Show($form,
        ("SLCLauncher $latest is available. You have $currentVersion.`n`n" +
         "Yes - download and install it now. Your settings are kept.`n" +
         "No - read what is new on GitHub first.`n`n" +
         "This window closes while it installs; changes not yet saved are lost."),
        'SLCLauncher', 'YesNoCancel', 'Information')
    if ($answer -eq 'No') { Start-Process "$($upd.Release.html_url)"; return }
    if ($answer -ne 'Yes') { return }

    $asset = @($upd.Release.assets | Where-Object { "$($_.name)" -match '^SLCLauncher-Setup-.+\.exe$' })[0]
    if (-not $asset -or "$($asset.digest)" -notmatch '^sha256:[0-9a-fA-F]{64}$') {
        # Never run an installer there is nothing to check against.
        Show-Message ("This release has no installer with a published checksum, so it cannot be " +
                      "installed from here. Its GitHub page will open instead.") 'Warning'
        Start-Process "$($upd.Release.html_url)"
        return
    }

    $dir = Join-Path ([System.IO.Path]::GetTempPath()) 'SLCLauncher-update'
    $file = Join-Path $dir $asset.name
    try {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
        $upd.Asset = $asset
        Set-UpdateStatus 'Downloading update...' $P::TextFaint $null ''
        Start-Request 'download' "$($asset.browser_download_url)" $file 600
    } catch {
        Show-Message "The update could not be downloaded.`n`n$_" 'Error'
        Show-Latest (Read-UpdateState)
    }
}

function Complete-Download {
    param($Job)
    $asset = $upd.Asset
    if ($Job.Task.IsFaulted -or $Job.Task.IsCanceled) {
        $why = if ($Job.Task.Exception) { $Job.Task.Exception.GetBaseException().Message } else { 'The download was stopped.' }
        Remove-Item -LiteralPath $Job.File -Force -ErrorAction SilentlyContinue
        Show-Message "The update could not be downloaded.`n`n$why" 'Error'
        Show-Latest (Read-UpdateState)
        return
    }

    $want = ("$($asset.digest)" -replace '^sha256:', '').ToLowerInvariant()
    $got  = (Get-FileHash -LiteralPath $Job.File -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($got -ne $want) {
        Remove-Item -LiteralPath $Job.File -Force -ErrorAction SilentlyContinue
        Show-Message ("The downloaded installer does not match the checksum GitHub publishes for it, " +
                      "so it has been deleted and not run.`n`nTry again later, or download it from the " +
                      "release page yourself.") 'Error'
        Show-Latest (Read-UpdateState)
        return
    }

    # The installer stops the watcher, closes this window, replaces the old
    # version and keeps config.json; /RELAUNCH opens the settings again after.
    Set-UpdateStatus 'Installing...' $P::TextFaint $null ''
    try {
        Start-Process -FilePath $Job.File -ArgumentList '/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/RELAUNCH'
    } catch {
        Show-Message "The installer could not be started.`n`n$_" 'Error'
        Show-Latest (Read-UpdateState)
        return
    }
    $form.DialogResult = 'Cancel'
}

$pollTimer = New-Object System.Windows.Forms.Timer
$pollTimer.Interval = 200
$pollTimer.Add_Tick({
    $job = $upd.Job
    if (-not $job) { $pollTimer.Stop(); return }

    if (-not $job.Task.IsCompleted) {
        if ((Get-Date) -gt $job.Deadline) {
            $job.Client.CancelAsync()   # completes the task as cancelled; handled next tick
            $job.Deadline = [datetime]::MaxValue
        } elseif ($job.Kind -eq 'download' -and $upd.Asset.size -gt 0) {
            $have = (Get-Item -LiteralPath $job.File -ErrorAction SilentlyContinue).Length
            if ($have) {
                $pct = [math]::Min(99, [int](100 * $have / $upd.Asset.size))
                Set-UpdateStatus "Downloading update... $pct%" $P::TextFaint $null ''
            }
        }
        return
    }

    $pollTimer.Stop()
    $upd.Job = $null
    $job.Client.Dispose()
    if ($job.Kind -eq 'check') { Complete-UpdateCheck $job } else { Complete-Download $job }
})

$updateLabel.Add_Click({
    switch ($upd.Action) {
        'check'   { Start-UpdateCheck }
        'install' { Invoke-Update }
    }
})

$form.Add_FormClosed({
    $pollTimer.Stop()
    if ($upd.Job) { try { $upd.Job.Client.CancelAsync() } catch { } }
})

# What the header says on opening: a check made in the last day stands, by
# this window or the watcher; otherwise a new one is made now -- unless checks
# are switched off, when the line just offers one.
function Initialize-UpdateStatus {
    $state = Read-UpdateState
    $fresh = $false
    if ($state.LastCheck -and $state.LatestVersion) {
        try {
            $last = [datetime]::Parse($state.LastCheck, $null, 'RoundtripKind').ToLocalTime()
            $fresh = ((Get-Date) - $last).TotalHours -lt 24
        } catch { }
    }
    if ($fresh) {
        Show-Latest $state
    } elseif (ConvertTo-Bool (Get-Setting 'CheckForUpdates' $true)) {
        Start-UpdateCheck
    } else {
        Set-UpdateStatus 'Check for updates' $P::TextFaint 'check' 'Click to ask GitHub for the latest version.'
    }
}

# Nothing is focused to begin with, rather than the first tick box wearing a
# focus edge before anyone has touched the keyboard.
$form.Add_Shown({
    $form.ActiveControl = $null
    Initialize-UpdateStatus
})

$null = $form.ShowDialog()
