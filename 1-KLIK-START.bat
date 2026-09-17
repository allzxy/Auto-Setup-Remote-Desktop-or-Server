@echo off
setlocal
cd /d "%~dp0"
title Auto Setup Remote Desktop or Server

:: 1. Cek hak Administrator
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Meminta izin Administrator...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -ArgumentList '-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '\"%~dp0setup-remote.ps1\"' -Verb RunAs"
    exit /b
)

:: 2. Jalankan PowerShell setup
echo ========================================================
echo    MEMULAI INSTALASI & SETUP REMOTE SERVER (ADMIN)      
echo ========================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-remote.ps1"

echo.
echo ========================================================
echo [SELESAI] Tekan tombol apa saja untuk keluar...
echo ========================================================
pause >nul
exit
