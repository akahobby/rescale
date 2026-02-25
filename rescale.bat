@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\scripts\rescale.ps1" config
if errorlevel 1 (
  echo.
  echo Command failed. Press any key to close this window.
  pause >nul
)
