@echo off
setlocal
cd /d "%~dp0"
title Status Remote Server
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0status.ps1"
exit
