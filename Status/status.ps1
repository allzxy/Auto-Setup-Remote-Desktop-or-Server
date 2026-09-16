# ==============================================================================
# Auto Setup Remote Desktop or Server - Health & Status Audit (Windows)
# Run via terminal:
# irm https://raw.githubusercontent.com/allzxy/Auto-Setup-Remote-Desktop-or-Server/main/Status/status.ps1 | iex
# ==============================================================================

param(
    [switch]$NoWait
)

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

# 1. Cek Koneksi Internet
$internetOk = $false
try {
    $t1 = Test-NetConnection -ComputerName "1.1.1.1" -Port 53 -InformationLevel Quiet -WarningAction SilentlyContinue
    $t2 = Test-NetConnection -ComputerName "8.8.8.8" -Port 53 -InformationLevel Quiet -WarningAction SilentlyContinue
    $internetOk = $t1 -or $t2
} catch {}
Print-Status "Koneksi Internet" $internetOk $(if ($internetOk) { "Online" } else { "Offline / Gangguan" })

# 2. Cek Tailscale App & Service
$tsCli = "C:\Program Files\Tailscale\tailscale.exe"
$tsAppInstalled = Test-Path $tsCli
$tsService = Get-Service -Name "Tailscale" -ErrorAction SilentlyContinue
$tsServiceRunning = ($tsService -and $tsService.Status -eq "Running")

Print-Status "Tailscale App" $tsAppInstalled $(if ($tsAppInstalled) { "Terinstall di $tsCli" } else { "Belum Terinstall" })
Print-Status "Tailscale Service" $tsServiceRunning $(if ($tsServiceRunning) { "Service Berjalan di Background" } else { "Service Berhenti" })

# 3. Cek Koneksi Tailscale Network (IP Machine & Hostname)
$tsIp = ""
$tsConnected = $false
$tsHostname = $env:COMPUTERNAME.ToLower()

if ($tsAppInstalled) {
    $tsIp = (& $tsCli ip -4 2>$null)
    if ($tsIp -and $tsIp -match "^\d+\.\d+\.\d+\.\d+$") {
        $tsConnected = $true
        # Cek self hostname dari status
        $statusJson = (& $tsCli status --json 2>$null | ConvertFrom-Json 2>$null)
        if ($statusJson -and $statusJson.Self -and $statusJson.Self.HostName) {
            $tsHostname = $statusJson.Self.HostName
        }
    }
}
Print-Status "Tailscale Mesh Network" $tsConnected $(if ($tsConnected) { "Terhubung! IP Mesin: $tsIp" } else { "Belum Login / Belum Konek" })

# 4. Cek OpenSSH Server & Service
$sshInstalled = (Get-Service -Name "sshd" -ErrorAction SilentlyContinue) -or (Test-Path "C:\Windows\System32\OpenSSH\sshd.exe") -or (Test-Path "C:\Program Files\OpenSSH\sshd.exe")
$sshService = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
$sshRunning = ($sshService -and $sshService.Status -eq "Running")

Print-Status "OpenSSH Server" $sshInstalled $(if ($sshInstalled) { "Terpasang di System" } else { "Belum Terpasang" })
Print-Status "OpenSSH Service" $sshRunning $(if ($sshRunning) { "Running (Port 22)" } else { "Belum Aktif" })

# 5. Cek Firewall Port 22
$fwSsh = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq "True" }
$fwSshOk = [bool]$fwSsh
Print-Status "Firewall Port 22 (SSH)" $fwSshOk $(if ($fwSshOk) { "Allowed" } else { "Port Belum Terbuka" })

# 6. Cek Remote Desktop (RDP)
$rdpReg = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -ErrorAction SilentlyContinue).fDenyTSConnections
$rdpEnabled = ($rdpReg -eq 0)
$fwRdp = Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq "True" }
$fwRdpOk = [bool]$fwRdp

Print-Status "Remote Desktop (RDP)" ($rdpEnabled -and $fwRdpOk) $(if ($rdpEnabled -and $fwRdpOk) { "Aktif & Port 3389 Terbuka" } else { "Non-aktif" })

# 7. Cek Anti-Sleep Mode
$powerAc = powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 2>$null | Select-String "Current AC Power Setting Index:" | ForEach-Object { $_.ToString().Split(":")[-1].Trim() }
$antiSleepOk = ($powerAc -eq "0x00000000" -or $powerAc -eq "0")
Print-Status "Anti-Sleep Mode" $antiSleepOk $(if ($antiSleepOk) { "Aktif (Server Tidak Akan Sleep)" } else { "Masih Bisa Sleep" })

# 8. Cek Resiliensi & Watchdog Auto-Restart
$watchdogTask = Get-ScheduledTask -TaskName "RemoteServerKeepAlive" -ErrorAction SilentlyContinue
$watchdogOk = [bool]$watchdogTask
Print-Status "Resiliensi Watchdog" $watchdogOk $(if ($watchdogOk) { "Aktif (Auto-Heal tiap 15 mnt)" } else { "Belum Terpasang" })

Write-Host "`n----------------------------------------------------------------" -ForegroundColor Gray

if ($allPassed) {
    Write-Host "STATUS KESELURUHAN: SEMPURNA (SIAP DI-REMOTE 24/7)" -ForegroundColor Green
    
    if ($tsIp) {
        Write-Host ""
        Write-Host "================================================================" -ForegroundColor Cyan
        Write-Host "               DATA KONEKSI UNTUK APLIKASI TERMIUS              " -ForegroundColor Cyan
        Write-Host "================================================================" -ForegroundColor Cyan
        Write-Host "  Buka Termius -> Klik '+ New Host' -> Masukkan data ini:" -ForegroundColor White
        Write-Host ""
        Write-Host "  Label / Alias : $tsHostname" -ForegroundColor Yellow
        Write-Host "  Hostname / IP : $tsIp" -ForegroundColor Yellow
        Write-Host "  Port          : 22" -ForegroundColor Yellow
        Write-Host "  Username      : $env:USERNAME" -ForegroundColor Yellow
        Write-Host "  Password      : (Password login Windows akun Anda)" -ForegroundColor Yellow
        Write-Host "----------------------------------------------------------------" -ForegroundColor Gray
        Write-Host "  Quick SSH CLI : ssh $env:USERNAME@$tsIp" -ForegroundColor Cyan
        Write-Host "  Remote Desktop: Buka RDP -> Hubungkan ke $tsIp" -ForegroundColor Cyan
        Write-Host "================================================================" -ForegroundColor Cyan
    }
} else {
    Write-Host "STATUS KESELURUHAN: MASIH ADA YANG KURANG" -ForegroundColor Yellow
    Write-Host "Jalankan installer sekali lagi untuk memperbaiki komponen yang [FAIL]:" -ForegroundColor Yellow
    Write-Host "  irm https://raw.githubusercontent.com/allzxy/Auto-Setup-Remote-Desktop-or-Server/main/install.ps1 | iex" -ForegroundColor White
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
