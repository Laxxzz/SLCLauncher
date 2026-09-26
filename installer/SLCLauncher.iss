; SLCLauncher.iss -- builds SLCLauncher-Setup-<version>.exe with Inno Setup 6.
;
; Build it with Build-Installer.ps1 beside this file, which reads the version
; out of SLCWatcher.ps1 and passes it in as AppVersion.
;
; Setup.exe is a wrapper round Install.ps1 and Uninstall.ps1 rather than a
; second copy of what they do. Install.ps1 already knows how to take over
; Archon Launcher, keep settings across updates, build the settings app on this
; machine and register the logon task, and Install.cmd goes on using it, so
; both ways in install exactly the same thing. What Setup.exe adds is the
; wizard, an entry in Settings > Apps, and an uninstaller.

#ifndef AppVersion
  #error Build with Build-Installer.ps1, which supplies AppVersion
#endif

[Setup]
; Never change AppId: it is how an update finds the install it replaces.
AppId={{7E5B9FD3-CF7D-429C-8CBB-FB887EC17E18}
AppName=SLC Launcher
AppVersion={#AppVersion}
AppVerName=SLC Launcher {#AppVersion}
AppPublisher=Laxxzz
AppPublisherURL=https://github.com/Laxxzz/SLCLauncher
AppSupportURL=https://github.com/Laxxzz/SLCLauncher/issues
AppUpdatesURL=https://github.com/Laxxzz/SLCLauncher/releases
VersionInfoVersion={#AppVersion}

; Per user, like the scheduled task: no administrator rights, no UAC prompt.
PrivilegesRequired=lowest

; Fixed, because Install.ps1, Uninstall.ps1, ViewLog.cmd and the watcher all
; expect it there, so there is no folder page to ask.
DefaultDirName={localappdata}\SLCLauncher
DisableDirPage=yes
DisableProgramGroupPage=yes

; Only so that {sys} is the 64-bit System32 on 64-bit Windows, and the install
; runs in the same PowerShell as the watcher later will. Nothing here is
; installed per architecture, and 32-bit Windows is still allowed.
ArchitecturesInstallIn64BitMode=x64compatible

; Install.ps1 closes an open settings window itself, and knows which one is
; ours; Restart Manager would only ask the user about it first.
CloseApplications=no

LicenseFile=..\LICENSE
SetupIconFile=..\SLCLauncher.ico
UninstallDisplayIcon={app}\SLCLauncher.exe
UninstallDisplayName=SLC Launcher
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
OutputDir=..\dist
OutputBaseFilename=SLCLauncher-Setup-{#AppVersion}

[Messages]
FinishedLabel=SLC Launcher is installed and watching for World of Warcraft.%n%nChoose which apps start with the game in SLC Launcher, which is in the Start menu.

[Files]
; Kept in the install folder: the uninstaller runs Uninstall.ps1 from there,
; and ViewLog.cmd is the troubleshooting check the README points to.
Source: "..\Uninstall.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\ViewLog.cmd";   DestDir: "{app}"; Flags: ignoreversion

; Everything Install.ps1 needs beside it. It copies what it keeps into {app}
; and builds SLCLauncher.exe from the .cs files; Setup deletes {tmp} when done.
Source: "..\SLCWatcher.ps1";          DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\RunHidden.vbs";           DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\SLCLauncherSettings.ps1"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\SLCLauncher.ico";         DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\SLCLauncher.cs";          DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\SLCTheme.cs";             DestDir: "{tmp}"; Flags: ignoreversion
; Last, so every file above is in place when it runs.
Source: "..\Install.ps1";             DestDir: "{tmp}"; Flags: ignoreversion; AfterInstall: RunInstallScript

[Run]
Filename: "{app}\SLCLauncher.exe"; Description: "Open SLC Launcher to choose your apps"; Flags: postinstall nowait skipifsilent

[UninstallRun]
; -KeepFiles because the folder is removed below, after this has stopped the
; watcher and closed the settings window that would otherwise hold files open.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\Uninstall.ps1"" -KeepFiles"; \
  Flags: runhidden waituntilterminated; RunOnceId: "RemoveTaskAndWatcher"

[UninstallDelete]
; Most of the folder was written by Install.ps1 and the settings app rather than
; by Setup, so Setup has no record of it. Settings and log go too, the same as
; Uninstall.cmd.
Type: filesandordirs; Name: "{app}"

[Code]
procedure RunInstallScript;
var
  PowerShell, LogPath: String;
  ResultCode: Integer;
begin
  PowerShell := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  LogPath := ExpandConstant('{app}\install.log');

  WizardForm.StatusLabel.Caption := 'Setting up the watcher and building the settings app...';

  if not Exec(PowerShell,
              '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
                ExpandConstant('{tmp}\Install.ps1') + '" -LogPath "' + LogPath + '"',
              ExpandConstant('{tmp}'), SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    RaiseException('Could not start Windows PowerShell: ' + SysErrorMessage(ResultCode));

  // Raising here makes Setup report the failure and roll back, rather than
  // claim success for an install that has no watcher.
  if ResultCode <> 0 then
    RaiseException('SLC Launcher could not finish installing (exit code ' +
                   IntToStr(ResultCode) + ').' + #13#10#13#10 +
                   'What went wrong is in ' + LogPath);
end;
