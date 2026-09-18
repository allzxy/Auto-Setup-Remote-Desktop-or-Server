# ==============================================================================
# Auto Setup Remote Desktop or Server (Windows)
# OpenSSH via Official MSI (No Windows Update Hangs) + Tailscale + RDP
# ==============================================================================

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (!$isAdmin) {
    Write-Host "  [!] Script memerlukan hak Administrator." -ForegroundColor Yellow
    Write-Host "      Membuka jendela Administrator baru..." -ForegroundColor Yellow
    $scriptPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } elseif ($PSScriptRoot) { Join-Path $PSScriptRoot "setup-remote.ps1" } elseif (Test-Path "setup-remote.ps1") { (Resolve-Path "setup-remote.ps1").Path } else { "D:\All\Auto Setup Remote Desktop or Server\setup-remote.ps1" }
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    Exit
}

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

# Gunakan Hostname & User Default Windows (Tanpa Prompt Tambahan)
$customHost = $env:COMPUTERNAME.ToLower()
$sshUser = $env:USERNAME
$displayPass = "(Password login akun '$sshUser' / Kosongkan di Termius jika tanpa password)"

# Pastikan akun Administrator aktif untuk remote
net user Administrator /active:yes 2>$null | Out-Null
net localgroup "Administrators" "Administrator" /add 2>$null | Out-Null
net localgroup "Remote Desktop Users" "Administrator" /add 2>$null | Out-Null

Write-Host ""
# ==============================================================================
# TAHAP 1: TAILSCALE (CEK DULU SEBELUM PASANG)
# ==============================================================================
Log ">>> [1/4] Memeriksa & Menyiapkan Tailscale..." "Cyan"
$tsCli = "C:\Program Files\Tailscale\tailscale.exe"
$tsSvc = Get-Service -Name "Tailscale" -ErrorAction SilentlyContinue

if ((Test-Path $tsCli) -and ($tsSvc -and $tsSvc.Status -eq "Running")) {
    Log "  [CHECK] Tailscale sudah terpasang & service berjalan normal." "Green"
    Log "          Melewati proses download & instalasi ulang." "Gray"
} elseif (Test-Path $tsCli) {
    Log "  [CHECK] Aplikasi Tailscale sudah ada, memastikan service berjalan..." "Yellow"
    Set-Service -Name "Tailscale" -StartupType 'Automatic' -ErrorAction SilentlyContinue
    Start-Service -Name "Tailscale" -ErrorAction SilentlyContinue
} else {
    Log "  [CHECK] Tailscale belum terpasang. Mendownload installer resmi..." "Yellow"
    $installerPath = "$env:TEMP\tailscale-setup.exe"
    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile("https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe", $installerPath)
        Log "  Memasang Tailscale di latar belakang..." "Yellow"
        Start-Process -FilePath $installerPath -ArgumentList "/quiet /norestart" -Wait
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
    } catch {
        Log "  Fallback: mencoba Invoke-WebRequest..." "Yellow"
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

# Matikan Tray GUI desktop agar hemat resource
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Tailscale" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "Tailscale" -ErrorAction SilentlyContinue
Stop-Process -Name "tailscale-ipn" -Force -ErrorAction SilentlyContinue

# Login Tailscale via Auth Key jika ada
$keyFile = Join-Path $dir "tailscale-key.txt"
$authKey = ""

if (Test-Path $keyFile) {
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
    Log "  [INFO] Auth key tidak ditemukan di tailscale-key.txt. Melewati login otomatis." "Yellow"
}

# ==============================================================================
# TAHAP 2: REMOTE DESKTOP (RDP) (CEK DULU SEBELUM AKTIFKAN)
# ==============================================================================
Log "`n>>> [2/4] Memeriksa & Mengaktifkan Remote Desktop (RDP)..." "Cyan"
try {
    $rdpVal = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -ErrorAction SilentlyContinue).fDenyTSConnections
    $fwRdp = Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq "True" }

    # Pastikan RDP aktif, NLA dinonaktifkan (UserAuthentication = 0 agar akun tanpa password bisa login), dan port 3389 terbuka
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0 -Force
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 0 -Force
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "MinEncryptionLevel" -Value 2 -Force
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Out-Null
    Set-NetFirewallRule -DisplayGroup "Remote Desktop" -Profile Any -ErrorAction SilentlyContinue | Out-Null
    Log "  [OK] Remote Desktop Aktif, NLA Dinonaktifkan (Support Blank Password) & Port 3389 Terbuka." "Green"
} catch {
    Log "  [FAIL] Gagal konfigurasi RDP: $_" "Red"
}

# ==============================================================================
# TAHAP 3: POWER MANAGEMENT (KEBAL SLEEP, LOCK, LAYAR MATI & TUTUP LAPTOP)
# ==============================================================================
Log "`n>>> [3/4] Mengatur Power Plan (Kebal Sleep, Lock, & Layar Mati 24/7)..." "Cyan"
try {
    # 1. Matikan Sleep & Hibernate saat dicolok (AC) maupun baterai (DC)
    powercfg /change standby-timeout-ac 0 | Out-Null
    powercfg /change standby-timeout-dc 0 | Out-Null
    powercfg /change hibernate-timeout-ac 0 | Out-Null
    powercfg /change hibernate-timeout-dc 0 | Out-Null

    # 2. Layar boleh mati setelah 2 menit (hemat layar/baterai), tapi CPU & jaringan tetap jalan 100%
    powercfg /change monitor-timeout-ac 2 | Out-Null
    powercfg /change monitor-timeout-dc 2 | Out-Null

    # 3. Kebal Tutup Layar Laptop: Saat laptop ditutup, laptop TIDAK sleep (proses tetap jalan terus)
    powercfg /setacvalueindex scheme_current sub_buttons lidaction 0 | Out-Null
    powercfg /setdcvalueindex scheme_current sub_buttons lidaction 0 | Out-Null

    # 4. Kebal Lock Screen: Saat layar di-lock (Win+L), komputer TIDAK akan sleep setelah 2 menit
    powercfg /setacvalueindex scheme_current 238c9fa8-0aad-41ed-83f4-97be242c8f20 7bc4a2f9-d8fc-4469-b07b-33eb785aaca0 0 | Out-Null
    powercfg /setdcvalueindex scheme_current 238c9fa8-0aad-41ed-83f4-97be242c8f20 7bc4a2f9-d8fc-4469-b07b-33eb785aaca0 0 | Out-Null

    # Terapkan perubahan skema power aktif
    powercfg /setactive scheme_current | Out-Null
    Log "  [OK] Server kebal sleep, kebal lock screen, & tetap jalan saat layar ditutup/mati." "Green"
} catch {
    Log "  [FAIL] Gagal mengatur power plan: $_" "Red"
}

# ==============================================================================
# TAHAP 4: OPENSSH SERVER (CEK DULU SEBELUM PASANG)
# ==============================================================================
Log "`n>>> [4/4] Memeriksa & Mengonfigurasi OpenSSH Server..." "Cyan"
try {
    $sshSvc = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
    $sshBin = (Test-Path "C:\Windows\System32\OpenSSH\sshd.exe") -or (Test-Path "C:\Program Files\OpenSSH\sshd.exe")

    if ($sshSvc -and $sshBin) {
        Log "  [CHECK] OpenSSH Server & Service sudah terpasang di sistem." "Green"
        Log "          Melewati proses instalasi ulang." "Gray"
    } else {
        Log "  [CHECK] OpenSSH Server belum lengkap/terpasang. Memasang OpenSSH resmi..." "Yellow"
        
        # 1. Pasang via Windows Capability / DISM (Metode Resmi Windows 10/11)
        $installed = $false
        try {
            Log "  Mencoba instalasi via Add-WindowsCapability..." "Yellow"
            Add-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0" -ErrorAction SilentlyContinue | Out-Null
            if ((Get-Service -Name "sshd" -ErrorAction SilentlyContinue) -or (Test-Path "C:\Windows\System32\OpenSSH\sshd.exe")) {
                $installed = $true
            }
        } catch {}

        if (!$installed) {
            Log "  Fallback: Mencoba instalasi via DISM..." "Yellow"
            dism.exe /Online /NoRestart /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0 | Out-Null
            if ((Get-Service -Name "sshd" -ErrorAction SilentlyContinue) -or (Test-Path "C:\Windows\System32\OpenSSH\sshd.exe")) {
                $installed = $true
            }
        }

        # 2. Fallback jika DISM gagal (misal offline/WSUS diblokir)
        if (!$installed -and !(Get-Service -Name "sshd" -ErrorAction SilentlyContinue)) {
            Log "  Fallback: Mencoba instalasi via winget..." "Yellow"
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                winget install --id Microsoft.OpenSSH.Beta -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
            }
            if (!(Get-Service -Name "sshd" -ErrorAction SilentlyContinue)) {
                Log "  Fallback: Mengunduh paket OpenSSH MSI..." "Yellow"
                $sshMsi = "$env:TEMP\OpenSSH-Win64.msi"
                try {
                    $wc = New-Object System.Net.WebClient
                    $wc.DownloadFile("https://github.com/PowerShell/Win32-OpenSSH/releases/download/10.0.0.0p2-Preview/OpenSSH-Win64-v10.0.0.0.msi", $sshMsi)
                    Start-Process msiexec.exe -ArgumentList "/i `"$sshMsi`" /qn /norestart" -Wait
                    Remove-Item $sshMsi -Force -ErrorAction SilentlyContinue
                } catch {}
            }
        }

        # 3. Pastikan Service sshd Terdaftar di Windows Service Manager
        if (!(Get-Service -Name "sshd" -ErrorAction SilentlyContinue)) {
            $binToRegister = if (Test-Path "C:\Windows\System32\OpenSSH\sshd.exe") { "C:\Windows\System32\OpenSSH\sshd.exe" } elseif (Test-Path "C:\Program Files\OpenSSH\sshd.exe") { "C:\Program Files\OpenSSH\sshd.exe" } else { $null }
            if ($binToRegister) {
                New-Service -Name "sshd" -BinaryPathName "`"$binToRegister`"" -DisplayName "OpenSSH SSH Server" -StartupType Automatic | Out-Null
            }
        }
    }

    # Cari lokasi direktori instalasi OpenSSH (utamakan System32 jika service mengarah ke sana)
    $sshDir = if (Test-Path "C:\Windows\System32\OpenSSH\sshd.exe") { "C:\Windows\System32\OpenSSH" } elseif (Test-Path "C:\Program Files\OpenSSH\sshd.exe") { "C:\Program Files\OpenSSH" } else { $null }
    
    if ($sshDir -and (Test-Path "$sshDir\ssh-keygen.exe")) {
        & "$sshDir\ssh-keygen.exe" -A 2>$null | Out-Null
    }

    # FIX PERMISSION: OpenSSH menolak start jika private host key bisa diakses selain SYSTEM/Admin
    $sshData = "$env:ProgramData\ssh"
    if (Test-Path $sshData) {
        icacls.exe $sshData /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" /c /q | Out-Null
        Get-ChildItem -Path $sshData -Filter "ssh_host_*_key" -ErrorAction SilentlyContinue | ForEach-Object {
            icacls.exe $_.FullName /inheritance:r /grant:r "SYSTEM:F" "BUILTIN\Administrators:F" /c /q | Out-Null
        }

        # HARDENING SSH CONFIG & ADAPTIVE BLANK PASSWORD SUPPORT
        $sshdConfigFile = "$sshData\sshd_config"
        if (Test-Path $sshdConfigFile) {
            $cfg = Get-Content $sshdConfigFile -Raw
            # Pastikan PermitEmptyPasswords, PasswordAuthentication & KbdInteractiveAuthentication aktif agar login Termius tanpa password bisa tembus
            $cfg = $cfg -replace "(?m)^\s*#?\s*PermitEmptyPasswords\s+.*$", "PermitEmptyPasswords yes"
            $cfg = $cfg -replace "(?m)^\s*#?\s*PasswordAuthentication\s+.*$", "PasswordAuthentication yes"
            $cfg = $cfg -replace "(?m)^\s*#?\s*KbdInteractiveAuthentication\s+.*$", "KbdInteractiveAuthentication yes"
            if ($cfg -notmatch "PermitEmptyPasswords") { $cfg += "`nPermitEmptyPasswords yes" }
            if ($cfg -notmatch "PasswordAuthentication") { $cfg += "`nPasswordAuthentication yes" }
            if ($cfg -notmatch "KbdInteractiveAuthentication") { $cfg += "`nKbdInteractiveAuthentication yes" }
            if ($cfg -notmatch "PubkeyAuthentication") { $cfg += "`nPubkeyAuthentication yes" }
            if ($cfg -notmatch "UseDNS") { $cfg += "`nUseDNS no" }
            if ($cfg -notmatch "MaxAuthTries") { $cfg += "`n# Security & Performance Tuning`nMaxAuthTries 4`nLoginGraceTime 30`nClientAliveInterval 300`nClientAliveCountMax 2" }
            Set-Content -Path $sshdConfigFile -Value $cfg -Force
            icacls.exe $sshdConfigFile /inheritance:r /grant:r "SYSTEM:F" "BUILTIN\Administrators:F" /c /q | Out-Null
        }
    }

    # Buka izin Windows Security Policy agar akun tanpa password bisa login via SSH/jaringan
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Lsa' -Name 'LimitBlankPasswordUse' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null

    # Set service auto-start, start service, dan resiliensi auto-restart
    Set-Service -Name sshd -StartupType 'Automatic' -ErrorAction SilentlyContinue
    sc.exe config sshd start= auto | Out-Null
    Restart-Service -Name sshd -Force -ErrorAction SilentlyContinue
    Start-Service -Name sshd -ErrorAction SilentlyContinue
    sc.exe start sshd | Out-Null
    sc.exe failure sshd reset= 86400 actions= restart/5000/restart/10000/restart/60000 | Out-Null
    sc.exe failureflag sshd 1 | Out-Null

    # Firewall Port 22 - Wajib Profile Any & Edge Traversal (tembus meski firewall nyala ketat)
    if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH SSH Server (sshd)' `
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any -EdgeTraversalPolicy Allow | Out-Null
    } else {
        Enable-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Out-Null
        Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -Profile Any -Action Allow -Enabled True -EdgeTraversalPolicy Allow -ErrorAction SilentlyContinue | Out-Null
    }

    # Set PowerShell default shell (pastikan key registry ada)
    if (!(Test-Path "HKLM:\SOFTWARE\OpenSSH")) {
        New-Item -Path "HKLM:\SOFTWARE\OpenSSH" -Force -ErrorAction SilentlyContinue | Out-Null
    }
    New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell `
        -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null

    # Verifikasi status service aktif
    Start-Sleep -Seconds 2
    $svcCheck = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
    if ($svcCheck -and $svcCheck.Status -eq "Running") {
        Log "  [OK] OpenSSH Server Aktif & Port 22 Terbuka." "Green"
    } else {
        Log "  [WARN] Service sshd belum berstatus Running. Mencoba net start sshd..." "Yellow"
        net start sshd 2>&1 | Out-Null
        $svcCheck = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
        if ($svcCheck -and $svcCheck.Status -eq "Running") {
            Log "  [OK] OpenSSH Server Berhasil Dijalankan via net start." "Green"
        } else {
            Log "  [FAIL] Service OpenSSH gagal berjalan (Status: $($svcCheck.Status))." "Red"
        }
    }

    # Pasang Watchdog Task Scheduler (Auto-heal tiap 15 menit jika service mati)
    try {
        $watchdogCmd = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -Command `"Get-Service -Name Tailscale,sshd -ErrorAction SilentlyContinue | Where-Object { `$_.Status -ne 'Running' } | Start-Service`""
        $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c $watchdogCmd"
        $triggerStartup = New-ScheduledTaskTrigger -AtStartup
        $triggerRepeat = New-ScheduledTaskTrigger -Once -At 00:00 -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Days 3650)
        $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName "RemoteServerKeepAlive" -Action $action -Trigger @($triggerStartup, $triggerRepeat) -Principal $principal -Settings $settings -Force -ErrorAction SilentlyContinue | Out-Null
    } catch {}

    # Fallback schtasks jika Register-ScheduledTask belum tercatat
    if (!(Get-ScheduledTask -TaskName "RemoteServerKeepAlive" -ErrorAction SilentlyContinue)) {
        $fallbackTaskCmd = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -Command `"Get-Service -Name Tailscale,sshd -ErrorAction SilentlyContinue | Where-Object { `$_.Status -ne 'Running' } | Start-Service`""
        schtasks.exe /create /tn "RemoteServerKeepAlive" /tr "cmd.exe /c $fallbackTaskCmd" /sc minute /mo 15 /ru "SYSTEM" /rl HIGHEST /f 2>$null | Out-Null
    }

    if (Get-ScheduledTask -TaskName "RemoteServerKeepAlive" -ErrorAction SilentlyContinue) {
        Log "  [OK] Watchdog Resiliensi 'RemoteServerKeepAlive' Aktif (Cek tiap 15 mnt & saat boot)." "Green"
    } else {
        Log "  [WARN] Watchdog belum berhasil didaftarkan." "Yellow"
    }
} catch {
    Log "  [Catatan OpenSSH] $_" "Yellow"
}

# ==============================================================================
# TAHAP 5: HARDENING ANTI-UNINSTALL & PROTEKSI SERVICE (END-TASK PROOF)
# ==============================================================================
Log "`n>>> [5/5] Menerapkan Hardening Anti-Uninstall & Proteksi Service..." "Cyan"
try {
    # 1. Service ACL (SDDL): Cegah user non-admin stop / pause / delete service Tailscale & sshd
    $svcSddl = "D:(D;;WPDTSD;;;BU)(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWLOCRRC;;;IU)"
    sc.exe sdset Tailscale $svcSddl | Out-Null
    sc.exe sdset sshd $svcSddl | Out-Null
    Log "  [OK] Service SDDL: Tailscale & sshd dikunci dari stop/delete non-admin." "Green"

    # 2. File ACL: Kunci folder instalasi Tailscale & OpenSSH
    $tsDir = "C:\Program Files\Tailscale"
    if (Test-Path $tsDir) {
        icacls.exe $tsDir /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" /c /q 2>$null | Out-Null
        icacls.exe $tsDir /deny "BUILTIN\Users:(OI)(CI)(DE,DC)" /c /q 2>$null | Out-Null
        Log "  [OK] File ACL: Folder Tailscale dikunci (User tidak bisa hapus file)." "Green"
    }

    $sshData = "$env:ProgramData\ssh"
    if (Test-Path $sshData) {
        icacls.exe $sshData /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" /c /q 2>$null | Out-Null
        icacls.exe $sshData /deny "BUILTIN\Users:(OI)(CI)(DE,DC)" /c /q 2>$null | Out-Null
        Log "  [OK] File ACL: Folder ssh dikunci (Host keys & config terlindungi)." "Green"
    }

    $sshProg = "C:\Program Files\OpenSSH"
    if (Test-Path $sshProg) {
        icacls.exe $sshProg /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" /c /q 2>$null | Out-Null
        icacls.exe $sshProg /deny "BUILTIN\Users:(OI)(CI)(DE,DC)" /c /q 2>$null | Out-Null
        Log "  [OK] File ACL: Folder OpenSSH dikunci (File sistem terlindungi)." "Green"
    }

    # 3. Registry ACL: Kunci registry service Tailscale & sshd
    $regServices = @(
        "SYSTEM\CurrentControlSet\Services\Tailscale",
        "SYSTEM\CurrentControlSet\Services\sshd"
    )
    foreach ($regSvc in $regServices) {
        $regKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
            $regSvc,
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
        }
    }
    Log "  [OK] Registry ACL: Service registry dikunci dari modifikasi non-admin." "Green"

    # 4. Uninstall Key ACL: Kunci entry Uninstall Tailscale
    $uninstKeys = @(
        "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($baseKey in $uninstKeys) {
        $fullBase = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($baseKey)
        if ($fullBase) {
            foreach ($subName in $fullBase.GetSubKeyNames()) {
                $subKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$baseKey\$subName")
                if ($subKey) {
                    $dName = $subKey.GetValue("DisplayName")
                    $subKey.Close()
                    if ($dName -like "*Tailscale*") {
                        $targetKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
                            "$baseKey\$subName",
                            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
                            ([System.Security.AccessControl.RegistryRights]::ChangePermissions -bor [System.Security.AccessControl.RegistryRights]::ReadPermissions)
                        )
                        if ($targetKey) {
                            $acl = $targetKey.GetAccessControl()
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
                            $targetKey.SetAccessControl($acl)
                            $targetKey.Close()
                        }
                    }
                }
            }
            $fullBase.Close()
        }
    }
    Log "  [OK] Uninstall Key ACL: Entry uninstall Tailscale dikunci." "Green"
} catch {
    Log "  [WARN] Catatan hardening: $_" "Yellow"
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
    Write-Host "  Label / Alias : $customHost (Admin)" -ForegroundColor Yellow
    Write-Host "  Hostname / IP : $finalIp" -ForegroundColor Yellow
    Write-Host "  Port          : 22" -ForegroundColor Yellow
    Write-Host "  Username      : Administrator" -ForegroundColor Yellow
    Write-Host "  Password      : (KOSONGKAN / Biarkan Blank di Termius)" -ForegroundColor Yellow
    Write-Host "  Hak Akses     : Full Administrator (Sesi Remote Berhak Penuh)" -ForegroundColor Green
    Write-Host "  User Fisik    : $sshUser (Otomatis login sebagai User Biasa di layar fisik)" -ForegroundColor Gray
    Write-Host "----------------------------------------------------------------" -ForegroundColor Gray
    Write-Host "  Quick SSH CLI : ssh Administrator@$finalIp" -ForegroundColor Cyan
    Write-Host "  Remote Desktop: RDP ke $finalIp (User: Administrator, tanpa password)" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  KONFIGURASI HAK AKSES: AUTO-LOGON USER BIASA & REMOTE ADMIN   " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  1. Mengaktifkan akun Administrator untuk akses remote..." -ForegroundColor Yellow

# Pastikan akun Administrator aktif & tanpa password untuk akses remote
net user Administrator /active:yes 2>$null | Out-Null
net user Administrator "" 2>$null | Out-Null
net user Administrator /passwordreq:no 2>$null | Out-Null
net localgroup "Administrators" "Administrator" /add 2>$null | Out-Null
net localgroup "Remote Desktop Users" "Administrator" /add 2>$null | Out-Null

Write-Host "  2. Mengatur user lokal '$sshUser' sebagai User Biasa tanpa password..." -ForegroundColor Yellow
# Atur akun lokal $sshUser sebagai User Biasa (Standard User) tanpa password
net user $sshUser "" 2>$null | Out-Null
net user $sshUser /passwordreq:no 2>$null | Out-Null
net localgroup "Users" $sshUser /add 2>$null | Out-Null
net localgroup "Administrators" $sshUser /delete 2>$null | Out-Null

Write-Host "  3. Mengonfigurasi Auto-Logon langsung masuk Desktop sebagai '$sshUser'..." -ForegroundColor Yellow
# Konfigurasi Auto-Logon Windows agar pas reboot langsung masuk desktop sebagai User Biasa tanpa lock screen
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name "AutoAdminLogon" -Value "1" -Force
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name "DefaultUserName" -Value $sshUser -Force
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name "DefaultPassword" -Value "" -Force
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name "ForceAutoLogon" -Value "1" -Force
Write-Host "  [OK] Auto-Logon aktif. Sesi fisik otomatis login sebagai '$sshUser' (User Biasa)." -ForegroundColor Green
Write-Host "  [OK] Akun 'Administrator' siap di-remote dari Termius / RDP dengan hak penuh." -ForegroundColor Green

Write-Host ""
Write-Host "Sistem akan otomatis reboot dalam 10 detik agar konfigurasi jaringan & remote aktif..." -ForegroundColor Yellow
for ($i = 10; $i -gt 0; $i--) {
    Write-Host "`rRebooting dalam $i detik... (Tekan Ctrl+C untuk batalkan reboot) " -NoNewline -ForegroundColor Cyan
    Start-Sleep -Seconds 1
}
Write-Host "`nMe-reboot sistem sekarang..." -ForegroundColor Green
Restart-Computer -Force
