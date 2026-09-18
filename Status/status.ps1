# ==============================================================================
# Auto Setup Remote Desktop or Server - Health & Status Audit (Windows)
# Run via terminal:
# irm https://raw.githubusercontent.com/allzxy/Auto-Setup-Remote-Desktop-or-Server/main/Status/status.ps1 | iex
# ==============================================================================

$NoWait = ($args -contains "-NoWait") -or ($args -contains "--no-wait") -or ($env:STATUS_NO_WAIT -eq "1")

# Paksa TLS 1.2 & TLS 1.3
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

if (-not $NoWait) {
    Clear-Host
}
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "        AUDIT STATUS REMOTE SERVER & REQUIREMENT (WINDOWS)      " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$allPassed = $true

function Print-Status ($name, $isOk, $detail) {
    if ($isOk) {
        Write-Host "  [ OK ] " -NoNewline -ForegroundColor Green
        Write-Host "$name " -NoNewline -ForegroundColor White
        Write-Host "($detail)" -ForegroundColor Gray
    } else {
        Write-Host "  [FAIL] " -NoNewline -ForegroundColor Red
        Write-Host "$name " -NoNewline -ForegroundColor Yellow
        Write-Host "($detail)" -ForegroundColor Red
        $script:allPassed = $false
    }
}

# 1. Cek Hak Akses Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Print-Status "Hak Akses Administrator" $isAdmin $(if ($isAdmin) { "Elevated (Administrator)" } else { "Non-Admin (Jalankan sebagai Admin untuk audit penuh)" })

# 2. Cek Koneksi Internet
$internetOk = $false
try {
    $t1 = Test-NetConnection -ComputerName "1.1.1.1" -Port 53 -InformationLevel Quiet -WarningAction SilentlyContinue
    $t2 = Test-NetConnection -ComputerName "8.8.8.8" -Port 53 -InformationLevel Quiet -WarningAction SilentlyContinue
    $internetOk = $t1 -or $t2
} catch {}
Print-Status "Koneksi Internet" $internetOk $(if ($internetOk) { "Online" } else { "Offline / Gangguan" })

# 3. Cek Tailscale App & Service
$tsCli = "C:\Program Files\Tailscale\tailscale.exe"
$tsAppInstalled = Test-Path $tsCli
$tsService = Get-Service -Name "Tailscale" -ErrorAction SilentlyContinue
$tsServiceRunning = ($tsService -and $tsService.Status -eq "Running")

Print-Status "Tailscale App" $tsAppInstalled $(if ($tsAppInstalled) { "Terinstall di $tsCli" } else { "Belum Terinstall" })
Print-Status "Tailscale Service" $tsServiceRunning $(if ($tsServiceRunning) { "Service Berjalan di Background" } else { "Service Berhenti" })

# 4. Cek Koneksi Tailscale Network (IP Machine & Hostname)
$tsIp = ""
$tsConnected = $false
$tsHostname = $env:COMPUTERNAME.ToLower()

if ($tsAppInstalled) {
    $tsIp = (& $tsCli ip -4 2>$null)
    if ($tsIp -and $tsIp -match "^\d+\.\d+\.\d+\.\d+$") {
        $tsConnected = $true
        $statusJson = (& $tsCli status --json 2>$null | ConvertFrom-Json 2>$null)
        if ($statusJson -and $statusJson.Self -and $statusJson.Self.HostName) {
            $tsHostname = $statusJson.Self.HostName
        }
    }
}
Print-Status "Tailscale Mesh Network" $tsConnected $(if ($tsConnected) { "Terhubung! IP Mesin: $tsIp" } else { "Belum Login / Belum Konek" })

# 5. Cek OpenSSH Server & Service
$sshInstalled = (Get-Service -Name "sshd" -ErrorAction SilentlyContinue) -or (Test-Path "C:\Windows\System32\OpenSSH\sshd.exe") -or (Test-Path "C:\Program Files\OpenSSH\sshd.exe")
$sshService = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
$sshRunning = ($sshService -and $sshService.Status -eq "Running")

Print-Status "OpenSSH Server" $sshInstalled $(if ($sshInstalled) { "Terpasang di System" } else { "Belum Terpasang" })
Print-Status "OpenSSH Service" $sshRunning $(if ($sshRunning) { "Running (Port 22)" } else { "Belum Aktif" })

# 6. Cek Firewall Port 22
$fwSsh = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq "True" }
$fwSshOk = [bool]$fwSsh
Print-Status "Firewall Port 22 (SSH)" $fwSshOk $(if ($fwSshOk) { "Allowed" } else { "Port Belum Terbuka" })

# 7. Cek Remote Desktop (RDP)
$rdpReg = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -ErrorAction SilentlyContinue).fDenyTSConnections
$rdpEnabled = ($rdpReg -eq 0)
$fwRdp = Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq "True" }
$fwRdpOk = [bool]$fwRdp

Print-Status "Remote Desktop (RDP)" ($rdpEnabled -and $fwRdpOk) $(if ($rdpEnabled -and $fwRdpOk) { "Aktif & Port 3389 Terbuka" } else { "Non-aktif" })

# 8. Cek Power Management (Kebal Sleep, Lock & Tutup Layar)
$powerAc = powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 2>$null | Select-String "Current AC Power Setting Index:" | ForEach-Object { $_.ToString().Split(":")[-1].Trim() }
$antiSleepOk = ($powerAc -eq "0x00000000" -or $powerAc -eq "0")
Print-Status "Anti-Sleep Mode" $antiSleepOk $(if ($antiSleepOk) { "Aktif (Server Tidak Akan Sleep)" } else { "Masih Bisa Sleep" })

$activeScheme = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes" -Name "ActivePowerScheme" -ErrorAction SilentlyContinue).ActivePowerScheme
$lidReg = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$activeScheme\4f971e89-eebd-4455-a8de-9e59040e7347\5ca83367-6e45-459f-a27b-476b1d01c936" -ErrorAction SilentlyContinue
$lidOk = ($lidReg -and $lidReg.ACSettingIndex -eq 0)
Print-Status "Kebal Tutup Layar Laptop" $lidOk $(if ($lidOk) { "Aktif (Tutup Laptop Tetap Jalan)" } else { "Akan Sleep Saat Ditutup" })

$lockReg = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$activeScheme\238c9fa8-0aad-41ed-83f4-97be242c8f20\7bc4a2f9-d8fc-4469-b07b-33eb785aaca0" -ErrorAction SilentlyContinue
$lockOk = ($lockReg -and $lockReg.ACSettingIndex -eq 0)
Print-Status "Kebal Lock Screen (Win+L)" $lockOk $(if ($lockOk) { "Aktif (Tetap Jalan Saat Layar Dikunci/Mati)" } else { "Akan Sleep Setelah Di-lock" })

# 9. Cek Dukungan Login Tanpa Password (LSA Blank Password)
$blankPw = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Lsa' -Name 'LimitBlankPasswordUse' -ErrorAction SilentlyContinue).LimitBlankPasswordUse
$blankPwOk = ($blankPw -eq 0)
Print-Status "Login Tanpa Password (LSA)" $blankPwOk $(if ($blankPwOk) { "Diizinkan (LimitBlankPasswordUse = 0)" } else { "Terkunci (Perlu Password Windows)" })

# 10. Cek Resiliensi Watchdog Task Scheduler
$watchdogTask = (Get-ScheduledTask -TaskName "RemoteServerKeepAlive" -ErrorAction SilentlyContinue) -or (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\RemoteServerKeepAlive")
$watchdogOk = [bool]$watchdogTask
Print-Status "Resiliensi Watchdog" $watchdogOk $(if ($watchdogOk) { "Aktif (Task 'RemoteServerKeepAlive' Auto-Heal 15 mnt)" } else { "Belum Terpasang" })

# 11. Cek Resiliensi Auto-Restart Service (Recovery Actions)
$tsFail = ((sc.exe qfailure Tailscale 2>$null) -join "") -match "RESTART"
$sshFail = ((sc.exe qfailure sshd 2>$null) -join "") -match "RESTART"
$autoRestartOk = $tsFail -and $sshFail
Print-Status "Auto-Restart Service" $autoRestartOk $(if ($autoRestartOk) { "Aktif (Restart otomatis jika service mati/crash)" } else { "Belum Diatur Lengkap" })

# 12. Cek Hardening Service SDDL (Anti-End-Service Non-Admin)
$sddlTs = ((sc.exe sdshow Tailscale 2>$null) -join "")
$sddlSsh = ((sc.exe sdshow sshd 2>$null) -join "")
$sddlHardened = ($sddlTs -match "WPDTSD;;;BU" -or $sddlTs -match "CCLCSWLOCRRC;;;AU") -and ($sddlSsh -match "WPDTSD;;;BU" -or $sddlSsh -match "CCLCSWLOCRRC;;;AU")
Print-Status "Hardening Service SDDL" $sddlHardened $(if ($sddlHardened) { "Terkunci (Non-Admin dilarang Stop/Delete)" } else { "Standar (Belum Dikunci SDDL)" })

# 13. Cek Hardening File ACL (Anti-Uninstall / Anti-Hapus File)
$tsAcl = (Get-Acl "C:\Program Files\Tailscale" -ErrorAction SilentlyContinue).Access | Where-Object { $_.AccessControlType -eq "Deny" -and $_.IdentityReference -match "Users" }
$fileAclOk = [bool]$tsAcl
Print-Status "Hardening File ACL" $fileAclOk $(if ($fileAclOk) { "Folder Tailscale & OpenSSH Terproteksi" } else { "Belum Terproteksi" })

# 14. Cek Auto-Logon Windows (Auto masuk ke User Biasa pas reboot)
$autoLogon = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name "AutoAdminLogon" -ErrorAction SilentlyContinue).AutoAdminLogon
$autoLogonUser = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name "DefaultUserName" -ErrorAction SilentlyContinue).DefaultUserName
$autoLogonOk = ($autoLogon -eq "1" -or $autoLogon -eq 1)
Print-Status "Auto-Logon User Biasa" $autoLogonOk $(if ($autoLogonOk) { "Aktif (Otomatis masuk desktop sebagai '$autoLogonUser')" } else { "Non-aktif (Berhenti di Lock Screen)" })

Write-Host "`n----------------------------------------------------------------" -ForegroundColor Gray

if ($allPassed) {
    Write-Host "STATUS KESELURUHAN: SEMPURNA (SIAP DI-REMOTE 24/7 & TERLINDUNGI)" -ForegroundColor Green
    
    if ($tsIp) {
        Write-Host ""
        Write-Host "================================================================" -ForegroundColor Cyan
        Write-Host "               DATA KONEKSI UNTUK APLIKASI TERMIUS              " -ForegroundColor Cyan
        Write-Host "================================================================" -ForegroundColor Cyan
        Write-Host "  Buka Termius -> Klik '+ New Host' -> Masukkan data ini:" -ForegroundColor White
        Write-Host "  Label / Alias : $tsHostname (Admin)" -ForegroundColor Yellow
        Write-Host "  Hostname / IP : $tsIp" -ForegroundColor Yellow
        Write-Host "  Port          : 22" -ForegroundColor Yellow
        Write-Host "  Username      : Administrator" -ForegroundColor Yellow
        Write-Host "  Password      : (KOSONGKAN / Biarkan Blank di Termius)" -ForegroundColor Yellow
        $physicalUser = if ($autoLogonUser) { $autoLogonUser } else { $env:USERNAME }
        Write-Host "  User Fisik    : $physicalUser (Otomatis login sebagai User Biasa di layar fisik)" -ForegroundColor Gray
        Write-Host "----------------------------------------------------------------" -ForegroundColor Gray
        Write-Host "  Quick SSH CLI : ssh Administrator@$tsIp" -ForegroundColor Cyan
        Write-Host "  Remote Desktop: RDP ke $tsIp (User: Administrator, tanpa password)" -ForegroundColor Cyan
        Write-Host "================================================================" -ForegroundColor Cyan
    }
} else {
    Write-Host "STATUS KESELURUHAN: MASIH ADA YANG PERLU DIKONFIGURASI" -ForegroundColor Yellow
    Write-Host "Jalankan 1-KLIK-START.bat (Run as Administrator) untuk mengaktifkan Watchdog & Hardening." -ForegroundColor Yellow
}

Write-Host "================================================================`n" -ForegroundColor Cyan
if (-not $NoWait) {
    try {
        if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
            Write-Host "Jendela ini tidak akan ditutup otomatis agar Anda bisa melihat log di atas." -ForegroundColor Gray
            Read-Host "Tekan tombol ENTER untuk keluar..."
        }
    } catch {}
}
