@echo off
setlocal
cd /d "%~dp0"
title Fix & Start OpenSSH Service

:: 1. Cek hak Administrator
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Meminta izin Administrator...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo ========================================================
echo        MEMPERBAIKI & MENYALAKAN OPENSSH SERVER          
echo ========================================================

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "Write-Host '[1/4] Memeriksa instalasi OpenSSH Server...' -ForegroundColor Cyan;" ^
  "if (!(Get-Service -Name 'sshd' -ErrorAction SilentlyContinue)) {" ^
  "  Write-Host '  Service sshd belum ada. Memasang via Windows Capability...' -ForegroundColor Yellow;" ^
  "  Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' -ErrorAction SilentlyContinue | Out-Null;" ^
  "  if (!(Get-Service -Name 'sshd' -ErrorAction SilentlyContinue)) {" ^
  "    dism.exe /Online /NoRestart /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0 | Out-Null;" ^
  "  };" ^
  "  if (!(Get-Service -Name 'sshd' -ErrorAction SilentlyContinue)) {" ^
  "    $b = if (Test-Path 'C:\Windows\System32\OpenSSH\sshd.exe') { 'C:\Windows\System32\OpenSSH\sshd.exe' } elseif (Test-Path 'C:\Program Files\OpenSSH\sshd.exe') { 'C:\Program Files\OpenSSH\sshd.exe' } else { $null };" ^
  "    if ($b) { New-Service -Name 'sshd' -BinaryPathName \"`\"$b`\"\" -DisplayName 'OpenSSH SSH Server' -StartupType Automatic | Out-Null };" ^
  "  };" ^
  "};" ^
  "Write-Host '[2/4] Menyiapkan Host Keys & Permission...' -ForegroundColor Cyan;" ^
  "$sshDir = if (Test-Path 'C:\Windows\System32\OpenSSH\sshd.exe') { 'C:\Windows\System32\OpenSSH' } elseif (Test-Path 'C:\Program Files\OpenSSH\sshd.exe') { 'C:\Program Files\OpenSSH' } else { $null };" ^
  "if ($sshDir -and (Test-Path \"$sshDir\ssh-keygen.exe\")) { & \"$sshDir\ssh-keygen.exe\" -A 2>$null | Out-Null };" ^
  "$sshData = '$env:ProgramData\ssh';" ^
  "if (Test-Path $sshData) {" ^
  "  icacls.exe $sshData /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'BUILTIN\Administrators:(OI)(CI)F' /c /q | Out-Null;" ^
  "  Get-ChildItem -Path $sshData -Filter 'ssh_host_*_key' -ErrorAction SilentlyContinue | ForEach-Object {" ^
  "    icacls.exe $_.FullName /inheritance:r /grant:r 'SYSTEM:F' 'BUILTIN\Administrators:F' /c /q | Out-Null;" ^
  "  };" ^
  "  $cfg = \"$sshData\sshd_config\";" ^
  "  if (Test-Path $cfg) {" ^
  "    $c = Get-Content $cfg -Raw;" ^
  "    $c = $c -replace '(?m)^\s*#?\s*PermitEmptyPasswords\s+.*$', 'PermitEmptyPasswords yes';" ^
  "    $c = $c -replace '(?m)^\s*#?\s*PasswordAuthentication\s+.*$', 'PasswordAuthentication yes';" ^
  "    $c = $c -replace '(?m)^\s*#?\s*KbdInteractiveAuthentication\s+.*$', 'KbdInteractiveAuthentication yes';" ^
  "    if ($c -notmatch 'PermitEmptyPasswords') { $c += \"`nPermitEmptyPasswords yes\" };" ^
  "    if ($c -notmatch 'PasswordAuthentication') { $c += \"`nPasswordAuthentication yes\" };" ^
  "    if ($c -notmatch 'KbdInteractiveAuthentication') { $c += \"`nKbdInteractiveAuthentication yes\" };" ^
  "    if ($c -notmatch 'PubkeyAuthentication') { $c += \"`nPubkeyAuthentication yes\" };" ^
  "    if ($c -notmatch 'UseDNS') { $c += \"`nUseDNS no`n\" };" ^
  "    Set-Content -Path $cfg -Value $c -Force;" ^
  "    icacls.exe $cfg /inheritance:r /grant:r 'SYSTEM:F' 'BUILTIN\Administrators:F' /c /q | Out-Null;" ^
  "  };" ^
  "};" ^
  "Write-Host '[3/4] Mengaktifkan LSA Blank Password & Firewall...' -ForegroundColor Cyan;" ^
  "Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Lsa' -Name 'LimitBlankPasswordUse' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null;" ^
  "if (!(Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {" ^
  "  New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH SSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any -EdgeTraversalPolicy Allow | Out-Null;" ^
  "} else {" ^
  "  Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Profile Any -Action Allow -Enabled True -EdgeTraversalPolicy Allow -ErrorAction SilentlyContinue | Out-Null;" ^
  "};" ^
  "Write-Host '[4/4] Memulai Service OpenSSH...' -ForegroundColor Cyan;" ^
  "Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue;" ^
  "sc.exe config sshd start= auto | Out-Null;" ^
  "Restart-Service -Name sshd -Force -ErrorAction SilentlyContinue;" ^
  "Start-Service -Name sshd -ErrorAction SilentlyContinue;" ^
  "sc.exe start sshd | Out-Null;" ^
  "Start-Sleep -Seconds 2;" ^
  "$s = Get-Service -Name sshd -ErrorAction SilentlyContinue;" ^
  "if ($s.Status -ne 'Running') { net start sshd 2>&1 | Out-Null; Start-Sleep -Seconds 1 };" ^
  "if (Test-Path '%~dp0Status\status.ps1') { & '%~dp0Status\status.ps1' -NoWait }"

echo.
pause
exit
