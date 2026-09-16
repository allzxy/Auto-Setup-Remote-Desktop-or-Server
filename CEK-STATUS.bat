@echo off
setlocal
title Audit Status Remote Server
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0cek-status.ps1"
echo.
pause
exit
