; SLCLauncher.iss -- builds SLCLauncher-Setup-<version>.exe with Inno Setup 6.
;
; Build it with Build-Installer.ps1 beside this file, which reads the version
; out of SLCWatcher.ps1 and passes it in as AppVersion.
;
; Setup.exe is a wrapper round Install.ps1 and Uninstall.ps1 rather than a
; second copy of what they do. Install.ps1 already knows how to keep settings
; across updates, build the settings app on this machine and register the
; logon task, and Install.cmd goes on using it, so
; both ways in install exactly the same thing. What Setup.exe adds is the
; wizard, an entry in Settings > Apps, and an uninstaller.
;
; An update removes the version already installed before installing this one,
; keeping only your settings. The uninstallers before 2.2.0 delete config.json
; with everything else, so it is copied aside first and put back after; see
; PrepareToInstall below. From 2.2.0 the uninstaller also takes /KEEPSETTINGS.
;
; Command line, besides Inno Setup's own (/SILENT, /VERYSILENT, ...):
;   /RELAUNCH      open SLCLauncher once installed, even when silent. The
;                  settings window's own update passes this.
;   unins000.exe /KEEPSETTINGS   uninstall, but leave config.json behind.

#ifndef AppVersion
  #error Build with Build-Installer.ps1, which supplies AppVersion
#endif

[Setup]
; Never change AppId: it is how an update finds the install it replaces.
AppId={{7E5B9FD3-CF7D-429C-8CBB-FB887EC17E18}
AppName=SLCLauncher
AppVersion={#AppVersion}
AppVerName=SLCLauncher {#AppVersion}
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
UninstallDisplayName=SLCLauncher
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
OutputDir=..\dist
OutputBaseFilename=SLCLauncher-Setup-{#AppVersion}

[Messages]
FinishedLabel=SLCLauncher is installed and watching for World of Warcraft.%n%nChoose which apps start with the game in SLCLauncher, which is in the Start menu.

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
Filename: "{app}\SLCLauncher.exe"; Description: "Open SLCLauncher to choose your apps"; Flags: postinstall nowait skipifsilent
Filename: "{app}\SLCLauncher.exe"; Flags: nowait; Check: HasSwitch('/RELAUNCH')

; No [UninstallRun] or [UninstallDelete]: both happen in CurUninstallStepChanged
; below, because whether config.json goes too is only known once the uninstaller
; is running, and those sections are fixed when Setup runs.

[Code]
const
  UninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{7E5B9FD3-CF7D-429C-8CBB-FB887EC17E18}_is1';

function HasSwitch(Name: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), Name) = 0 then
      Result := True;
end;

function SettingsBackupDir: String;
begin
  // Beside the install folder, not in it or in {tmp}: the old uninstaller
  // deletes the one, Setup the other, and this must outlast both should the
  // update stop halfway.
  Result := ExpandConstant('{localappdata}\SLCLauncher-update-backup');
end;

// ------------------------------------------------------------------ update --
// Runs before any file is installed. If a version is installed already, its
// settings are copied aside, it is uninstalled -- which stops its watcher,
// removes its task and shortcut, and with the uninstallers before 2.2.0 deletes
// the whole folder -- and the settings are put back where Install.ps1 will
// find and keep them.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Uninstaller, AppDir, Config, Backup: String;
  ResultCode, Waited: Integer;
begin
  Result := '';
  AppDir := ExpandConstant('{app}');
  Config := AppDir + '\config.json';
  Backup := SettingsBackupDir + '\config.json';

  if not RegQueryStringValue(HKCU, UninstallKey, 'UninstallString', Uninstaller) then
    RegQueryStringValue(HKLM, UninstallKey, 'UninstallString', Uninstaller);
  Uninstaller := RemoveQuotes(Uninstaller);

  if (Uninstaller <> '') and FileExists(Uninstaller) then
  begin
    // A copy left by an update that stopped halfway is older than this one,
    // which is why the folder's own file wins whenever there is one.
    if FileExists(Config) then
    begin
      ForceDirectories(SettingsBackupDir);
      if not FileCopy(Config, Backup, False) then
      begin
        Result := 'Your SLCLauncher settings could not be backed up, so nothing has been changed.' + #13#10#13#10 +
                  'Could not copy ' + Config + ' to ' + Backup + '.';
        exit;
      end;
    end;

    if Exec(Uninstaller, '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /KEEPSETTINGS', '',
            SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    begin
      // The uninstaller hands over to a copy of itself in the temp folder and
      // returns at once, so the wait above is no wait at all. It deletes
      // itself as its last act: wait for that, for up to a minute.
      Waited := 0;
      while FileExists(Uninstaller) and (Waited < 60000) do
      begin
        Sleep(250);
        Waited := Waited + 250;
      end;
    end;
    // If it failed or is still going, install over it as earlier versions
    // always did: Install.ps1 stops the old watcher and clears out its files.
  end;

  // Back where Install.ps1 looks for it, whether it was copied aside just now
  // or by an earlier update that never finished.
  if FileExists(Backup) and not FileExists(Config) then
  begin
    ForceDirectories(AppDir);
    if not FileCopy(Backup, Config, False) then
      Result := 'Your SLCLauncher settings could not be put back from ' + Backup + '.' + #13#10#13#10 +
                'They are still there. Run Setup again to retry.';
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  // Installed and running: the copy has done its job. A failed install never
  // gets here -- RunInstallScript rolls it back -- so the copy stays for the
  // next attempt.
  if CurStep = ssPostInstall then
    DelTree(SettingsBackupDir, True, True, True);
end;

// --------------------------------------------------------------- uninstall --
procedure RemoveInstalledFiles(KeepSettings: Boolean);
var
  Dir: String;
  Found: TFindRec;
begin
  // Most of the folder was written by Install.ps1 and the settings app rather
  // than by Setup, so Setup has no record of it. Settings and log go too, the
  // same as Uninstall.cmd -- except with /KEEPSETTINGS, which keeps config.json
  // and update.json. The uninstaller's own files are left to it: it removes
  // them, and the folder if that leaves it empty, last of all.
  Dir := ExpandConstant('{app}');
  if FindFirst(Dir + '\*', Found) then
  try
    repeat
      if (Found.Name = '.') or (Found.Name = '..') then continue;
      if CompareText(Copy(Found.Name, 1, 5), 'unins') = 0 then continue;
      if KeepSettings and ((CompareText(Found.Name, 'config.json') = 0) or
                           (CompareText(Found.Name, 'update.json') = 0)) then continue;
      if Found.Attributes and FILE_ATTRIBUTE_DIRECTORY <> 0 then
        DelTree(Dir + '\' + Found.Name, True, True, True)
      else
        DeleteFile(Dir + '\' + Found.Name);
    until not FindNext(Found);
  finally
    FindClose(Found);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    // Stops the watcher, removes the task and the Start menu entry, and closes
    // a settings window that would otherwise hold files open. -KeepFiles,
    // because the files are removed just below.
    Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
         '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
           ExpandConstant('{app}\Uninstall.ps1') + '" -KeepFiles',
         ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ResultCode);
    RemoveInstalledFiles(HasSwitch('/KEEPSETTINGS'));
  end;
end;

// ------------------------------------------------------------------ install --
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
    RaiseException('SLCLauncher could not finish installing (exit code ' +
                   IntToStr(ResultCode) + ').' + #13#10#13#10 +
                   'What went wrong is in ' + LogPath);
end;
