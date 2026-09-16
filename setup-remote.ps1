# ==============================================================================
# Auto Setup Remote Desktop or Server (Windows)
# OpenSSH via Official MSI (No Windows Update Hangs) + Tailscale + RDP
# ==============================================================================

#Requires -RunAsAdministrator
$ErrorActionPreference = "SilentlyContinue"

# Paksa TLS 1.2 & TLS 1.3
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

$dir = if ($PSScriptRoot) { $PSScriptRoot } else { "D:\All\Auto Setup Remote Desktop or Server" }
$logFile = Join-Path $dir "setup-remote.log"

function Log ($msg, $color = "White") {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] $msg" | Out-File -FilePath $logFile -Append -Encoding utf8
    Write-Host $msg -ForegroundColor $color
}

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "         AUTO SETUP REMOTE DESKTOP OR SERVER            " -ForegroundColor Cyan
Write-Host "========================================================`n" -ForegroundColor Cyan

# Input Custom Hostname & Username jika interaktif
$defaultHost = $env:COMPUTERNAME.ToLower()
$defaultUser = $env:USERNAME

if ([Environment]::UserInteractive) {
    Write-Host ""
    $inputHost = Read-Host "Masukkan Custom Hostname Tailscale [Tekan Enter untuk default: $defaultHost]"
    $customHost = if ($inputHost.Trim()) { $inputHost.Trim().ToLower() } else { $defaultHost }

    Write-Host ""
    $inputUser = Read-Host "Masukkan Username untuk Login SSH/Termius [Tekan Enter untuk default: $defaultUser]"
    $sshUser = if ($inputUser.Trim()) { $inputUser.Trim() } else { $defaultUser }
    $displayPass = "(Password login akun '$sshUser')"

    if ($sshUser -ne $defaultUser) {
        $userExists = net user $sshUser 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [!] User '$sshUser' belum terdaftar di Windows ini." -ForegroundColor Yellow
            $makeNew = Read-Host "      Buat user baru '$sshUser' sekarang secara otomatis? (Y/N)"
            if ($makeNew.Trim().ToUpper() -eq "Y") {
                $newPass = Read-Host "      Masukkan password baru untuk user '$sshUser'"
                if ($newPass) {
                    net user $sshUser $newPass /add | Out-Null
                    net localgroup "Administrators" $sshUser /add 2>$null | Out-Null
                    net localgroup "Remote Desktop Users" $sshUser /add 2>$null | Out-Null
                    $displayPass = $newPass
                    Write-Host "  [OK] User '$sshUser' berhasil dibuat & diberi hak akses Administrator/RDP!" -ForegroundColor Green
                }
            }
        } else {
            # Pastikan user yang sudah ada WAJIB punya hak Administrator & RDP
            net localgroup "Administrators" $sshUser /add 2>$null | Out-Null
            net localgroup "Remote Desktop Users" $sshUser /add 2>$null | Out-Null
            Write-Host "  [OK] User '$sshUser' dipastikan memiliki hak akses Administrator & RDP!" -ForegroundColor Green
        }
    } else {
        # Pastikan default user juga masuk grup Administrators & RDP
        net localgroup "Administrators" $sshUser /add 2>$null | Out-Null
        net localgroup "Remote Desktop Users" $sshUser /add 2>$null | Out-Null
    }
} else {
    $customHost = $defaultHost
    $sshUser = $defaultUser
    $displayPass = "(Password akun '$sshUser')"
}

Write-Host ""
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

# Pastikan service berjalan & atur Resiliensi Auto-Restart
Set-Service -Name "Tailscale" -StartupType 'Automatic' -ErrorAction SilentlyContinue
Start-Service -Name "Tailscale" -ErrorAction SilentlyContinue
sc.exe failure Tailscale reset= 86400 actions= restart/5000/restart/10000/restart/60000 | Out-Null
sc.exe failureflag Tailscale 1 | Out-Null

# Hardening Service ACL: Kunci agar user non-admin tidak bisa Stop/Pause/Hapus service
$svcSddl = "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSORC;;;AU)(A;;CCLCSORC;;;IU)"
sc.exe sdset Tailscale $svcSddl | Out-Null

# ==============================================================================
# HARDENING ANTI-UNINSTALL: Kunci Tailscale 3 Layer
# ==============================================================================
Log "  [+] Mengunci Tailscale agar tidak bisa di-uninstall sembarangan..." "Yellow"

# Layer 1 - File ACL: Kunci folder instalasi Tailscale
# Hanya SYSTEM dan Administrators yang bisa modify/delete file
$tsDir = "C:\Program Files\Tailscale"
if (Test-Path $tsDir) {
    try {
        # Reset inheritance, lalu grant hanya ke SYSTEM dan BA
        icacls.exe $tsDir /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" /c /q 2>$null | Out-Null
        # Deny Delete ke semua user biasa (Authenticated Users)
        icacls.exe $tsDir /deny "BUILTIN\Users:(OI)(CI)(DE,DC)" /c /q 2>$null | Out-Null
        Log "  [OK] File ACL: Folder Tailscale dikunci — user biasa tidak bisa hapus file." "Green"
    } catch {
        Log "  [WARN] Gagal mengunci File ACL Tailscale: $_" "Yellow"
    }
}

# Layer 2 - Registry ACL: Kunci registry service Tailscale
# Prevent non-admin dari memodifikasi registry Tailscale
try {
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tailscale"
    if (Test-Path $regPath) {
        $regKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
            "SYSTEM\CurrentControlSet\Services\Tailscale", 
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            [System.Security.AccessControl.RegistryRights]::ChangePermissions
        )
        if ($regKey) {
            $acl = $regKey.GetAccessControl()
            # Hapus inheritance dari parent
            $acl.SetAccessRuleProtection($true, $true)
            # Deny write/delete ke Users biasa
            $denyRule = New-Object System.Security.AccessControl.RegistryAccessRule(
                "BUILTIN\Users",
                [System.Security.AccessControl.RegistryRights]::WriteKey -bor
                [System.Security.AccessControl.RegistryRights]::Delete -bor
                [System.Security.AccessControl.RegistryRights]::ChangePermissions,
                [System.Security.AccessControl.InheritanceFlags]::ContainerInherit,
                [System.Security.AccessControl.PropagationFlags]::None,
                [System.Security.AccessControl.AccessControlType]::Deny
            )
            $acl.AddAccessRule($denyRule)
            $regKey.SetAccessControl($acl)
            $regKey.Close()
            Log "  [OK] Registry ACL: Registry Tailscale dikunci." "Green"
        }
    }
} catch {
    Log "  [WARN] Gagal mengunci Registry ACL Tailscale: $_" "Yellow"
}

# Layer 3 - Uninstall Key ACL: Kunci entry Add/Remove Programs Tailscale
# Prevent user biasa dari trigger uninstall via Settings > Apps
try {
    $uninstKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($baseKey in $uninstKeys) {
        if (Test-Path $baseKey) {
            $subkeys = Get-ChildItem $baseKey -ErrorAction SilentlyContinue | 
                Where-Object { ($_.GetValue("DisplayName") -like "*Tailscale*") }
            foreach ($sk in $subkeys) {
                $skPath = $sk.PSPath -replace "Microsoft.PowerShell.Core\\Registry::", ""
                $skKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
                    ($sk.Name -replace "HKEY_LOCAL_MACHINE\\", ""),
                    [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
                    [System.Security.AccessControl.RegistryRights]::ChangePermissions
                )
                if ($skKey) {
                    $acl = $skKey.GetAccessControl()
                    $acl.SetAccessRuleProtection($true, $true)
                    $denyRule = New-Object System.Security.AccessControl.RegistryAccessRule(
                        "BUILTIN\Users",
                        [System.Security.AccessControl.RegistryRights]::WriteKey -bor
                        [System.Security.AccessControl.RegistryRights]::Delete,
                        [System.Security.AccessControl.InheritanceFlags]::None,
                        [System.Security.AccessControl.PropagationFlags]::None,
                        [System.Security.AccessControl.AccessControlType]::Deny
                    )
                    $acl.AddAccessRule($denyRule)
                    $skKey.SetAccessControl($acl)
                    $skKey.Close()
                }
            }
        }
    }
    Log "  [OK] Uninstall Key ACL: Entry uninstall Tailscale dikunci." "Green"
} catch {
    Log "  [WARN] Gagal mengunci Uninstall Key ACL: $_" "Yellow"
}

Log "  [DONE] Tailscale 3-Layer Anti-Uninstall Hardening selesai." "Cyan"

# Matikan Tray GUI desktop
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Tailscale" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "Tailscale" -ErrorAction SilentlyContinue
Stop-Process -Name "tailscale-ipn" -Force -ErrorAction SilentlyContinue

# Login Tailscale via Auth Key (Hardening File Permissions)
$keyFile = Join-Path $dir "tailscale-key.txt"
$authKey = ""

if (Test-Path $keyFile) {
    # Kunci izin file tailscale-key.txt agar hanya SYSTEM dan Administrator yang bisa membaca
    icacls.exe $keyFile /inheritance:r /grant:r "SYSTEM:F" "BUILTIN\Administrators:F" /c /q 2>$null | Out-Null
    $found = Get-Content $keyFile | Where-Object { $_ -match "tskey-auth" } | Select-Object -First 1
    if ($found) { $authKey = $found.Trim() }
}

if ($authKey -and (Test-Path $tsCli)) {
    Log "Mendaftarkan server ke Tailscale network (Hostname: $customHost)..." "Yellow"
    & $tsCli up --auth-key="$authKey" --hostname="$customHost" --unattended --accept-routes --reset=false 2>&1 | Out-Null
    
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
# TAHAP 2: REMOTE DESKTOP (RDP) - HARDENED NLA & HIGH ENCRYPTION
# ==============================================================================
Log "`n>>> [2/4] Mengaktifkan Remote Desktop (RDP) dengan NLA Hardening..." "Cyan"
try {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1 -Force
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "MinEncryptionLevel" -Value 3 -Force
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" | Out-Null
    Log "  [OK] Remote Desktop Aktif, NLA Terkunci & Port 3389 Terbuka." "Green"
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

        # HARDENING SSH CONFIG: Cegah brute force dan putus dead sessions
        $sshdConfigFile = "$sshData\sshd_config"
        if (Test-Path $sshdConfigFile) {
            $cfg = Get-Content $sshdConfigFile -Raw
            if ($cfg -notmatch "MaxAuthTries") {
                Add-Content -Path $sshdConfigFile -Value "`n# Security Hardening`nMaxAuthTries 4`nLoginGraceTime 30`nClientAliveInterval 300`nClientAliveCountMax 2"
            }
            icacls.exe $sshdConfigFile /inheritance:r /grant:r "SYSTEM:F" "BUILTIN\Administrators:F" /c /q | Out-Null
        }
    }

    # Set service auto-start, start service, dan resiliensi auto-restart
    Set-Service -Name sshd -StartupType 'Automatic' -ErrorAction SilentlyContinue
    Restart-Service -Name sshd -Force -ErrorAction SilentlyContinue
    Start-Service -Name sshd -ErrorAction SilentlyContinue
    sc.exe failure sshd reset= 86400 actions= restart/5000/restart/10000/restart/60000 | Out-Null
    sc.exe failureflag sshd 1 | Out-Null

    # Hardening Service ACL: Kunci agar user non-admin tidak bisa Stop/Pause/Hapus sshd
    sc.exe sdset sshd $svcSddl | Out-Null

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

    # Pasang Watchdog Task Scheduler (Auto-heal tiap 15 menit jika service mati)
    try {
        $watchdogCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `"Get-Service -Name Tailscale,sshd -ErrorAction SilentlyContinue | Where-Object { `$_.Status -ne 'Running' } | Start-Service`""
        $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c $watchdogCmd"
        $triggerStartup = New-ScheduledTaskTrigger -AtStartup
        $triggerRepeat = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration ([TimeSpan]::MaxValue)
        $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName "RemoteServerKeepAlive" -Action $action -Trigger @($triggerStartup, $triggerRepeat) -Principal $principal -Settings $settings -Force -ErrorAction SilentlyContinue | Out-Null
        Log "  [OK] Watchdog Resiliensi 'RemoteServerKeepAlive' Aktif (Cek tiap 15 mnt)." "Green"
    } catch {}
} catch {
    Log "  [Catatan OpenSSH] $_" "Yellow"
}

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "                AUDIT KELENGKAPAN SISTEM                " -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
$statusScript = Join-Path $dir "Status\status.ps1"
if (Test-Path $statusScript) {
    & $statusScript -NoWait
}

$finalIp = (& $tsCli ip -4 2>$null)
$machineName = $env:COMPUTERNAME

if ($finalIp) {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "               DATA KONEKSI UNTUK APLIKASI TERMIUS              " -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  Buka Termius -> Klik '+ New Host' -> Masukkan data ini:" -ForegroundColor White
    Write-Host ""
    Write-Host "  Label / Alias : $customHost" -ForegroundColor Yellow
    Write-Host "  Hostname / IP : $finalIp" -ForegroundColor Yellow
    Write-Host "  Port          : 22" -ForegroundColor Yellow
    Write-Host "  Username      : $sshUser" -ForegroundColor Yellow
    Write-Host "  Password      : $displayPass" -ForegroundColor Yellow
    Write-Host "----------------------------------------------------------------" -ForegroundColor Gray
    Write-Host "  Quick SSH CLI : ssh $sshUser@$finalIp" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
}

try {
    if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
        Write-Host "`nJendela tidak akan ditutup otomatis agar Anda bisa menyalin data di atas." -ForegroundColor Gray
        Read-Host "Tekan tombol ENTER untuk keluar..."
    }
} catch {}
