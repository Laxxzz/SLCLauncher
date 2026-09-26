<#
.SYNOPSIS
    The Archon Launcher settings window.

.DESCRIPTION
    Edits config.json in %LOCALAPPDATA%\ArchonLauncher: which apps start with
    World of Warcraft, whether they close with it, and any programs of your own.

    The watcher notices the saved file within a second and reloads it without a
    restart; the new settings take effect the next time the game starts. Keys
    this window does not show -- GamePattern, the *Exe paths and so on -- are
    written back exactly as they were found.

    ArchonLauncher.exe runs this inside its own process; that is what the Start
    menu shortcut opens. It can equally be run with powershell.exe -STA -File,
    at the cost of a console window behind it.

.PARAMETER InstallDir
    The folder holding the watcher and its config.json. Defaults to where the
    installer puts them; pointing it elsewhere is for trying the window out
    without touching a real install.
#>
[CmdletBinding()]
param(
    [string] $InstallDir = (Join-Path $env:LOCALAPPDATA 'ArchonLauncher')
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

# Without this Windows draws the window at 96 DPI and stretches the bitmap,
# which reads as blurry text on any display scaled above 100%.
Add-Type -Namespace ArchonLauncher -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
'@
$null = [ArchonLauncher.Native]::SetProcessDPIAware()
[System.Windows.Forms.Application]::EnableVisualStyles()

$installDir = $InstallDir
$configPath = Join-Path $installDir 'config.json'

function Show-Message {
    param([string]$Text, [string]$Icon = 'Information')
    $null = [System.Windows.Forms.MessageBox]::Show($Text, 'Archon Launcher', 'OK', $Icon)
}

if (-not (Test-Path (Join-Path $installDir 'ArchonWatcher.ps1'))) {
    Show-Message "Archon Launcher is not installed.`n`nRun Install.cmd first, then open Archon Launcher again." 'Warning'
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

# The optional apps, in the order they are shown. Archon is not among them:
# starting it is the point of the tool, so it is shown ticked and fixed.
$builtIns = @(
    @{ Key = 'LaunchWowUp';          Label = 'WowUp' },
    @{ Key = 'LaunchCurseForge';     Label = 'CurseForge' },
    @{ Key = 'LaunchRaiderIO';       Label = 'Raider.IO' },
    @{ Key = 'LaunchWowUtilsBridge'; Label = 'WowUtils Bridge' }
)

# ------------------------------------------------------------------ window --
$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Archon Launcher'
$form.Font            = New-Object System.Drawing.Font('Segoe UI', 9)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox     = $false
$form.StartPosition   = 'CenterScreen'
$form.AutoSize        = $true
$form.AutoSizeMode    = 'GrowAndShrink'
$form.Padding         = New-Object System.Windows.Forms.Padding(12)

# Fixed sizes are given at 96 DPI and scaled; everything else sizes itself
# from the font, which is already the right size for the display.
$scale = $form.CreateGraphics().DpiX / 96
function S { param([int]$Px) [int][math]::Round($Px * $scale) }

# The taskbar shows the window's icon, not the file's, so the icon embedded in
# ArchonLauncher.exe has to be given to the window as well. The .ico carries
# every size, and Windows picks the one each place needs.
$iconPath = Join-Path $PSScriptRoot 'ArchonLauncher.ico'
if (Test-Path $iconPath) {
    $form.Icon = New-Object System.Drawing.Icon($iconPath)
}

$root = New-Object System.Windows.Forms.TableLayoutPanel
$root.AutoSize     = $true
$root.AutoSizeMode = 'GrowAndShrink'
$root.ColumnCount  = 1
$form.Controls.Add($root)

function Add-Row {
    param($Control)
    $Control.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, (S 10))
    $root.Controls.Add($Control)
}

function New-Group {
    param([string]$Title)
    $g = New-Object System.Windows.Forms.GroupBox
    $g.Text         = $Title
    $g.AutoSize     = $true
    $g.AutoSizeMode = 'GrowAndShrink'
    $g.Padding      = New-Object System.Windows.Forms.Padding((S 10), (S 6), (S 10), (S 8))
    $g.Dock         = 'Fill'
    $flow = New-Object System.Windows.Forms.FlowLayoutPanel
    $flow.FlowDirection = 'TopDown'
    $flow.WrapContents  = $false
    $flow.AutoSize      = $true
    $flow.AutoSizeMode  = 'GrowAndShrink'
    $flow.Dock          = 'Fill'
    $g.Controls.Add($flow)
    return $g, $flow
}

function New-Note {
    param([string]$Text)
    $l = New-Object System.Windows.Forms.Label
    $l.Text        = $Text
    $l.AutoSize    = $true
    $l.MaximumSize = New-Object System.Drawing.Size((S 440), 0)
    $l.ForeColor   = [System.Drawing.SystemColors]::GrayText
    return $l
}

# ------------------------------------------------------- the built-in apps --
$appsGroup, $appsFlow = New-Group 'Start with World of Warcraft'
Add-Row $appsGroup

$archonBox = New-Object System.Windows.Forms.CheckBox
$archonBox.Text     = 'Archon App (always)'
$archonBox.Checked  = $true
$archonBox.Enabled  = $false
$archonBox.AutoSize = $true
$appsFlow.Controls.Add($archonBox)

$appBoxes = @{}
foreach ($b in $builtIns) {
    $box = New-Object System.Windows.Forms.CheckBox
    $box.Text     = $b.Label
    $box.Checked  = ConvertTo-Bool (Get-Setting $b.Key $true)
    $box.AutoSize = $true
    $appsFlow.Controls.Add($box)
    $appBoxes[$b.Key] = $box
}
$appsFlow.Controls.Add((New-Note 'Anything ticked that is not installed is skipped.'))

# ------------------------------------------------------ your own programs ---
$customGroup, $customFlow = New-Group 'Your own programs'
Add-Row $customGroup

$list = New-Object System.Windows.Forms.ListView
$list.View          = 'Details'
$list.CheckBoxes    = $true
$list.FullRowSelect = $true
$list.HeaderStyle   = 'Nonclickable'
$list.Size          = New-Object System.Drawing.Size((S 440), (S 120))
$null = $list.Columns.Add('Program', (S 140))
$null = $list.Columns.Add('Path', (S 276))
$customFlow.Controls.Add($list)

function Add-CustomItem {
    param([string]$Name, [string]$Path, [bool]$Enabled)
    $item = New-Object System.Windows.Forms.ListViewItem($Name)
    $null = $item.SubItems.Add($Path)
    $item.Checked     = $Enabled
    $item.ToolTipText = $Path
    $null = $list.Items.Add($item)
    return $item
}

foreach ($a in @(Get-Setting 'CustomApps' @())) {
    if ($null -eq $a -or -not "$($a.Path)".Trim()) { continue }
    $path = "$($a.Path)".Trim()
    $name = "$($a.Name)".Trim()
    if (-not $name) { $name = [System.IO.Path]::GetFileNameWithoutExtension($path) }
    $enabled = ($null -eq $a.Enabled) -or (ConvertTo-Bool $a.Enabled)
    $null = Add-CustomItem $name $path $enabled
}
$list.ShowItemToolTips = $true

$buttons = New-Object System.Windows.Forms.FlowLayoutPanel
$buttons.AutoSize     = $true
$buttons.AutoSizeMode = 'GrowAndShrink'
$buttons.Margin       = New-Object System.Windows.Forms.Padding(0, (S 6), 0, 0)
$customFlow.Controls.Add($buttons)

$addButton = New-Object System.Windows.Forms.Button
$addButton.Text     = 'Add program...'
$addButton.AutoSize = $true
$buttons.Controls.Add($addButton)

$removeButton = New-Object System.Windows.Forms.Button
$removeButton.Text     = 'Remove'
$removeButton.AutoSize = $true
$removeButton.Enabled  = $false
$buttons.Controls.Add($removeButton)

$customFlow.Controls.Add((New-Note ('Ticked programs start with WoW unless they are already running. ' +
    'Pick the program itself, not a launcher or updater that starts it.')))

$list.Add_SelectedIndexChanged({ $removeButton.Enabled = $list.SelectedItems.Count -gt 0 })

$addButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title  = 'Choose a program to start with World of Warcraft'
    $dialog.Filter = 'Programs (*.exe)|*.exe'
    $dialog.InitialDirectory = $env:ProgramFiles
    if ($dialog.ShowDialog($form) -ne 'OK') { return }
    $path = $dialog.FileName

    foreach ($existing in $list.Items) {
        if ($existing.SubItems[1].Text -eq $path) {
            $existing.Checked  = $true
            $existing.Selected = $true
            $existing.EnsureVisible()
            return
        }
    }

    # The name the program gives itself reads better than its file name:
    # "Microsoft Edge" rather than "msedge".
    $name = $null
    try { $name = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path).FileDescription } catch { }
    if (-not "$name".Trim()) { $name = [System.IO.Path]::GetFileNameWithoutExtension($path) }

    $item = Add-CustomItem "$name".Trim() $path $true
    $item.Selected = $true
    $item.EnsureVisible()
})

$removeButton.Add_Click({
    foreach ($item in @($list.SelectedItems)) { $list.Items.Remove($item) }
})

# ---------------------------------------------------------- close with WoW --
$quitBox = New-Object System.Windows.Forms.CheckBox
$quitBox.Text     = 'Close them all when WoW closes'
$quitBox.Checked  = ConvertTo-Bool (Get-Setting 'QuitWithWow' $false)
$quitBox.AutoSize = $true
Add-Row $quitBox

# ------------------------------------------------------------------ footer --
$footer = New-Object System.Windows.Forms.TableLayoutPanel
$footer.AutoSize     = $true
$footer.AutoSizeMode = 'GrowAndShrink'
$footer.ColumnCount  = 3
$footer.Dock         = 'Fill'
$footer.Margin       = New-Object System.Windows.Forms.Padding(0)
$null = $footer.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
$null = $footer.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize')))
$null = $footer.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize')))
$root.Controls.Add($footer)

# The same check ViewLog.cmd makes.
$watcher = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
           Where-Object { $_.CommandLine -like '*ArchonWatcher.ps1*' } |
           Select-Object -First 1
$status = New-Object System.Windows.Forms.Label
$status.AutoSize = $true
$status.Anchor   = 'Left'
if ($watcher) {
    $status.Text = 'Changes apply the next time WoW starts.'
} else {
    $status.Text      = 'The watcher is not running right now.'
    $status.ForeColor = [System.Drawing.Color]::Firebrick
}
$footer.Controls.Add($status, 0, 0)

$saveButton = New-Object System.Windows.Forms.Button
$saveButton.Text     = 'Save'
$saveButton.AutoSize = $true
$footer.Controls.Add($saveButton, 1, 0)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text         = 'Cancel'
$cancelButton.AutoSize     = $true
$cancelButton.DialogResult = 'Cancel'
$footer.Controls.Add($cancelButton, 2, 0)

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
    foreach ($item in $list.Items) {
        $custom += [pscustomobject][ordered]@{
            Name    = $item.Text
            Path    = $item.SubItems[1].Text
            Enabled = $item.Checked
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


$null = $form.ShowDialog()
