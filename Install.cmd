@echo off
setlocal
title Archon Launcher - Install

echo.
echo   Archon Launcher
echo   Starts the Archon App - plus WowUp and CurseForge, if you have them -
echo   when World of Warcraft launches.
echo   ---------------------------------------------------------------------
echo.

rem Arguments passed on the command line win; otherwise ask.
rem
rem Both managers are asked about regardless of what is installed. Saying yes
rem to one you don't have costs nothing -- the watcher logs "not installed -
rem skipping" and carries on -- and detecting it here would mean a second copy
rem of the watcher's whole search, free to drift out of step with it.
rem
rem choice sets errorlevel 1 for Y and 2 for N, and "if errorlevel 2" is true
rem for anything at or above 2 -- so "if not errorlevel 2" is the Y branch.
set "OPTS=%*"
if not "%OPTS%"=="" goto run

choice /C YN /N /M "  Install Archon Launcher?  [Y/N] "
if errorlevel 2 goto cancelled

echo.
choice /C YN /N /M "  Launch WowUp with WoW too?  [Y/N] "
if not errorlevel 2 goto askcurse
set "OPTS=%OPTS% -NoWowUp"

:askcurse
choice /C YN /N /M "  Launch CurseForge with WoW too?  [Y/N] "
if not errorlevel 2 goto askquit
set "OPTS=%OPTS% -NoCurseForge"

:askquit
choice /C YN /N /M "  Do you want to close all of them when you close WoW?  [Y/N] "
if errorlevel 2 goto run
set "OPTS=%OPTS% -QuitWithWow"

:run
rem Clear the "downloaded from the internet" mark so the scripts can run. This
rem sits after the questions so that cancelling really does leave every file
rem exactly as it was, and on this side of :run so a scripted install with
rem arguments still gets it.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0.' -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1

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
goto done

:cancelled
echo.
echo   Cancelled - nothing was installed.

:done
echo.
echo   Press any key to close this window.
pause >nul
endlocal
