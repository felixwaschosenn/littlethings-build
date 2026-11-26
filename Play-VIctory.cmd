@echo off
setlocal EnableExtensions DisableDelayedExpansion
if not "%~1"=="" set "VICTORY_GAME_DIR=%~1"
if not defined VICTORY_GAME_DIR (
  echo Usage: Play-VIctory.cmd "C:\path\to\your\dump" 1>&2
  exit /b 2
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run-rx6600.ps1" -GameDir "%VICTORY_GAME_DIR%" -TimeoutSeconds 300
exit /b %errorlevel%
