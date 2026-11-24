@echo off
rem Starts the offline app: local server + browser window (no internet needed)
setlocal
set "DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%DIR%server.ps1"
