# ==============================================================================
# Auto Setup Remote Desktop or Server - Clean Uninstaller (Windows)
# Run via terminal:
# irm https://raw.githubusercontent.com/allzxy/Auto-Setup-Remote-Desktop-or-Server/main/Uninstall/uninstall.ps1 | iex
# ==============================================================================

# Paksa TLS 1.2 & TLS 1.3
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

Clear-Host
Write-Host ""
Write-Host "================================================================" -ForegroundColor Red
Write-Host "       UNINSTALLER: AUTO SETUP REMOTE DESKTOP OR SERVER         " -ForegroundColor Red
Write-Host "================================================================" -ForegroundColor Red
Write-Host ""
Write-Host "  Tindakan pembersihan yang akan dilakukan:" -ForegroundColor White
Write-Host "   1. Buka semua kunci Hardening ACL (SDDL, File ACL, Registry ACL)" -ForegroundColor Gray
Write-Host "   2. Logout & Hapus aplikasi Tailscale beserta service & datanya" -ForegroundColor Gray
Write-Host "   3. Hentikan & Copot OpenSSH Server (Service, Host Keys & Config)" -ForegroundColor Gray
Write-Host "   4. Kembalikan setting Firewall (Port 22 & RDP 3389)" -ForegroundColor Gray
Write-Host "   5. Kembalikan power plan Windows (Sleep, Lid, Lock Screen normal)" -ForegroundColor Gray
Write-Host "   6. Hapus Background Task Scheduler (Keep-Alive Watchdog)" -ForegroundColor Gray
Write-Host ""

# 1. Cek Hak Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (!$isAdmin) {
    Write-Host "  [!] Script memerlukan hak Administrator." -ForegroundColor Yellow
    Write-Host "      Membuka jendela PowerShell Administrator baru..." -ForegroundColor Yellow
    $localUninst = if ($PSCommandPath) { $PSCommandPath } elseif ($PSScriptRoot) { Join-Path $PSScriptRoot "uninstall.ps1" } else { $null }
    if ($localUninst -and (Test-Path $localUninst)) {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$localUninst`""
    } else {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/allzxy/Auto-Setup-Remote-Desktop-or-Server/main/Uninstall/uninstall.ps1 | iex`""
    }
    Exit
}

# 2. Konfirmasi User
$confirm = Read-Host "Apakah Anda YAKIN ingin MENGHAPUS SEMUA komponen remote server? (Y/N)"
if ($confirm.Trim().ToUpper() -ne "Y") {
    Write-Host "`n[x] Proses uninstall dibatalkan oleh pengguna.`n" -ForegroundColor Yellow
    Exit
}

Write-Host ""
Write-Host "----------------------------------------------------------------" -ForegroundColor Gray
Write-Host "                 MEMULAI PROSES PEMBERSIHAN                     " -ForegroundColor Red
Write-Host "----------------------------------------------------------------" -ForegroundColor Gray

# ==============================================================================
# TAHAP 0: BUKA SEMUA KUNCI HARDENING ACL (SDDL, FILE, REGISTRY, UNINSTALL)
# ==============================================================================
Write-Host "`n>>> [1/6] Membuka Kunci Hardening ACL (Proteksi Service & File)..." -ForegroundColor Cyan

# 0.1 Reset Service SDDL ke default Windows
$defaultSddl = "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)"
sc.exe sdset Tailscale $defaultSddl 2>$null | Out-Null
sc.exe sdset sshd $defaultSddl 2>$null | Out-Null
Write-Host "  [OK] Service SDDL Tailscale & sshd dibuka." -ForegroundColor Green

# 0.2 Unlock File ACL: Tailscale & OpenSSH directories
$dirsToUnlock = @("C:\Program Files\Tailscale", "$env:ProgramData\ssh", "C:\Program Files\OpenSSH")
foreach ($d in $dirsToUnlock) {
    if (Test-Path $d) {
        try {
            icacls.exe $d /remove:d "BUILTIN\Users" /t /c /q 2>$null | Out-Null
            icacls.exe $d /inheritance:e /c /q 2>$null | Out-Null
            icacls.exe $d /grant:r "SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" /c /q 2>$null | Out-Null
        } catch {}
    }
}
Write-Host "  [OK] File ACL Tailscale & OpenSSH dibuka." -ForegroundColor Green

# 0.3 Unlock Registry ACL: Service registry
$regServices = @(
    "SYSTEM\CurrentControlSet\Services\Tailscale",
    "SYSTEM\CurrentControlSet\Services\sshd"
)
foreach ($regSvc in $regServices) {
    try {
        if (Test-Path "HKLM:\$regSvc") {
            $regKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
                $regSvc,
                [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
                ([System.Security.AccessControl.RegistryRights]::ChangePermissions -bor [System.Security.AccessControl.RegistryRights]::ReadPermissions)
            )
            if ($regKey) {
                $acl = $regKey.GetAccessControl()
                $denyRules = $acl.Access | Where-Object {
                    $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny -and
                    $_.IdentityReference -match "Users"
                }
                foreach ($rule in $denyRules) { $acl.RemoveAccessRule($rule) | Out-Null }
                $acl.SetAccessRuleProtection($false, $true)
                $regKey.SetAccessControl($acl)
                $regKey.Close()
            }
        }
    } catch {}
}
Write-Host "  [OK] Registry ACL Services Tailscale & sshd dibuka." -ForegroundColor Green

# 0.4 Unlock Registry ACL: Uninstall Keys
try {
    $uninstBases = @(
        "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($baseKey in $uninstBases) {
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
                            $denyRules = $acl.Access | Where-Object {
                                $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny -and
                                $_.IdentityReference -match "Users"
                            }
                            foreach ($rule in $denyRules) { $acl.RemoveAccessRule($rule) | Out-Null }
                            $acl.SetAccessRuleProtection($false, $true)
                            $targetKey.SetAccessControl($acl)
                            $targetKey.Close()
                        }
                    }
                }
            }
            $fullBase.Close()
        }
    }
    Write-Host "  [OK] Registry ACL Uninstall Key Tailscale dibuka." -ForegroundColor Green
} catch {}

# ==============================================================================
# 1. UNINSTALL TAILSCALE
# ==============================================================================
Write-Host "`n>>> [2/6] Membersihkan Tailscale..." -ForegroundColor Cyan
$tsCli = "C:\Program Files\Tailscale\tailscale.exe"
if (Test-Path $tsCli) {
    Write-Host "  - Memutuskan koneksi Tailscale (logout)..." -ForegroundColor Yellow
    & $tsCli logout 2>$null | Out-Null
    & $tsCli down 2>$null | Out-Null
}

Stop-Service -Name "Tailscale" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "tailscale", "tailscale-ipn", "tailscaled" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Cari Uninstaller Tailscale di Registry
$uninstalledTs = $false
$tsRegPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

foreach ($regPath in $tsRegPaths) {
    $apps = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*Tailscale*" }
    foreach ($app in $apps) {
        if ($app.UninstallString) {
            Write-Host "  - Menjalankan uninstaller Tailscale..." -ForegroundColor Yellow
            $uninst = $app.UninstallString
            if ($uninst -match "msiexec") {
                $guid = ($uninst -replace '.*({[A-F0-9-]+}).*', '$1')
                Start-Process msiexec.exe -ArgumentList "/x $guid /qn /norestart" -Wait
            } else {
                Start-Process cmd.exe -ArgumentList "/c `"$uninst /quiet /norestart`"" -Wait
            }
            $uninstalledTs = $true
        }
    }
}

# Fallback jika winget tersedia
if (!$uninstalledTs -and (Get-Command winget -ErrorAction SilentlyContinue)) {
    winget uninstall --id Tailscale.Tailscale -e --silent 2>$null | Out-Null
}

# Bersihkan sisa folder & service jika masih ada
Start-Sleep -Seconds 2
sc.exe delete Tailscale 2>$null | Out-Null
Remove-Item -Path "C:\Program Files\Tailscale" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:LocalAppData\Tailscale" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:ProgramData\Tailscale" -Recurse -Force -ErrorAction SilentlyContinue

# Bersihkan sisa registry Tailscale
Remove-Item -Path "HKLM:\SOFTWARE\Tailscale IPN" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "HKCU:\SOFTWARE\Tailscale IPN" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "  [OK] Tailscale berhasil dihapus sepenuhnya." -ForegroundColor Green

# ==============================================================================
# 2. UNINSTALL OPENSSH SERVER
# ==============================================================================
Write-Host "`n>>> [3/6] Membersihkan OpenSSH Server..." -ForegroundColor Cyan
Stop-Service -Name "sshd", "ssh-agent" -Force -ErrorAction SilentlyContinue
sc.exe delete sshd 2>$null | Out-Null
sc.exe delete "ssh-agent" 2>$null | Out-Null

# Copot via MSI jika terpasang dari MSI
$openSshApps = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*OpenSSH*" }
foreach ($app in $openSshApps) {
    if ($app.UninstallString -match "msiexec") {
        Write-Host "  - Mencopot OpenSSH MSI package..." -ForegroundColor Yellow
        $guid = ($app.UninstallString -replace '.*({[A-F0-9-]+}).*', '$1')
        Start-Process msiexec.exe -ArgumentList "/x $guid /qn /norestart" -Wait
    }
}

# Copot capability Windows jika terpasang via DISM/Capability
$sshCap = Get-WindowsCapability -Online -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'OpenSSH.Server*' -and $_.State -eq 'Installed' }
if ($sshCap) {
    Write-Host "  - Menghapus Windows Capability OpenSSH.Server..." -ForegroundColor Yellow
    Remove-WindowsCapability -Online -Name $sshCap.Name -ErrorAction SilentlyContinue | Out-Null
}

# Hapus sisa file sistem, host keys, dan config
Remove-Item -Path "C:\Program Files\OpenSSH" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:ProgramData\ssh" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "HKLM:\SOFTWARE\OpenSSH" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "  [OK] OpenSSH Server & data konfigurasi berhasil dihapus." -ForegroundColor Green

# ==============================================================================
# 3. KEMBALIKAN FIREWALL & RDP
# ==============================================================================
Write-Host "`n>>> [4/6] Mengembalikan Aturan Firewall & Remote Desktop..." -ForegroundColor Cyan
# Hapus firewall port 22
Remove-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Out-Null

# Nonaktifkan RDP
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 1 -ErrorAction SilentlyContinue
Disable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Out-Null
Write-Host "  [OK] Port 22 SSH ditutup dan Remote Desktop dinonaktifkan." -ForegroundColor Green

# ==============================================================================
# 4. KEMBALIKAN POWER MANAGEMENT (RESTORE SLEEP)
# ==============================================================================
Write-Host "`n>>> [5/6] Mengembalikan Pengaturan Power / Sleep..." -ForegroundColor Cyan
# Kembalikan ke setting default Windows (sleep setelah 30 menit)
powercfg /change standby-timeout-ac 30 2>$null | Out-Null
powercfg /change monitor-timeout-ac 15 2>$null | Out-Null
powercfg /setacvalueindex scheme_current sub_buttons lidaction 1 2>$null | Out-Null
powercfg /setdcvalueindex scheme_current sub_buttons lidaction 1 2>$null | Out-Null
powercfg /setacvalueindex scheme_current 238c9fa8-0aad-41ed-83f4-97be242c8f20 7bc4a2f9-d8fc-4469-b07b-33eb785aaca0 120 2>$null | Out-Null
powercfg /setdcvalueindex scheme_current 238c9fa8-0aad-41ed-83f4-97be242c8f20 7bc4a2f9-d8fc-4469-b07b-33eb785aaca0 120 2>$null | Out-Null
powercfg /setactive scheme_current 2>$null | Out-Null
Write-Host "  [OK] Power timeout & perilaku lid/lock screen dikembalikan ke standar." -ForegroundColor Green

# ==============================================================================
# 5. BERSIHKAN TASK SCHEDULER & LOG
# ==============================================================================
Write-Host "`n>>> [6/6] Membersihkan Task Scheduler & Log..." -ForegroundColor Cyan
Unregister-ScheduledTask -TaskName "RemoteServerKeepAlive" -Confirm:$false -ErrorAction SilentlyContinue
schtasks.exe /delete /tn "RemoteServerKeepAlive" /f 2>$null | Out-Null
Remove-Item -Path "D:\All\Auto Setup Remote Desktop or Server\*.log" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:TEMP\tailscale*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:TEMP\OpenSSH*" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "  [OK] Background Task Scheduler dan file log sementara dibersihkan." -ForegroundColor Green

# ==============================================================================
# 6. KEMBALIKAN HAK AKSES USER & AUTO-LOGON WINDOWS
# ==============================================================================
Write-Host "`n>>> [7/7] Mengembalikan Hak Akses User & Konfigurasi Logon..." -ForegroundColor Cyan
# 1. Matikan Auto-Logon Windows
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name "AutoAdminLogon" -Value "0" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name "ForceAutoLogon" -ErrorAction SilentlyContinue
Write-Host "  [OK] Auto-Logon dinonaktifkan." -ForegroundColor Green

# 2. Kembalikan user lokal ke grup Administrators
$currentUser = $env:USERNAME
if ($currentUser -and $currentUser -ne "Administrator") {
    net localgroup "Administrators" $currentUser /add 2>$null | Out-Null
    Write-Host "  [OK] User lokal '$currentUser' dikembalikan ke grup Administrators." -ForegroundColor Green
}

# 3. Kembalikan LSA LimitBlankPasswordUse ke standar Windows (1)
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Lsa' -Name "LimitBlankPasswordUse" -Value 1 -ErrorAction SilentlyContinue
Write-Host "  [OK] Kebijakan password Windows dikembalikan ke standar." -ForegroundColor Green

# ==============================================================================
# RINGKASAN AUDIT AKHIR
# ==============================================================================
Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "              UNINSTALL SELESAI & SISTEM BERSIH                 " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  [ OK ] Semua Kunci Hardening ACL   : Dibuka & Dibersihkan" -ForegroundColor Green
Write-Host "  [ OK ] Tailscale Application       : Terhapus Bersih" -ForegroundColor Green
Write-Host "  [ OK ] Tailscale Mesh Tunnel       : Terputus & Dihapus" -ForegroundColor Green
Write-Host "  [ OK ] OpenSSH Server & Service    : Dinonaktifkan & Dihapus" -ForegroundColor Green
Write-Host "  [ OK ] Host Keys & Config          : Dihapus dari ProgramData" -ForegroundColor Green
Write-Host "  [ OK ] Firewall Rule Port 22       : Ditutup & Dihapus" -ForegroundColor Green
Write-Host "  [ OK ] Remote Desktop (Port 3389)  : Dinonaktifkan" -ForegroundColor Green
Write-Host "  [ OK ] Power Management            : Mode Normal Diaktifkan" -ForegroundColor Green
Write-Host "  [ OK ] Task Scheduler Watchdog     : Dihapus dari Sistem" -ForegroundColor Green
Write-Host "----------------------------------------------------------------" -ForegroundColor Gray
Write-Host "  Status Sistem: Komputer Anda telah kembali ke kondisi awal." -ForegroundColor White
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
try {
    if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
        Write-Host "Jendela tidak akan ditutup otomatis agar Anda bisa melihat log di atas." -ForegroundColor Gray
        Read-Host "Tekan tombol ENTER untuk keluar..."
    }
} catch {}
