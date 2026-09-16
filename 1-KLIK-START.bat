@echo off
setlocal
cd /d "%~dp0"
title Auto Setup Remote Desktop or Server

:: 1. Cek hak Administrator
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Meminta izin Administrator...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

:: 2. Jalankan PowerShell setup dengan path aman dari spasi
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
