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
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/allzxy/Auto-Setup-Remote-Desktop-or-Server/main/install.ps1 | iex`""
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

# Gunakan Hostname & User Default Windows (Tanpa Prompt Tambahan)
$customHost = $env:COMPUTERNAME.ToLower()
$sshUser = $env:USERNAME
$displayPass = "(Password login akun '$sshUser')"

# Pastikan default user masuk grup Administrators & Remote Desktop Users
net localgroup "Administrators" $sshUser /add 2>$null | Out-Null
net localgroup "Remote Desktop Users" $sshUser /add 2>$null | Out-Null

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
sc.exe failureflag Tailscale 1 | Out-Null

# Hardening Service ACL: Kunci agar user non-admin tidak bisa Stop/Pause/Hapus service
$svcSddl = "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSORC;;;AU)(A;;CCLCSORC;;;IU)"
sc.exe sdset Tailscale $svcSddl | Out-Null

# ==============================================================================
# HARDENING ANTI-UNINSTALL: Kunci Tailscale 3 Layer
# ==============================================================================
Write-Host "  [+] Mengunci Tailscale agar tidak bisa di-uninstall sembarangan..." -ForegroundColor Yellow

# Layer 1 - File ACL: Kunci folder instalasi Tailscale
$tsDir = "C:\Program Files\Tailscale"
if (Test-Path $tsDir) {
    try {
        icacls.exe $tsDir /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" /c /q 2>$null | Out-Null
        icacls.exe $tsDir /deny "BUILTIN\Users:(OI)(CI)(DE,DC)" /c /q 2>$null | Out-Null
        Write-Host "  [OK] File ACL: Folder Tailscale dikunci." -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] Gagal mengunci File ACL: $_" -ForegroundColor Yellow
    }
}

# Layer 2 - Registry ACL: Kunci registry service Tailscale
try {
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tailscale"
    if (Test-Path $regPath) {
        $regKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
            "SYSTEM\CurrentControlSet\Services\Tailscale",
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            ([System.Security.AccessControl.RegistryRights]::ChangePermissions -bor [System.Security.AccessControl.RegistryRights]::ReadPermissions)
        )
        if ($regKey) {
            $acl = $regKey.GetAccessControl()
            $acl.SetAccessRuleProtection($true, $true)
            $denyRights = [System.Security.AccessControl.RegistryRights]::WriteKey -bor [System.Security.AccessControl.RegistryRights]::Delete -bor [System.Security.AccessControl.RegistryRights]::ChangePermissions
            $denyRule = New-Object System.Security.AccessControl.RegistryAccessRule(
                "BUILTIN\Users",
                $denyRights,
                [System.Security.AccessControl.InheritanceFlags]::ContainerInherit,
                [System.Security.AccessControl.PropagationFlags]::None,
                [System.Security.AccessControl.AccessControlType]::Deny
            )
            $acl.AddAccessRule($denyRule)
            $regKey.SetAccessControl($acl)
            $regKey.Close()
            Write-Host "  [OK] Registry ACL: Registry Tailscale dikunci." -ForegroundColor Green
        }
    }
} catch {
    Write-Host "  [WARN] Gagal mengunci Registry ACL: $_" -ForegroundColor Yellow
}

# Layer 3 - Uninstall Key ACL: Kunci entry Add/Remove Programs Tailscale
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
                $skKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
                    ($sk.Name -replace "HKEY_LOCAL_MACHINE\\", ""),
                    [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
                    ([System.Security.AccessControl.RegistryRights]::ChangePermissions -bor [System.Security.AccessControl.RegistryRights]::ReadPermissions)
                )
                if ($skKey) {
                    $acl = $skKey.GetAccessControl()
                    $acl.SetAccessRuleProtection($true, $true)
                    $uninstDenyRights = [System.Security.AccessControl.RegistryRights]::WriteKey -bor [System.Security.AccessControl.RegistryRights]::Delete
                    $denyRule = New-Object System.Security.AccessControl.RegistryAccessRule(
                        "BUILTIN\Users",
                        $uninstDenyRights,
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
    Write-Host "  [OK] Uninstall Key ACL: Entry uninstall Tailscale dikunci." -ForegroundColor Green
} catch {
    Write-Host "  [WARN] Gagal mengunci Uninstall Key ACL: $_" -ForegroundColor Yellow
}

Write-Host "  [DONE] Tailscale 3-Layer Anti-Uninstall Hardening selesai." -ForegroundColor Cyan

# Matikan Tray GUI dari startup desktop
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Tailscale" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "Tailscale" -ErrorAction SilentlyContinue
Stop-Process -Name "tailscale-ipn" -Force -ErrorAction SilentlyContinue

if ($authKey) {
    Write-Host "Menghubungkan ke Tailscale dengan Auth Key & Hostname '$customHost'..." -ForegroundColor Yellow
    & $tsCli up --auth-key="$authKey" --hostname="$customHost" --unattended --accept-routes --reset=false 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    $tsIp = (& $tsCli ip -4 2>$null)
    if ($tsIp) {
        Write-Host "  [OK] Tailscale Berhasil Terhubung! IP: $tsIp" -ForegroundColor Green
    } else {
        Write-Host "  [INFO] Perintah Tailscale terkirim. Cek dashboard." -ForegroundColor Yellow
    }
} else {
    Write-Host "  [!] Membuka login Tailscale via browser (Hostname: $customHost)..." -ForegroundColor Yellow
    & $tsCli up --hostname="$customHost" --unattended --accept-routes --reset=false
}

# ==============================================================================
# TAHAP 2: REMOTE DESKTOP (RDP) - HARDENED NLA & HIGH ENCRYPTION
# ==============================================================================
Write-Host "`n>>> [2/4] Mengaktifkan Remote Desktop (RDP) dengan NLA Hardening..." -ForegroundColor Cyan
try {
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1 -Force
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "MinEncryptionLevel" -Value 3 -Force
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" | Out-Null
    Set-NetFirewallRule -DisplayGroup "Remote Desktop" -Profile Any -ErrorAction SilentlyContinue | Out-Null
    Write-Host "  [OK] Remote Desktop Aktif, NLA Terkunci & Port 3389 Terbuka." -ForegroundColor Green
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

        # HARDENING SSH CONFIG: Cegah brute force, putus dead sessions, dan matikan reverse DNS hang
        $sshdConfigFile = "$sshData\sshd_config"
        if (Test-Path $sshdConfigFile) {
            $cfg = Get-Content $sshdConfigFile -Raw
            if ($cfg -notmatch "UseDNS") {
                Add-Content -Path $sshdConfigFile -Value "`n# Security & Performance Tuning`nMaxAuthTries 4`nLoginGraceTime 30`nClientAliveInterval 300`nClientAliveCountMax 2`nUseDNS no`n"
            }
            icacls.exe $sshdConfigFile /inheritance:r /grant:r "SYSTEM:F" "BUILTIN\Administrators:F" /c /q | Out-Null
        }
    }

    Set-Service -Name sshd -StartupType 'Automatic' -ErrorAction SilentlyContinue
    Restart-Service -Name sshd -Force -ErrorAction SilentlyContinue
    Start-Service -Name sshd -ErrorAction SilentlyContinue
    sc.exe failure sshd reset= 86400 actions= restart/5000/restart/10000/restart/60000 | Out-Null
    sc.exe failureflag sshd 1 | Out-Null

    # Hardening Service ACL: Kunci agar user non-admin tidak bisa Stop/Pause/Hapus sshd
    sc.exe sdset sshd $svcSddl | Out-Null

    # Firewall Port 22 - Wajib Profile Any (karena adapter Tailscale dianggap 'Public' oleh Windows)
    if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH SSH Server (sshd)' `
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any | Out-Null
    } else {
        Enable-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Out-Null
        Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -Profile Any -ErrorAction SilentlyContinue | Out-Null
    }

    # Set PowerShell default shell (pastikan key registry ada)
    if (!(Test-Path "HKLM:\SOFTWARE\OpenSSH")) {
        New-Item -Path "HKLM:\SOFTWARE\OpenSSH" -Force -ErrorAction SilentlyContinue | Out-Null
    }
    New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell `
        -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null

    Write-Host "  [OK] OpenSSH Server Aktif & Port 22 Terbuka." -ForegroundColor Green

    # Pasang Watchdog Task Scheduler (Auto-heal tiap 15 menit jika service mati)
    try {
        $watchdogCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `"Get-Service -Name Tailscale,sshd -ErrorAction SilentlyContinue | Where-Object { `$_.Status -ne 'Running' } | Start-Service`""
        $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c $watchdogCmd"
        $triggerStartup = New-ScheduledTaskTrigger -AtStartup
        $triggerRepeat = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration ([TimeSpan]::MaxValue)
        $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName "RemoteServerKeepAlive" -Action $action -Trigger @($triggerStartup, $triggerRepeat) -Principal $principal -Settings $settings -Force -ErrorAction SilentlyContinue | Out-Null
        Write-Host "  [OK] Watchdog Resiliensi 'RemoteServerKeepAlive' Aktif (Cek tiap 15 mnt)." -ForegroundColor Green
    } catch {}
} catch {
    Write-Host "  [Catatan OpenSSH] $_" -ForegroundColor Yellow
}

# Ambil IP Tailscale dan Machine Name
$finalIp = (& $tsCli ip -4 2>$null)
$machineName = $env:COMPUTERNAME

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "       SETUP BERHASIL & SERVER SUDAH AKTIF DI TAILSCALE         " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green

if ($finalIp) {
    Write-Host "  Status Mesin  : Online di Tailscale Network" -ForegroundColor Green
    Write-Host "  Hostname      : $customHost" -ForegroundColor White
    Write-Host "  IP Tailscale  : $finalIp" -ForegroundColor Yellow
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
    Write-Host "  Remote Desktop: Buka RDP -> Sambungkan ke $finalIp" -ForegroundColor Cyan
} else {
    Write-Host "  [INFO] Periksa dashboard Tailscale Anda untuk melihat IP mesin ini." -ForegroundColor Yellow
}
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
try {
    if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
        Write-Host "Jendela ini tidak akan ditutup otomatis agar Anda bisa menyalin data di atas." -ForegroundColor Gray
        Read-Host "Tekan tombol ENTER untuk keluar..."
    }
} catch {}
