# ==============================================================================
# Setup Remote Windows Server (Super Fast-Track Edition)
# OpenSSH via Official MSI (No Windows Update Hangs) + Tailscale + RDP
# ==============================================================================

#Requires -RunAsAdministrator
$ErrorActionPreference = "SilentlyContinue"

# Paksa TLS 1.2 & TLS 1.3
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

$dir = if ($PSScriptRoot) { $PSScriptRoot } else { "D:\All\Setup Server" }
$logFile = Join-Path $dir "setup-remote.log"

function Log ($msg, $color = "White") {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] $msg" | Out-File -FilePath $logFile -Append -Encoding utf8
    Write-Host $msg -ForegroundColor $color
}

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "       MEMULAI INSTALASI & SETUP REMOTE SERVER          " -ForegroundColor Cyan
Write-Host "========================================================`n" -ForegroundColor Cyan

# ==============================================================================
# TAHAP 1: TAILSCALE (PRIORITAS UTAMA - HITUNGAN DETIK TERDAFTAR DI MACHINE)
# ==============================================================================
Log ">>> [1/4] Menginstall & Menghubungkan Tailscale..." "Cyan"
$tsCli = "C:\Program Files\Tailscale\tailscale.exe"

if (!(Test-Path $tsCli)) {
    Log "Mendownload installer resmi Tailscale..." "Yellow"
    $installerPath = "$env:TEMP\tailscale-setup.exe"
    
    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile("https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe", $installerPath)
        
        Log "Memasang Tailscale di latar belakang..." "Yellow"
        Start-Process -FilePath $installerPath -ArgumentList "/quiet /norestart" -Wait
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
    } catch {
        Log "Gagal download via WebClient, mencoba Invoke-WebRequest..." "Yellow"
        Invoke-WebRequest -Uri "https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe" -OutFile $installerPath -UseBasicParsing
        Start-Process -FilePath $installerPath -ArgumentList "/quiet /norestart" -Wait
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
    }

    $wait = 0
    while (!(Test-Path $tsCli) -and ($wait -lt 20)) {
        Start-Sleep -Seconds 2
        $wait++
    }
}

# Pastikan service berjalan
Set-Service -Name "Tailscale" -StartupType 'Automatic' -ErrorAction SilentlyContinue
Start-Service -Name "Tailscale" -ErrorAction SilentlyContinue
sc.exe failure Tailscale reset= 86400 actions= restart/5000/restart/10000/restart/60000 | Out-Null

# Matikan Tray GUI desktop
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Tailscale" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "Tailscale" -ErrorAction SilentlyContinue
Stop-Process -Name "tailscale-ipn" -Force -ErrorAction SilentlyContinue

# Login Tailscale via Auth Key
$keyFile = Join-Path $dir "tailscale-key.txt"
$authKey = ""

if (Test-Path $keyFile) {
    $found = Get-Content $keyFile | Where-Object { $_ -match "tskey-auth" } | Select-Object -First 1
    if ($found) { $authKey = $found.Trim() }
}

if ($authKey -and (Test-Path $tsCli)) {
    Log "Mendaftarkan server ke Tailscale network dengan Auth Key..." "Yellow"
    & $tsCli up --auth-key="$authKey" --unattended --accept-routes --reset=false 2>&1 | Out-Null
    
    Start-Sleep -Seconds 3
    $tsIp = (& $tsCli ip -4 2>$null)
    if ($tsIp) {
        Log "  [OK] Tailscale Berhasil Terhubung! IP Mesin: $tsIp" "Green"
    } else {
        Log "  [INFO] Perintah Tailscale terkirim." "Yellow"
    }
} else {
    Log "  [WARNING] Auth key tidak ditemukan di tailscale-key.txt." "Red"
}

# ==============================================================================
# TAHAP 2: REMOTE DESKTOP (RDP)
# ==============================================================================
Log "`n>>> [2/4] Mengaktifkan Remote Desktop (RDP)..." "Cyan"
try {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" | Out-Null
    Log "  [OK] Remote Desktop Aktif & Port 3389 Terbuka." "Green"
} catch {
    Log "  [FAIL] Gagal konfigurasi RDP: $_" "Red"
}

# ==============================================================================
# TAHAP 3: POWER MANAGEMENT (ANTI-SLEEP 24/7)
# ==============================================================================
Log "`n>>> [3/4] Mengatur Power Plan (Anti-Sleep)..." "Cyan"
try {
    powercfg /change standby-timeout-ac 0 | Out-Null
    powercfg /change hibernate-timeout-ac 0 | Out-Null
    powercfg /change monitor-timeout-ac 1 | Out-Null
    Log "  [OK] Server diatur tidak akan pernah sleep saat menyala." "Green"
} catch {
    Log "  [FAIL] Gagal mengatur power plan: $_" "Red"
}

# ==============================================================================
# TAHAP 4: OPENSSH SERVER (OFFICIAL MSI INSTALLER - CEPAT & TIDAK BIKIN STUCK)
# ==============================================================================
Log "`n>>> [4/4] Memeriksa & Menginstall OpenSSH Server..." "Cyan"
try {
    $sshInstalled = (Get-Service -Name "sshd" -ErrorAction SilentlyContinue) -or (Test-Path "C:\Program Files\OpenSSH\sshd.exe") -or (Test-Path "C:\Windows\System32\OpenSSH\sshd.exe")
    
    if (!$sshInstalled) {
        Log "Mendownload installer resmi Microsoft OpenSSH (MSI ~6MB)..." "Yellow"
        $sshMsi = "$env:TEMP\OpenSSH-Win64.msi"
        $downloaded = $false
        
        try {
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile("https://github.com/PowerShell/Win32-OpenSSH/releases/download/10.0.0.0p2-Preview/OpenSSH-Win64-v10.0.0.0.msi", $sshMsi)
            $downloaded = $true
        } catch {
            Log "Mencoba alternatif winget..." "Yellow"
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                winget install --id Microsoft.OpenSSH.Preview -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
            }
        }

        if ($downloaded -and (Test-Path $sshMsi)) {
            Log "Memasang OpenSSH MSI secara silent..." "Yellow"
            Start-Process msiexec.exe -ArgumentList "/i `"$sshMsi`" /qn /norestart" -Wait
            Remove-Item $sshMsi -Force -ErrorAction SilentlyContinue
        }

        # Fallback jika MSI belum ada
        if (!(Get-Service -Name "sshd" -ErrorAction SilentlyContinue) -and !(Test-Path "C:\Program Files\OpenSSH\sshd.exe")) {
            Log "Fallback via DISM..." "Yellow"
            dism.exe /Online /NoRestart /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0 | Out-Null
        }
    }

    # Cari lokasi direktori instalasi OpenSSH
    $sshDir = if (Test-Path "C:\Program Files\OpenSSH\sshd.exe") { "C:\Program Files\OpenSSH" } else { "C:\Windows\System32\OpenSSH" }
    
    if (Test-Path "$sshDir\ssh-keygen.exe") {
        & "$sshDir\ssh-keygen.exe" -A 2>$null | Out-Null
    }

    # FIX PERMISSION: OpenSSH menolak start jika private host key bisa diakses selain SYSTEM/Admin
    $sshData = "$env:ProgramData\ssh"
    if (Test-Path $sshData) {
        icacls.exe $sshData /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" /c /q | Out-Null
        Get-ChildItem -Path $sshData -Filter "ssh_host_*_key" -ErrorAction SilentlyContinue | ForEach-Object {
            icacls.exe $_.FullName /inheritance:r /grant:r "SYSTEM:F" "BUILTIN\Administrators:F" /c /q | Out-Null
        }
    }

    # Set service auto-start dan start service
    Set-Service -Name sshd -StartupType 'Automatic' -ErrorAction SilentlyContinue
    Restart-Service -Name sshd -Force -ErrorAction SilentlyContinue
    Start-Service -Name sshd -ErrorAction SilentlyContinue
    sc.exe failure sshd reset= 86400 actions= restart/5000/restart/10000/restart/60000 | Out-Null

    # Firewall Port 22
    if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH SSH Server (sshd)' `
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
    } else {
        Enable-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Out-Null
    }

    # Set PowerShell default shell
    New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell `
        -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force | Out-Null

    Log "  [OK] OpenSSH Server Aktif & Port 22 Terbuka." "Green"
} catch {
    Log "  [Catatan OpenSSH] $_" "Yellow"
}

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "                AUDIT KELENGKAPAN SISTEM                " -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

& (Join-Path $dir "cek-status.ps1")
