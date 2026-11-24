@echo off
rem Starts the app with phone access over the salon Wi-Fi (run on the salon PC)
setlocal
set "DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%DIR%server.ps1" -Lan
