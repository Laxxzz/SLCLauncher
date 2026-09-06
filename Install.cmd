@echo off
setlocal
title Archon Launcher - Install

echo.
echo   Archon Launcher
echo   Starts the Archon App - plus WowUp and CurseForge, if you have them -
echo   when World of Warcraft launches.
echo   ---------------------------------------------------------------------
echo.

rem Clear the "downloaded from the internet" mark so the scripts can run.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0.' -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1

rem Arguments passed on the command line win; otherwise ask.
rem
rem Each question is asked whether or not you actually have that app: the
rem installer would have to duplicate the watcher's whole search to know, and
rem answering Y for something you don't have costs nothing. The watcher logs
rem "not installed - skipping" and carries on. Hence "if you use it" rather
rem than a flat "do you want it".
rem
rem choice sets errorlevel 1 for Y and 2 for N, and "if errorlevel 2" is true
rem for anything at or above 2 -- so "if not errorlevel 2" is the Y branch.
set "OPTS=%*"
if not "%OPTS%"=="" goto run

echo.
choice /C YN /N /M "  If you use WowUp, launch it with WoW too?  [Y/N] "
if not errorlevel 2 goto askcurse
set "OPTS=%OPTS% -NoWowUp"

:askcurse
choice /C YN /N /M "  If you use CurseForge, launch it with WoW too?  [Y/N] "
if not errorlevel 2 goto askquit
set "OPTS=%OPTS% -NoCurseForge"

:askquit
choice /C YN /N /M "  Also close them again when you quit WoW?  [Y/N] "
if errorlevel 2 goto run
set "OPTS=%OPTS% -QuitWithWow"

:run
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %OPTS%
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
  echo   All set - launch WoW to test it.
) else (
  echo   Install failed with exit code %RC%.
  echo   Check the messages above, then see README.md.
)
echo.
echo   Press any key to close this window.
pause >nul
endlocal
