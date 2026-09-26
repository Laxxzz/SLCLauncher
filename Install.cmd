@echo off
setlocal
title SLC Launcher - Install

echo.
echo   SLC Launcher
echo   A launcher toolkit for your World of Warcraft tools: starts Archon,
echo   your addon manager, Raider.IO and anything else you choose with the game.
echo   ---------------------------------------------------------------------
echo.

rem Arguments passed on the command line win, and mean a scripted install:
rem they go straight to Install.ps1 and no window is opened.
rem
rem Otherwise there is one question here, and every other choice is made in
rem SLC Launcher, the settings app the installer opens at the end -- the
rem same one the Start menu opens later. Asking here as well would mean two
rem places that set the same things and could disagree about them.
rem
rem choice sets errorlevel 1 for Y and 2 for N, and "if errorlevel 2" is true
rem for anything at or above 2.
set "OPTS=%*"
set "OPENED="
if not "%OPTS%"=="" goto run

choice /C YN /N /M "  Install SLC Launcher?  [Y/N] "
if errorlevel 2 goto cancelled
set "OPTS=-OpenSettings"
set "OPENED=1"

:run
rem Clear the "downloaded from the internet" mark so the scripts can run. This
rem sits after the question so that cancelling really does leave every file
rem exactly as it was, and on this side of :run so a scripted install with
rem arguments still gets it.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0.' -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1

echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %OPTS%
set "RC=%ERRORLEVEL%"

echo.
if not "%RC%"=="0" goto failed
if defined OPENED (
  echo   All set - pick your apps in the SLC Launcher window, then launch WoW.
) else (
  echo   All set - launch WoW to test it.
)
goto done

:failed
echo   Install failed with exit code %RC%.
echo   Check the messages above, then see README.md.
goto done

:cancelled
echo.
echo   Cancelled - nothing was installed.

:done
echo.
echo   Press any key to close this window.
pause >nul
endlocal
