@echo off
setlocal
cd /d "%~dp0"
title Fix & Start OpenSSH Service

:: 1. Cek hak Administrator
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

echo ========================================================
echo        MEMPERBAIKI PERMISSION & MENYALAKAN OPENSSH      
echo ========================================================

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$sshData = '$env:ProgramData\ssh';" ^
  "if (Test-Path $sshData) {" ^
  "  icacls.exe $sshData /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'BUILTIN\Administrators:(OI)(CI)F' /c /q | Out-Null;" ^
  "  Get-ChildItem -Path $sshData -Filter 'ssh_host_*_key' | ForEach-Object {" ^
  "    icacls.exe $_.FullName /inheritance:r /grant:r 'SYSTEM:F' 'BUILTIN\Administrators:F' /c /q | Out-Null;" ^
  "  };" ^
  "  $cfg = \"$sshData\sshd_config\";" ^
  "  if (Test-Path $cfg) {" ^
  "    $c = Get-Content $cfg -Raw;" ^
  "    if ($c -notmatch 'UseDNS') { Add-Content $cfg \"`nUseDNS no`n\" };" ^
  "  };" ^
  "};" ^
  "Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Profile Any -ErrorAction SilentlyContinue | Out-Null;" ^
  "Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue;" ^
  "Restart-Service -Name sshd -Force -ErrorAction SilentlyContinue;" ^
  "Start-Service -Name sshd -ErrorAction SilentlyContinue;" ^
  "Start-Sleep -Seconds 2;" ^
  "if (Test-Path '%~dp0Status\status.ps1') { & '%~dp0Status\status.ps1' -NoWait }"

echo.
pause
exit
