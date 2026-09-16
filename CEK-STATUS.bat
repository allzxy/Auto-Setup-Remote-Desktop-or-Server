@echo off
setlocal
title Audit Status Remote Server
if exist "%~dp0Status\status.ps1" (
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0Status\status.ps1"
) else (
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0cek-status.ps1"
    echo.
    pause
)
exit
