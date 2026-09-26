<#
.SYNOPSIS
    The SLCLauncher settings window.

.DESCRIPTION
    Edits config.json in %LOCALAPPDATA%\SLCLauncher: which apps start with
    World of Warcraft, whether they close with it, and any programs of your own.

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

# The built-in apps, in the order they are shown.
$builtIns = @(
    @{ Key = 'LaunchArchon';         Label = 'Archon App' },
    @{ Key = 'LaunchWowUp';          Label = 'WowUp' },
    @{ Key = 'LaunchCurseForge';     Label = 'CurseForge' },
    @{ Key = 'LaunchRaiderIO';       Label = 'Raider.IO' },
    @{ Key = 'LaunchWowUtilsBridge'; Label = 'WowUtils Bridge' }
)

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

# -------------------------------------------------------------------- body --
$body = New-Stack
$body.Padding = New-Object System.Windows.Forms.Padding($pad, (S 4), $pad, $pad)
$page.Controls.Add($body)

# ------------------------------------------------------- the built-in apps --
$apps = Add-Section 'Start with World of Warcraft'

$appBoxes = @{}
foreach ($b in $builtIns) {
    $box = New-Check $b.Label (ConvertTo-Bool (Get-Setting $b.Key $true))
    $apps.Controls.Add($box)
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

# Nothing is focused to begin with, rather than the first tick box wearing a
# focus edge before anyone has touched the keyboard.
$form.Add_Shown({ $form.ActiveControl = $null })

$null = $form.ShowDialog()
