@echo off
pushd "%~dp0"
if not exist "rescale.ps1" (
  echo Downloading rescale.ps1...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/akahobby/rescale/main/rescale.ps1' -OutFile '.\rescale.ps1' -UseBasicParsing"
  if errorlevel 1 (
    echo Download failed.
    popd
    pause
    exit /b 1
  )
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0rescale.ps1" %*
popd
