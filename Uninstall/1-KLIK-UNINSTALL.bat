@echo off
setlocal
cd /d "%~dp0"
title Uninstaller Remote Server

:: 1. Cek hak Administrator
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Meminta izin Administrator...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

:: 2. Jalankan PowerShell uninstaller
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
exit
