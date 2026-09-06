# ArchonLauncher

Starts the [Archon App](https://www.archon.gg/) — and your addon manager,
[WowUp](https://wowup.io/) or [CurseForge](https://www.curseforge.com/), if you
have one — when World of Warcraft launches.

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

It launches Archon normally, so Archon's own game-version detection, tooltips,
combat log upload and overlay all work exactly as usual.

### The addon managers

WowUp and CurseForge have the same shape of problem, only more so: neither has
a launch-with-game setting at all. Their choices are run from boot or open them
by hand. So the watcher starts those too, on the same trigger.

Each one is launched **only if it is installed and not already running**. If you
don't have WowUp, nothing happens for WowUp — it is not an error and there is
nothing to configure. If you have it open already, it is left alone rather than
being nudged into a second window.

Both are found automatically, and both can be switched off:

```json
{ "LaunchWowUp": false, "LaunchCurseForge": false }
```

Two things worth knowing before you leave them on. These are addon *managers*,
so they may check for updates on startup and want to write to your `AddOns`
folder — which WoW reads at login, and mid-session addon changes generally need
a `/reload` to take effect. And CurseForge in particular opens a real window,
which with the game in exclusive fullscreen means an alt-tab away. If either
bothers you, turn that one off; Archon on its own is the original behaviour.

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
2. Double-click **`Install.cmd`**.
3. Answer the one question it asks, and you're done.

Windows may show *"Windows protected your PC"* because the file came from the
internet. Click **More info → Run anyway**. The installer clears that mark from
the other files itself.

The installer copies the watcher to `%LOCALAPPDATA%\ArchonLauncher`, registers a
hidden logon task, and starts it immediately — no reboot required.

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

`-NoWowUp` and `-NoCurseForge` do the same job as the `LaunchWowUp` and
`LaunchCurseForge` config keys, for when you would rather not keep a
`config.json` around.

## Uninstall

Double-click **`Uninstall.cmd`** and confirm.

Removes the task, stops the watcher, and deletes `%LOCALAPPDATA%\ArchonLauncher`.
Archon, WowUp and CurseForge are left exactly as they are — this uninstalls the
watcher, not the apps it starts.

Command-line equivalent, with `-KeepFiles` to leave the folder in place:

```powershell
powershell -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

## Configuration

Optional. Copy `config.example.json` to `config.json` next to
`ArchonLauncher.ps1` **before** running `Install.cmd`, and it gets installed
along with the script. Empty or missing values fall back to the defaults:

```json
{
  "ArchonExe":          "C:\\Program Files\\Archon App\\Archon App.exe",
  "WowUpExe":           "",
  "CurseForgeExe":      "",
  "LaunchWowUp":        true,
  "LaunchCurseForge":   true,
  "GamePattern":        "^Wow(Classic|T|B)?$",
  "PollSeconds":        1,
  "LaunchDelaySeconds": 3,
  "QuitWithWow":        false
}
```

| Key | Default | Meaning |
| --- | --- | --- |
| `ArchonExe` | auto-detected | Path to `Archon App.exe`. See [How the apps are found](#how-the-apps-are-found). |
| `WowUpExe` | auto-detected | Path to `WowUp-CF.exe` or `WowUp.exe`. |
| `CurseForgeExe` | auto-detected | Path to `CurseForge.exe`. |
| `LaunchWowUp` | `true` | Start WowUp too, when it is installed. |
| `LaunchCurseForge` | `true` | Start CurseForge too, when it is installed. |
| `GamePattern` | `^Wow(Classic\|T\|B)?$` | Regex against process names, no `.exe`. Covers retail, Classic, PTR (`WowT`), beta (`WowB`). |
| `PollSeconds` | `1` | Seconds between checks. Minimum `1`. |
| `LaunchDelaySeconds` | `3` | Wait this long after spotting the game before starting the apps. `0` launches immediately. |
| `QuitWithWow` | `false` | Close the apps when the game exits. |

To watch retail only, set `GamePattern` to `^Wow$`.

The two `Launch*` keys are the ones to reach for. The `*Exe` keys exist for the
rare install that auto-detection misses, and are better left empty otherwise —
an empty value means "find it", not "don't launch it", so blanking a path does
not switch an app off.

### How the apps are found

The `*Exe` keys are optional because the watcher locates each app itself. All
three are electron-builder installs that describe themselves the same way, so
one search serves all three, trying these in order and taking the first that
exists on disk:

1. **The path from `config.json`**, if you set one.
2. **The uninstall registry entry**, which is checked three ways —
   `InstallLocation`, then `DisplayIcon` (the executable plus an icon index),
   then the directory containing `UninstallString`. All three apps ship
   `InstallLocation` empty, so the second is what actually resolves them today.
3. **A running process** of that app, whose own image path is ground truth.
4. **The usual install locations**, as a last resort.

Archon is required: if it cannot be found at all the watcher logs `FATAL` and
stops, because starting Archon is the job. WowUp and CurseForge are optional, so
not finding them just logs `not installed - skipping` and the watcher carries on
with the rest.

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
[2026-08-15 22:05:16] version   : 1.4.0
[2026-08-15 22:05:16] Archon    : C:\Program Files\Archon App\Archon App.exe
[2026-08-15 22:05:16] WowUp     : C:\Users\me\AppData\Local\Programs\wowup-cf\WowUp-CF.exe
[2026-08-15 22:05:16] CurseForge: not installed - skipping
[2026-08-15 22:05:16] watching  : ^Wow(Classic|T|B)?$  every 1s
[2026-08-15 22:05:16] delay     : 3s after the game is spotted
[2026-08-15 22:18:41] game detected (pid 1640)
[2026-08-15 22:18:41] waiting 3s before launching
[2026-08-15 22:18:44] launched C:\Program Files\Archon App\Archon App.exe
[2026-08-15 22:18:44] launched C:\Users\me\AppData\Local\Programs\wowup-cf\WowUp-CF.exe
[2026-08-15 23:47:02] game exited
```

The startup block lists every app it will manage and where it found each one,
so it is the first place to look if something isn't starting. Anything already
open when the game launches is reported as `already running: Archon` and left
alone, which is also correct — and if everything is already up you get
`nothing left to launch`.

**Nothing in the log after launching WoW** — the process name probably doesn't
match. Open Task Manager → Details while the game is running, note the exact
`.exe` name, and set `GamePattern` in `config.json` to match it (without the
`.exe`). Then run `Install.cmd` again.

**`FATAL: could not locate "Archon App.exe"`** — set `ArchonExe` in
`config.json` to the full path, then run `Install.cmd` again.

**WowUp or CurseForge doesn't start, and the log says `not installed -
skipping`.** Auto-detection found no install. If you do have it, set `WowUpExe`
or `CurseForgeExe` in `config.json` to the full path of the executable and run
`Install.cmd` again. The likeliest cause is a CurseForge that runs *inside*
Overwolf rather than as the standalone app: that one has no `CurseForge.exe` of
its own to start, and this tool cannot launch it.

**They start when I don't want them to.** Set `LaunchWowUp` or
`LaunchCurseForge` to `false` in `config.json` and run `Install.cmd` again, or
install with `-NoWowUp` / `-NoCurseForge`. Note that emptying `WowUpExe` does
*not* do this — an empty path means auto-detect.

**`QuitWithWow` didn't close one of them.** The watcher asks politely: it sends
a close request to the app's main window, the same thing clicking the X does. An
app already sitting in the tray with no window open has nothing to send it to,
so it stays. The log says `asked WowUp to close` because that is exactly what
happened — it is a request, not a kill.

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

**The log has no history from previous days.** `Uninstall.cmd` deletes
`%LOCALAPPDATA%\ArchonLauncher`, log included, so an uninstall/reinstall cycle
starts the log fresh. That's expected, not a fault.

## Notes

- Windows 10/11, PowerShell 5.1 (the built-in one). No modules required.
- Polling, not process-creation events. Event-driven detection needs
  administrator rights or an audit-policy change, and the measured cost of
  polling doesn't justify either.
- Nothing here modifies, patches, or injects into Archon, the addon managers or
  WoW. It only calls `Start-Process` on their executables — and, with
  `QuitWithWow`, asks their windows to close.
- Adding the addon managers costs nothing per poll. The extra work happens only
  when the game launches, not once a second, so the figures above still hold.

## License

Public domain / CC0. Do whatever you like with it.
