@echo off
setlocal
cd /d "%~dp0"
title Status & Audit Remote Server

:: 1. Cek hak Administrator (Auto-elevate agar audit lengkap 100%)
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Meminta izin Administrator untuk audit lengkap...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -ArgumentList '-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '\"%~dp0status.ps1\"' -Verb RunAs"
    exit /b
)

:: 2. Jalankan audit status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0status.ps1"
echo.
pause
exit
