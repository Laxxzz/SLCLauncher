# ArchonLauncher

Starts the [Archon App](https://www.archon.gg/) — and your addon manager,
[WowUp](https://wowup.io/) or [CurseForge](https://www.curseforge.com/), the
[Raider.IO](https://raider.io/) client, WowUtils Bridge and any other program
you pick — when World of Warcraft launches.

## The problem

Archon has a **"launch with game"** setting. It does not do what most people
assume: it only opens the window of an **already-running** Archon instance.

The handler behind that setting lives in the app's own UI layer. When it sees a
new game process, it waits a few seconds and then asks Archon's window manager
to open the main window — an operation on a window that already exists. It never
starts a process.

That code can only run if Archon is already running. And Archon ships no
service, no scheduled task, and no resident helper — the Overwolf
game-detection components (`gep`, `overlay`, `recorder`, `utility`) are loaded
*inside* `Archon App.exe` itself. So with Archon closed, nothing on the machine
is watching for the game, and nothing starts it.

You can confirm this in Archon's own log at
`%APPDATA%\Archon App\logs\main.log`: when the feature fires it records a window
action with the reason `Auto Launch on Game Start` — always in a session that
was already running.

The intended flow is that Archon runs from boot via its *Run on startup*
setting and sits in the tray all day. If you would rather it start only when
you actually play, that has to come from outside the app.

## What this does

A small PowerShell watcher, registered as a hidden logon task, checks once a
second for the WoW process and starts Archon when it appears — so Archon only
runs while you're actually playing.

There are two parts, and only one of them is something you open:

- **Archon Launcher** (`ArchonLauncher.exe`) is the settings app — the one in
  the Start menu. It chooses what starts with WoW, and does nothing else; close
  it and nothing of it stays running.
- **The watcher** (`ArchonWatcher.ps1`) does the launching and closing. It runs
  in the background from logon, with no window and no tray icon.

It launches Archon normally, so Archon's own game-version detection, tooltips,
combat log upload and overlay all work exactly as usual.

### The other apps

WowUp, CurseForge, the Raider.IO client and WowUtils Bridge have the same shape
of problem, only more so: none of them has a launch-with-game setting at all.
Their choices are run from boot or open them by hand. So the watcher starts
those too, on the same trigger.

Each one is launched **only if it is installed and not already running**. If you
don't have WowUp, nothing happens for WowUp — it is not an error and there is
nothing to configure. If you have it open already, it is left alone rather than
being nudged into a second window.

All four are found automatically, and each can be switched off in
[Archon Launcher](#the-settings-app).

Two things worth knowing about the addon managers before you leave them on.
They may check for updates on startup and want to write to your `AddOns`
folder — which WoW reads at login, and mid-session addon changes generally need
a `/reload` to take effect. And CurseForge in particular opens a real window,
which with the game in exclusive fullscreen means an alt-tab away. If either
bothers you, turn that one off; Archon on its own is the original behaviour.

### The settings app

Open **Archon Launcher** from the Start menu, or run `ArchonLauncher.exe` in
`%LOCALAPPDATA%\ArchonLauncher`:

- **Start with World of Warcraft** — a tick box for each of WowUp, CurseForge,
  Raider.IO and WowUtils Bridge. Archon is shown ticked and cannot be unticked:
  starting it is the point of the tool.
- **Your own programs** — see [below](#your-own-programs).
- **Close them all when WoW closes** — see [Closing them again](#closing-them-again).

**Save** writes your choices to `config.json` in `%LOCALAPPDATA%\ArchonLauncher`.
The watcher notices the change within a second and reloads it — no reinstall,
no restart — and the new settings apply from the next time the game starts.
Anything already running is left as it is. The log records each reload:

```
[21:14:03] settings changed - reloaded config.json, effective from the next game launch
```

The window only shows the common settings. Everything else in `config.json` —
`GamePattern`, the `*Exe` paths and so on — is written back exactly as it was
found, so hand edits survive a save. Opening it a second time brings the
window already open to the front rather than a second copy.

The installer builds `ArchonLauncher.exe` on your machine from
`ArchonLauncher.cs`, with the C# compiler that is part of Windows' own .NET
Framework, rather than shipping a ready-made program: a downloaded `.exe` is
exactly what SmartScreen and antivirus look hardest at, while one built from
source you can read is plainly what it says it is. The window itself is
`ArchonLauncherOptions.ps1`, run inside the program, so it shows in Task
Manager and on the taskbar as Archon Launcher with its own icon, and with no
console window behind it.

### Your own programs

**Add program...** picks any `.exe` to start with WoW alongside the rest — a
voice client, a stream tool, a timer. It is named after the description the
program gives itself, and its tick box switches it on and off without losing
it from the list.

They follow the same rules as the built-in apps, with two differences that come
from knowing a program only by its path:

- **It is not searched for.** If the file is not where you said, the log reads
  `not found at <path> - skipping` and the rest carry on. An update that moves
  the program means adding it again.
- **"Already running" means a process with the same file name.** Pick the
  program itself, not a launcher or updater that starts it: a launcher's own
  process is gone a moment later, so it looks "not running" at every game start
  and gets started again each time. Discord is the common case — its shortcut
  runs `Update.exe`, which starts `Discord.exe` from a folder named after the
  version, so neither path makes a good choice. Leave Discord running from boot
  instead.

Closing with WoW is also narrower for these: see
[Closing them again](#closing-them-again).

### What it costs

Measured on a 16-core desktop with ~262 running processes, at the default
1-second interval, once past startup:

| | Watcher | Archon App idling |
| --- | --- | --- |
| Processes | 1 | 13 |
| Private memory | ~103 MB | ~1,622 MB |
| CPU | 94 ms per 20 s — 0.47% of one core, **0.029% of all cores** | — |

Each check takes roughly 4 ms to enumerate every process on the system. Raising
`PollSeconds` to `5` cuts the CPU by five times, to about 0.005% of all cores —
but both figures are far below the noise floor of normal desktop activity, so
pick the interval for responsiveness rather than for performance.

The memory is PowerShell's runtime rather than the script itself. It is roughly
a sixteenth of what Archon uses sitting idle, which is the trade this tool
exists to make.

## Install

No administrator rights needed, and no typing commands. The task runs as the
current user only.

1. Download the zip and **extract it** (right-click → Extract All). Don't run it
   from inside the zip.
2. Double-click **`Install.cmd`** and answer **Y** to `Install Archon Launcher?`
3. Tick what you want in the [Archon Launcher](#the-settings-app) window that
   opens, and click **Save**.

Answering **N** cancels immediately, without touching a single file.

That window is the same one the Start menu opens, so every choice can be
changed there later without reinstalling. The apps are all ticked
to begin with, whatever you have installed, and leaving one ticked that you
don't own costs nothing: the watcher notes `not installed - skipping` and gets
on with the rest.

Running `Install.cmd` again — to update, say — keeps what you chose. If you are
upgrading from 1.4.x, the answers you gave its installer are carried over too.
The installer confirms what it registered:

```
  starts  -> Archon, plus WowUp, CurseForge, Raider.IO and WowUtils Bridge if installed
```

Windows may show *"Windows protected your PC"* because the file came from the
internet. Click **More info → Run anyway**. The installer clears that mark from
the other files itself.

The installer copies the watcher to `%LOCALAPPDATA%\ArchonLauncher`, registers a
hidden logon task, starts it immediately — no reboot required — then builds
`ArchonLauncher.exe` beside it and adds **Archon Launcher** to the Start menu.
Upgrading from 1.4.x also removes the old watcher file, which was called
`ArchonLauncher.ps1` before that name went to the settings app.

The task also carries a **heartbeat**: every 5 minutes Windows checks the
watcher is still alive and restarts it if not. Without that, anything which
kills the process — a reinstall, a manual kill, a security tool — would leave
it dead until your next logon, and silently, since a dead watcher looks exactly
like one that simply hasn't seen the game yet. A mutex inside the script keeps
duplicate starts from stacking up, so a heartbeat that fires while the watcher
is healthy costs nothing.

Nothing appears on screen. The task runs `wscript.exe` against a small shim
rather than `powershell.exe` directly, because Task Scheduler gives a console
process a console window every time it fires — `-WindowStyle Hidden` does not
prevent that, since the console is allocated before the script runs.

Double-click **`ViewLog.cmd`** any time to see what it has been doing.

### Command line

If you prefer it, or want to script the install:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1            # basic
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -QuitWithWow
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -NoCurseForge -NoWowUp
```

`-NoWowUp`, `-NoCurseForge`, `-NoRaiderIO` and `-NoWowUtilsBridge` untick that
app and `-QuitWithWow` ticks the close box, exactly as if you had done it in
Archon Launcher: they are written into `config.json`, and anything they don't
mention keeps its current setting. `-OpenSettings` opens Archon Launcher
afterwards, which is what `Install.cmd` passes. `Install.cmd` with any
arguments hands them straight to `Install.ps1` and does not open the window.

## Uninstall

Double-click **`Uninstall.cmd`** and confirm.

Removes the task, stops the watcher, closes Archon Launcher if it is open,
removes it from the Start menu, and
deletes `%LOCALAPPDATA%\ArchonLauncher` — your settings included. The apps it
starts are left exactly as they are — this uninstalls the watcher, not them.

Command-line equivalent, with `-KeepFiles` to leave the folder, and so your
settings, in place:

```powershell
powershell -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

## Configuration

Optional — [Archon Launcher](#the-settings-app) covers the common settings.
The rest live in the same file, `config.json` in
`%LOCALAPPDATA%\ArchonLauncher`, which you can edit by hand; the watcher reloads
it within a second of a save, just as it does for Archon Launcher. Empty or
missing values fall back to the defaults:

```json
{
  "ArchonExe":            "C:\\Program Files\\Archon App\\Archon App.exe",
  "WowUpExe":             "",
  "CurseForgeExe":        "",
  "RaiderIOExe":          "",
  "WowUtilsBridgeExe":    "",
  "LaunchWowUp":          true,
  "LaunchCurseForge":     true,
  "LaunchRaiderIO":       true,
  "LaunchWowUtilsBridge": true,
  "CustomApps": [
    { "Name": "OBS Studio", "Path": "C:\\Program Files\\obs-studio\\bin\\64bit\\obs64.exe", "Enabled": true }
  ],
  "GamePattern":          "^Wow(Classic|T|B)?$",
  "PollSeconds":          1,
  "LaunchDelaySeconds":   3,
  "QuitWithWow":          false,
  "QuitGraceSeconds":     5
}
```

| Key | Default | Meaning |
| --- | --- | --- |
| `ArchonExe` | auto-detected | Path to `Archon App.exe`. See [How the apps are found](#how-the-apps-are-found). |
| `WowUpExe` | auto-detected | Path to `WowUp-CF.exe` or `WowUp.exe`. |
| `CurseForgeExe` | auto-detected | Path to `CurseForge.exe`. |
| `RaiderIOExe` | auto-detected | Path to `RaiderIO.exe`. |
| `WowUtilsBridgeExe` | auto-detected | Path to `WowUtils.Bridge.App.exe`. |
| `LaunchWowUp` | `true` | Start WowUp too, when it is installed. |
| `LaunchCurseForge` | `true` | Start CurseForge too, when it is installed. |
| `LaunchRaiderIO` | `true` | Start the Raider.IO client too, when it is installed. |
| `LaunchWowUtilsBridge` | `true` | Start WowUtils Bridge too, when it is installed. |
| `CustomApps` | none | [Your own programs](#your-own-programs). `Name` is what the log calls it and defaults to the file name; `Enabled` defaults to `true`. |
| `GamePattern` | `^Wow(Classic\|T\|B)?$` | Regex against process names, no `.exe`. Covers retail, Classic, PTR (`WowT`), beta (`WowB`). |
| `PollSeconds` | `1` | Seconds between checks. Minimum `1`. |
| `LaunchDelaySeconds` | `3` | Wait this long after spotting the game before starting the apps. `0` launches immediately. |
| `QuitWithWow` | `false` | Close the apps when the game exits. |
| `QuitGraceSeconds` | `5` | How long an app gets to close on its own before it is stopped outright. `0` only ever asks. See [Closing them again](#closing-them-again). |

To watch retail only, set `GamePattern` to `^Wow$`.

A save that leaves the file unreadable, or `GamePattern` an invalid regex, is
logged and ignored: the watcher keeps the settings it already had rather than
dropping back to the defaults.

To set things up before installing — for several machines, say — put a
`config.json` next to `Install.cmd`. The installer applies each key in it over
your current settings, so it can set a few keys without disturbing the rest.
It does that on every run, though, so take it away afterwards if you would
rather Archon Launcher had the last word. `config.example.json` has the
keys and their defaults.

The `*Exe` keys exist for the rare install that auto-detection misses, and are
better left empty otherwise — an empty value means "find it", not "don't launch
it", so blanking a path does not switch an app off.

### Closing them again

`QuitWithWow` first *asks* each app to close, by sending its main window the
same message clicking the X does. Archon and CurseForge take that as "exit".
WowUp, by default, takes it as **"hide to the system tray"** — it obeys and
keeps running, which made "close all of them" quietly untrue for one app.
WowUtils Bridge does the same, and the Raider.IO client sitting in the tray has
no window to ask at all.

So asking is only the first move. Anything still running `QuitGraceSeconds`
later is stopped outright:

```
[05:07:59] asked WowUp to close
[05:08:04] WowUp ignored the close request - stopped it
```

The grace window is shared by all of them rather than spent on each in turn,
and apps that exit politely never reach the second step — the log just shows the
`asked` lines and nothing more.

[Your own programs](#your-own-programs) are closed only if the watcher started
them for this game. They are recognised by file name, and closing every
`chrome.exe` because WoW exited would take the browser you had open all along.
The built-in apps are closed whoever started them, as before.

Set `QuitGraceSeconds` to `0` to go back to asking only. Worth doing if you'd
rather a mid-flight addon update was never interrupted: a forced stop is a
forced stop, and an addon manager caught halfway through writing to your
`AddOns` folder will not finish the job. Five seconds of grace makes that
unlikely, not impossible. The alternative that costs nothing is to turn off
close-to-tray in WowUp's own settings, after which it exits when asked and the
timeout never fires.

### How the apps are found

The `*Exe` keys are optional because the watcher locates each app itself. Their
installers all register an uninstall entry, so one search serves all of them,
trying these in order and taking the first that exists on disk:

1. **The path from `config.json`**, if you set one.
2. **The uninstall registry entry**, which is checked three ways —
   `InstallLocation`, then `DisplayIcon` (the executable plus an icon index),
   then the directory containing `UninstallString`. Archon, WowUp, CurseForge
   and Raider.IO are electron-builder installs that ship `InstallLocation`
   empty, so the second is what resolves them today; WowUtils Bridge fills it
   in, so the first resolves that one.
3. **A running process** of that app, whose own image path is ground truth.
4. **The usual install locations**, as a last resort.

Archon is required: if it cannot be found at all the watcher logs `FATAL` and
stops, because starting Archon is the job. The others are optional, so not
finding one just logs `not installed - skipping` and the watcher carries on
with the rest. [Your own programs](#your-own-programs) skip all of this: the
path you gave is the only place they are looked for.

If a resolved path stops existing — an update relocating the install, for
instance — the watcher re-runs the whole chain at launch time rather than
failing on a stale path. You'll see `re-resolving` in the log when that happens.
An app installed *after* the watcher started is picked up too: anything still
unresolved is looked for again each time the game launches, so installing WowUp
tomorrow does not require a reboot.

### About the timing

The delay runs from when the watcher *spots* the game, not from the instant WoW
starts — those differ by up to `PollSeconds`. At the defaults that gap is at
most a second, so the apps appear **3–4 seconds** after you launch WoW. There is
one delay, not one per app: they are all started together once it has elapsed.

Want it to wait longer before appearing? Raise `LaunchDelaySeconds`. Raising
`PollSeconds` instead makes the timing less predictable, since it widens the
window between the game starting and the watcher noticing.

## Verifying / troubleshooting

Double-click **`ViewLog.cmd`**. It reports the installed version, whether the
watcher is running, and recent activity:

```
  Installed version : 1.3.1
  Watcher           : RUNNING (pid 27612)
  Scheduled task    : installed
```

The version is read from the installed script rather than from this folder, so
it tells you what is actually running — useful if an older copy is still lying
around somewhere. A healthy log looks like:

```
[2026-08-15 22:05:16] watcher started (pid 24196)
[2026-08-15 22:05:16] version   : 1.5.0
[2026-08-15 22:05:16] Archon    : C:\Program Files\Archon App\Archon App.exe
[2026-08-15 22:05:16] WowUp     : C:\Users\me\AppData\Local\Programs\wowup-cf\WowUp-CF.exe
[2026-08-15 22:05:16] CurseForge: not installed - skipping
[2026-08-15 22:05:16] Raider.IO : C:\Program Files\RaiderIO\RaiderIO.exe
[2026-08-15 22:05:16] WowUtils Bridge: C:\Users\me\AppData\Local\Programs\WowUtils Bridge\WowUtils.Bridge.App.exe
[2026-08-15 22:05:16] watching  : ^Wow(Classic|T|B)?$  every 1s
[2026-08-15 22:05:16] delay     : 3s after the game is spotted
[2026-08-15 22:05:16] quit-with-wow: off
[2026-08-15 22:18:41] game detected (pid 1640)
[2026-08-15 22:18:41] already running: WowUtils Bridge
[2026-08-15 22:18:41] waiting 3s before launching
[2026-08-15 22:18:44] launched C:\Program Files\Archon App\Archon App.exe
[2026-08-15 22:18:44] launched C:\Users\me\AppData\Local\Programs\wowup-cf\WowUp-CF.exe
[2026-08-15 22:18:44] launched C:\Program Files\RaiderIO\RaiderIO.exe
[2026-08-15 23:47:02] game exited
```

The startup block lists every app it will manage and where it found each one,
so it is the first place to look if something isn't starting. Anything already
open when the game launches is reported as `already running: Archon` and left
alone, which is also correct — and if everything is already up you get
`nothing left to launch`.

**Nothing in the log after launching WoW** — the process name probably doesn't
match. Open Task Manager → Details while the game is running, note the exact
`.exe` name, and set `GamePattern` in `%LOCALAPPDATA%\ArchonLauncher\config.json`
to match it (without the `.exe`). The watcher picks the change up by itself.

**`FATAL: could not locate "Archon App.exe"`** — set `ArchonExe` in
`%LOCALAPPDATA%\ArchonLauncher\config.json` to the full path. A watcher that
stopped on this is restarted by the heartbeat within 5 minutes, or run
`Install.cmd` to start it now.

**One of the apps doesn't start, and the log says `not installed -
skipping`.** Auto-detection found no install. If you do have it, set its `*Exe`
key in `%LOCALAPPDATA%\ArchonLauncher\config.json` to the full path of the
executable. The likeliest cause is a CurseForge that runs *inside* Overwolf
rather than as the standalone app: that one has no `CurseForge.exe` of its own
to start, and this tool cannot launch it.

**They start when I don't want them to.** Untick that app in
**Archon Launcher**. Note that emptying its `*Exe` key in `config.json`
does *not* do this — an empty path means auto-detect.

**A program of my own starts every time, even when it is already open.** You
picked a launcher rather than the program. See
[Your own programs](#your-own-programs).

**`QuitWithWow` left one of them running.** Expected before 1.4.1, and WowUp was
almost always the one: it treats a close request as "hide to the tray" and
stayed alive having done as it was asked. From 1.4.1 anything still up after
`QuitGraceSeconds` is stopped outright, so the log reads
`WowUp ignored the close request - stopped it`. See
[Closing them again](#closing-them-again) if you'd rather it only ever asked.

**Archon starts but stays behind the game** — that is Archon's own behaviour.
It opens its window *without* taking focus, so with the game in exclusive
fullscreen you won't see it until you alt-tab. Nothing to fix here; it did
start.

**It worked for a while and then quietly stopped.** The watcher process was
killed at some point. `ViewLog.cmd` shows this as a log that just stops — a
`game detected` with no `launched` line after it, and no later entries. From
version 1.2.0 the heartbeat restarts it within 5 minutes on its own; before
that it stayed dead until the next logon. Run `Install.cmd` once to pick up the
heartbeat.

**`ViewLog.cmd` says `Watcher: NOT RUNNING`** — the heartbeat should start it
within 5 minutes; `Install.cmd` starts it immediately. Note that the *task*
showing as `Ready` rather than `Running` is normal and not a fault: the shim
exits as soon as it has started the watcher, so task state says nothing about
health. `ViewLog.cmd` reports the watcher process itself, which is the thing
that matters.

**You started the game before the watcher was running.** The watcher catches up
on startup: if the game is already running and Archon is not, it launches
straight away rather than waiting for a launch that already happened. Versions
before 1.3.0 went dormant for the rest of the session in that situation.

**The game restarted and Archon didn't come back.** Fixed in 1.3.2. Detection
tracks process IDs rather than merely whether *a* matching process exists,
because a restarting game can have the old process still shutting down as the
new one starts — leaving no instant where nothing matched, and so no launch to
detect. The log now names the process: `game detected (pid 1640)`.

Note that if one of the apps closes on its own while the game keeps running, the
watcher will not restart it — it acts on the game starting, not on an app
disappearing.

**The log has no history from previous days, or my options are back to the
defaults.** `Uninstall.cmd` deletes `%LOCALAPPDATA%\ArchonLauncher`, log and
settings included, so an uninstall/reinstall cycle starts both fresh. That's
expected, not a fault; reinstalling over the top instead keeps them.

## Notes

- Windows 10/11, PowerShell 5.1 (the built-in one). No modules required, and
  nothing to download: the compiler that builds `ArchonLauncher.exe` is part of
  the .NET Framework that ships with Windows.
- Polling, not process-creation events. Event-driven detection needs
  administrator rights or an audit-policy change, and the measured cost of
  polling doesn't justify either.
- Nothing here modifies, patches, or injects into Archon, the other apps or
  WoW. It only calls `Start-Process` on their executables — and, with
  `QuitWithWow`, asks their windows to close, then stops whatever ignored the
  request.
- Adding more apps costs nothing per poll. The extra work happens only when the
  game launches, not once a second. What each poll does gain is one look at
  `config.json`'s timestamp, to notice a save — a single file lookup, far below
  the process scan beside it — so the figures above still hold.

## License

Public domain / CC0. Do whatever you like with it.
