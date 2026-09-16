# ==============================================================================
# Auto Setup Remote Desktop or Server - Web One-Liner Installer (Windows)
# Run: irm https://raw.githubusercontent.com/allzxy/Auto-Setup-Remote-Desktop-or-Server/main/install.ps1 | iex
# ==============================================================================

# Paksa TLS 1.2 & TLS 1.3
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

Clear-Host
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "         AUTO SETUP REMOTE DESKTOP OR SERVER (WINDOWS)          " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Script ini akan mengonfigurasi:" -ForegroundColor White
Write-Host "   1. Tailscale Mesh VPN (Akses aman tanpa port forwarding)" -ForegroundColor Gray
Write-Host "   2. OpenSSH Server (Terminal remote via Port 22)" -ForegroundColor Gray
Write-Host "   3. Remote Desktop / RDP (GUI remote via Port 3389)" -ForegroundColor Gray
Write-Host "   4. Anti-Sleep 24/7 (Mencegah komputer standby/sleep)" -ForegroundColor Gray
Write-Host ""

# 1. Cek Hak Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (!$isAdmin) {
    Write-Host "  [!] Script memerlukan hak Administrator." -ForegroundColor Yellow
    Write-Host "      Membuka jendela PowerShell Administrator baru..." -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/allzxy/Auto-Setup-Remote-Desktop-or-Server/main/install.ps1 | iex`""
    Exit
}

# 2. Konfirmasi Persetujuan User
$confirm = Read-Host "Apakah Anda setuju untuk melanjutkan instalasi & setup? (Y/N)"
if ($confirm.Trim().ToUpper() -ne "Y") {
    Write-Host "`n[x] Instalasi dibatalkan oleh pengguna.`n" -ForegroundColor Red
    Exit
}

# 3. Minta Input Auth Key Tailscale
Write-Host ""
Write-Host "Dapatkan Auth Key di: https://login.tailscale.com/admin/settings/keys" -ForegroundColor DarkGray
$authKey = Read-Host "Masukkan Tailscale Auth Key (Tekan Enter jika ingin login manual lewat browser)"
$authKey = $authKey.Trim()

Write-Host ""
Write-Host "----------------------------------------------------------------" -ForegroundColor Gray
Write-Host "                 MEMULAI PROSES INSTALASI                       " -ForegroundColor Cyan
Write-Host "----------------------------------------------------------------" -ForegroundColor Gray

# ==============================================================================
# TAHAP 1: TAILSCALE
# ==============================================================================
Write-Host "`n>>> [1/4] Menginstall & Menghubungkan Tailscale..." -ForegroundColor Cyan
$tsCli = "C:\Program Files\Tailscale\tailscale.exe"

if (!(Test-Path $tsCli)) {
    Write-Host "Mendownload installer resmi Tailscale..." -ForegroundColor Yellow
    $installerPath = "$env:TEMP\tailscale-setup.exe"
    
    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile("https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe", $installerPath)
        Write-Host "Memasang Tailscale di latar belakang..." -ForegroundColor Yellow
        Start-Process -FilePath $installerPath -ArgumentList "/quiet /norestart" -Wait
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "Fallback via winget..." -ForegroundColor Yellow
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            winget install --id Tailscale.Tailscale -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
        }
    }

    $wait = 0
    while (!(Test-Path $tsCli) -and ($wait -lt 20)) {
        Start-Sleep -Seconds 2
        $wait++
    }
}

Set-Service -Name "Tailscale" -StartupType 'Automatic' -ErrorAction SilentlyContinue
Start-Service -Name "Tailscale" -ErrorAction SilentlyContinue
sc.exe failure Tailscale reset= 86400 actions= restart/5000/restart/10000/restart/60000 | Out-Null

# Matikan Tray GUI dari startup desktop
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Tailscale" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "Tailscale" -ErrorAction SilentlyContinue
Stop-Process -Name "tailscale-ipn" -Force -ErrorAction SilentlyContinue

if ($authKey) {
    Write-Host "Menghubungkan ke Tailscale dengan Auth Key..." -ForegroundColor Yellow
    & $tsCli up --auth-key="$authKey" --unattended --accept-routes --reset=false 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    $tsIp = (& $tsCli ip -4 2>$null)
    if ($tsIp) {
        Write-Host "  [OK] Tailscale Berhasil Terhubung! IP: $tsIp" -ForegroundColor Green
    } else {
        Write-Host "  [INFO] Perintah Tailscale terkirim. Cek dashboard." -ForegroundColor Yellow
    }
} else {
    Write-Host "  [!] Membuka login Tailscale via browser..." -ForegroundColor Yellow
    & $tsCli up --unattended --accept-routes --reset=false
}

# ==============================================================================
# TAHAP 2: REMOTE DESKTOP (RDP)
# ==============================================================================
Write-Host "`n>>> [2/4] Mengaktifkan Remote Desktop (RDP)..." -ForegroundColor Cyan
try {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" | Out-Null
    Write-Host "  [OK] Remote Desktop Aktif (Port 3389 Terbuka)." -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] Gagal konfigurasi RDP: $_" -ForegroundColor Red
}

# ==============================================================================
# TAHAP 3: POWER MANAGEMENT (ANTI-SLEEP)
# ==============================================================================
Write-Host "`n>>> [3/4] Mengatur Power Management (Anti-Sleep)..." -ForegroundColor Cyan
try {
    powercfg /change standby-timeout-ac 0 | Out-Null
    powercfg /change hibernate-timeout-ac 0 | Out-Null
    powercfg /change monitor-timeout-ac 1 | Out-Null
    Write-Host "  [OK] Sleep & Hibernate dimatikan saat server menyala." -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] Gagal mengatur power plan: $_" -ForegroundColor Red
}

# ==============================================================================
# TAHAP 4: OPENSSH SERVER
# ==============================================================================
Write-Host "`n>>> [4/4] Memeriksa & Menginstall OpenSSH Server..." -ForegroundColor Cyan
try {
    $sshInstalled = (Get-Service -Name "sshd" -ErrorAction SilentlyContinue) -or (Test-Path "C:\Program Files\OpenSSH\sshd.exe") -or (Test-Path "C:\Windows\System32\OpenSSH\sshd.exe")
    
    if (!$sshInstalled) {
        Write-Host "Mendownload paket resmi OpenSSH MSI (~6MB)..." -ForegroundColor Yellow
        $sshMsi = "$env:TEMP\OpenSSH-Win64.msi"
        $downloaded = $false
        
        try {
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile("https://github.com/PowerShell/Win32-OpenSSH/releases/download/10.0.0.0p2-Preview/OpenSSH-Win64-v10.0.0.0.msi", $sshMsi)
            $downloaded = $true
        } catch {
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                winget install --id Microsoft.OpenSSH.Preview -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
            }
        }

        if ($downloaded -and (Test-Path $sshMsi)) {
            Write-Host "Memasang OpenSSH MSI..." -ForegroundColor Yellow
            Start-Process msiexec.exe -ArgumentList "/i `"$sshMsi`" /qn /norestart" -Wait
            Remove-Item $sshMsi -Force -ErrorAction SilentlyContinue
        }

        if (!(Get-Service -Name "sshd" -ErrorAction SilentlyContinue) -and !(Test-Path "C:\Program Files\OpenSSH\sshd.exe")) {
            dism.exe /Online /NoRestart /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0 | Out-Null
        }
    }

    $sshDir = if (Test-Path "C:\Program Files\OpenSSH\sshd.exe") { "C:\Program Files\OpenSSH" } else { "C:\Windows\System32\OpenSSH" }
    if (Test-Path "$sshDir\ssh-keygen.exe") {
        & "$sshDir\ssh-keygen.exe" -A 2>$null | Out-Null
    }

    # Fix permission host key
    $sshData = "$env:ProgramData\ssh"
    if (Test-Path $sshData) {
        icacls.exe $sshData /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" /c /q | Out-Null
        Get-ChildItem -Path $sshData -Filter "ssh_host_*_key" -ErrorAction SilentlyContinue | ForEach-Object {
            icacls.exe $_.FullName /inheritance:r /grant:r "SYSTEM:F" "BUILTIN\Administrators:F" /c /q | Out-Null
        }
    }

    Set-Service -Name sshd -StartupType 'Automatic' -ErrorAction SilentlyContinue
    Restart-Service -Name sshd -Force -ErrorAction SilentlyContinue
    Start-Service -Name sshd -ErrorAction SilentlyContinue
    sc.exe failure sshd reset= 86400 actions= restart/5000/restart/10000/restart/60000 | Out-Null

    if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH SSH Server (sshd)' `
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
    } else {
        Enable-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Out-Null
    }

    New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell `
        -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force | Out-Null

    Write-Host "  [OK] OpenSSH Server Aktif & Port 22 Terbuka." -ForegroundColor Green
} catch {
    Write-Host "  [Catatan OpenSSH] $_" -ForegroundColor Yellow
}

# Ambil IP Tailscale akhir
$finalIp = (& $tsCli ip -4 2>$null)

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "              SETUP BERHASIL & SERVER SIAP DIREMOTE             " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
if ($finalIp) {
    Write-Host "  IP Tailscale Server : $finalIp" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Cara Remote dari Luar Jaringan:" -ForegroundColor White
    Write-Host "   1. SSH Terminal  : ssh $env:USERNAME@$finalIp" -ForegroundColor Cyan
    Write-Host "   2. Remote Desktop: Buka RDP -> Hubungkan ke $finalIp" -ForegroundColor Cyan
} else {
    Write-Host "  Periksa dashboard Tailscale Anda untuk melihat IP mesin ini." -ForegroundColor Yellow
}
Write-Host "================================================================`n" -ForegroundColor Green
