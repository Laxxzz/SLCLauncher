# SLCLauncher

**Starts your World of Warcraft tools when the game launches, and can close them when it exits.**

SLCLauncher starts [Archon](https://www.archon.gg/), [WowUp](https://wowup.io/),
[CurseForge](https://www.curseforge.com/), the [Raider.IO](https://raider.io/)
client, WowUtils Bridge and any program of your own when WoW starts. You pick
them in one small settings window, and an invisible background watcher does the
rest. Part of the SLC family of WoW tools, alongside the SimpleLootCouncil addon.

![The SLCLauncher settings window](docs/settings.png)

- **Starts only what you pick.** Apps that aren't installed are skipped, and
  apps already open are left alone.
- **Your own programs too.** Add any `.exe`.
- **Optionally closes them with the game.** That includes apps that hide in the tray.
- **No tray icon, no window, tiny footprint.** One PowerShell process polling
  once a second, about 0.03% CPU.

## Contents

- [Install](#install)
- [The settings window](#the-settings-window)
- [Supported apps](#supported-apps)
- [Your own programs](#your-own-programs)
- [Closing them with the game](#closing-them-with-the-game)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [How it works](#how-it-works)
- [Uninstall](#uninstall)
- [License](#license)

## Install

Windows 10 or 11. You don't need administrator rights or anything else installed first.

1. Download **`SLCLauncher-Setup-<version>.exe`** from
   [Releases](https://github.com/Laxxzz/SLCLauncher/releases) and run it.
2. Leave **Open SLCLauncher to choose your apps** ticked on the last page.
3. Tick your apps and click **Save**.

The installer is unsigned, so Windows may say *"Windows protected your PC"*.
Click **More info → Run anyway**. Running a newer Setup later updates
SLCLauncher and keeps your settings.

**Without the installer:** extract the release zip and double-click
**`Install.cmd`**. It installs exactly the same thing.

Either way you get the watcher in `%LOCALAPPDATA%\SLCLauncher`, started at once
and at every logon by a hidden scheduled task. The settings app is built on your
PC and added to the Start menu.

## The settings window

Open **SLCLauncher** from the Start menu. Tick the apps to start, add your own
programs, and choose whether they close with WoW. **Save** takes effect from the
next game launch. You never need to reinstall or restart anything.

## Supported apps

| App | Notes |
| --- | --- |
| [Archon](https://www.archon.gg/) | Archon's own "launch with game" only works while Archon is already running. See [why](#why-archon-needs-this). |
| [WowUp](https://wowup.io/) | WowUp-CF or the older WowUp. |
| [CurseForge](https://www.curseforge.com/) | The standalone app only. The Overwolf version has no program of its own to start. |
| [Raider.IO](https://raider.io/) client | |
| WowUtils Bridge | |

All are found automatically and ticked by default. A ticked app you don't have is
simply skipped. Addon managers may update your `AddOns` folder mid-session, so
you'll need a `/reload` to see the changes.

## Your own programs

**Add program...** adds any `.exe`. The tick box turns it on and off, and **×**
removes it.

- It isn't searched for. If the program moves, add it again.
- "Already running" means any process with the same file name. Pick the program
  itself, not a launcher that starts it, or it will be started again at every
  launch. Discord is the usual case: leave it running from boot instead.

## Closing them with the game

With **Close them all when WoW closes** ticked, each app is first asked to close,
just as clicking **X** would. Anything still running after `QuitGraceSeconds`
(default 5) is stopped outright, because some apps treat **X** as "hide to tray".
Your own programs are closed only if SLCLauncher started them for that game.

Set `QuitGraceSeconds` to `0` to only ever ask. A forced stop can interrupt an
addon manager halfway through an update.

## Configuration

Everything lives in `%LOCALAPPDATA%\SLCLauncher\config.json`. The watcher reloads
it within a second of a save. Keys the settings window doesn't show are kept.

| Key | Default | Meaning |
| --- | --- | --- |
| `LaunchArchon` … `LaunchWowUtilsBridge` | `true` | Start that app with the game. |
| `CustomApps` | none | Your own programs: `Name`, `Path`, `Enabled`. |
| `ArchonExe` … `WowUtilsBridgeExe` | auto | Full path, only if auto-detection misses the app. |
| `GamePattern` | `^Wow(Classic\|T\|B)?$` | Regex for the game's process name. |
| `PollSeconds` | `1` | Seconds between checks. |
| `LaunchDelaySeconds` | `3` | Wait after spotting the game. |
| `QuitWithWow` | `false` | Close the apps when the game exits. |
| `QuitGraceSeconds` | `5` | Time to close before being stopped. |

An invalid save is logged and ignored. `config.example.json` lists every key. A
`config.json` placed next to `Install.cmd` is applied on each install.

`Install.ps1` also takes `-NoArchon`, `-NoWowUp`, `-NoCurseForge`,
`-NoRaiderIO`, `-NoWowUtilsBridge` and `-QuitWithWow`. Setup also installs
silently with `/VERYSILENT`.

## Troubleshooting

Run **`ViewLog.cmd`** from `%LOCALAPPDATA%\SLCLauncher`. It shows the installed
version, whether the watcher is running, and recent activity. Its startup block
lists every app it manages and where it found it.

- **Nothing logged when WoW starts:** the game's process name doesn't match
  `GamePattern`. Check its `.exe` name in Task Manager → Details.
- **`not installed - skipping` for an app you have:** set its `*Exe` path in
  `config.json`.
- **An app starts but stays behind the game:** it did start. Alt-tab out of
  exclusive fullscreen to see it.
- **"The watcher is not running right now":** it restarts itself within 5
  minutes, or reinstall to start it at once.
- **Setup couldn't finish:** it rolls back. The reason is in
  `%LOCALAPPDATA%\SLCLauncher\install.log`.

## How it works

- **The watcher** (`SLCWatcher.ps1`) checks for the game once a second and starts
  your apps when a new game process appears. A scheduled task starts it at logon
  and revives it every 5 minutes if it has stopped. It runs through a small
  `wscript` shim so no console window ever flashes.
- **The settings app** (`SLCLauncher.exe`) only edits `config.json`. It is
  compiled on your PC from `SLCLauncher.cs` and `SLCTheme.cs` by the C# compiler
  built into Windows. A program built locally from readable source draws less
  suspicion from SmartScreen and antivirus than a downloaded one.
- **Apps are found** from your `config.json` path, then the app's uninstall
  registry entry, then a running copy, then the usual install folders.
- **The installer** is an [Inno Setup](https://jrsoftware.org/isinfo.php)
  wrapper around `Install.ps1` and `Uninstall.ps1`. To build it, install Inno Setup 6
  (`winget install --id JRSoftware.InnoSetup -e --scope user`) and run
  `installer\Build-Installer.ps1`. The result goes to `dist\`.

Nothing here modifies or injects into WoW or any app. It only starts and closes them.

### Why Archon needs this

Archon's "launch with game" setting only brings up the window of an Archon that
is already running. Its game detection lives inside the app, so with Archon
closed nothing is watching for the game. SLCLauncher starts it for you.

## Uninstall

Go to **Settings → Apps → Installed apps → SLCLauncher → Uninstall**. If you
installed from the zip, run `Uninstall.cmd` instead. Either way it removes the
task, the watcher, the Start menu entry and `%LOCALAPPDATA%\SLCLauncher`,
including your settings. The apps it started are not touched.

## License

Copyright (c) 2026 Laxx. All rights reserved. You may install and use SLCLauncher
and privately modify your own copy. Redistributing it, republishing it or
reusing its source needs permission first. See [LICENSE](LICENSE). Copies of
earlier versions released under CC0 (public domain) stay that way.
