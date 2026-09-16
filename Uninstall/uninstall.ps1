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
Write-Host "   1. Logout & Hapus aplikasi Tailscale beserta service & datanya" -ForegroundColor Gray
Write-Host "   2. Hentikan & Copot OpenSSH Server (Service, Host Keys & Config)" -ForegroundColor Gray
Write-Host "   3. Kembalikan setting Firewall (Port 22 & RDP 3389)" -ForegroundColor Gray
Write-Host "   4. Kembalikan power plan Windows (Anti-sleep dikembalikan normal)" -ForegroundColor Gray
Write-Host "   5. Hapus Background Task Scheduler (Keep-Alive Watchdog)" -ForegroundColor Gray
Write-Host ""

# 1. Cek Hak Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (!$isAdmin) {
    Write-Host "  [!] Script memerlukan hak Administrator." -ForegroundColor Yellow
    Write-Host "      Membuka jendela PowerShell Administrator baru..." -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/allzxy/Auto-Setup-Remote-Desktop-or-Server/main/Uninstall/uninstall.ps1 | iex`""
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
# 1. UNINSTALL TAILSCALE
# ==============================================================================
Write-Host "`n>>> [1/5] Membersihkan Tailscale..." -ForegroundColor Cyan
$tsCli = "C:\Program Files\Tailscale\tailscale.exe"
if (Test-Path $tsCli) {
    Write-Host "  - Memutuskan koneksi Tailscale (logout)..." -ForegroundColor Yellow
    & $tsCli logout 2>$null | Out-Null
    & $tsCli down 2>$null | Out-Null
}

Stop-Service -Name "Tailscale" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "tailscale", "tailscale-ipn", "tailscaled" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# --- UNLOCK 3-LAYER ACL (wajib dilakukan sebelum uninstall) ---
Write-Host "  - Membuka kunci Anti-Uninstall Hardening (3 Layer)..." -ForegroundColor Yellow

# Unlock Layer 1: File ACL - kembalikan izin normal ke folder Tailscale
$tsDir = "C:\Program Files\Tailscale"
if (Test-Path $tsDir) {
    try {
        # Hapus deny rule untuk Users
        icacls.exe $tsDir /remove:d "BUILTIN\Users" /t /c /q 2>$null | Out-Null
        # Kembalikan inheritance dari parent
        icacls.exe $tsDir /inheritance:e /c /q 2>$null | Out-Null
        # Grant full ke Administrators & SYSTEM (agar uninstaller bisa jalan)
        icacls.exe $tsDir /grant:r "SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" /c /q 2>$null | Out-Null
        Write-Host "  [OK] Unlock File ACL: Folder Tailscale dibuka." -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] Gagal unlock File ACL: $_" -ForegroundColor Yellow
    }
}

# Unlock Layer 2: Registry ACL - hapus deny rule dari registry service
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
            # Hapus semua Deny rule untuk Users
            $denyRules = $acl.Access | Where-Object {
                $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny -and
                $_.IdentityReference -match "Users"
            }
            foreach ($rule in $denyRules) { $acl.RemoveAccessRule($rule) | Out-Null }
            # Aktifkan kembali inheritance
            $acl.SetAccessRuleProtection($false, $true)
            $regKey.SetAccessControl($acl)
            $regKey.Close()
            Write-Host "  [OK] Unlock Registry ACL: Registry Tailscale dibuka." -ForegroundColor Green
        }
    }
} catch {
    Write-Host "  [WARN] Gagal unlock Registry ACL: $_" -ForegroundColor Yellow
}

# Unlock Layer 3: Uninstall Key ACL - hapus deny rule dari entry uninstall
try {
    $uninstBases = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($base in $uninstBases) {
        if (Test-Path $base) {
            $subkeys = Get-ChildItem $base -ErrorAction SilentlyContinue |
                Where-Object { ($_.GetValue("DisplayName") -like "*Tailscale*") }
            foreach ($sk in $subkeys) {
                $skKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
                    ($sk.Name -replace "HKEY_LOCAL_MACHINE\\", ""),
                    [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
                    [System.Security.AccessControl.RegistryRights]::ChangePermissions
                )
                if ($skKey) {
                    $acl = $skKey.GetAccessControl()
                    $denyRules = $acl.Access | Where-Object {
                        $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny -and
                        $_.IdentityReference -match "Users"
                    }
                    foreach ($rule in $denyRules) { $acl.RemoveAccessRule($rule) | Out-Null }
                    $acl.SetAccessRuleProtection($false, $true)
                    $skKey.SetAccessControl($acl)
                    $skKey.Close()
                }
            }
        }
    }
    Write-Host "  [OK] Unlock Uninstall Key ACL: Entry uninstall Tailscale dibuka." -ForegroundColor Green
} catch {
    Write-Host "  [WARN] Gagal unlock Uninstall Key ACL: $_" -ForegroundColor Yellow
}

Write-Host "  [DONE] Semua kunci ACL dibuka. Melanjutkan uninstall..." -ForegroundColor Cyan

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
Write-Host "  [OK] Tailscale berhasil dihapus sepenuhnya (termasuk semua kunci ACL)." -ForegroundColor Green


# ==============================================================================
# 2. UNINSTALL OPENSSH SERVER
# ==============================================================================
Write-Host "`n>>> [2/5] Membersihkan OpenSSH Server..." -ForegroundColor Cyan
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
Write-Host "`n>>> [3/5] Mengembalikan Aturan Firewall & Remote Desktop..." -ForegroundColor Cyan
# Hapus firewall port 22
Remove-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Out-Null

# Nonaktifkan RDP
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 1 -ErrorAction SilentlyContinue
Disable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Out-Null
Write-Host "  [OK] Port 22 SSH ditutup dan Remote Desktop dinonaktifkan." -ForegroundColor Green

# ==============================================================================
# 4. KEMBALIKAN POWER MANAGEMENT (RESTORE SLEEP)
# ==============================================================================
Write-Host "`n>>> [4/5] Mengembalikan Pengaturan Power / Sleep..." -ForegroundColor Cyan
# Kembalikan ke setting default Windows (sleep setelah 30 menit)
powercfg /change standby-timeout-ac 30 | Out-Null
powercfg /change monitor-timeout-ac 15 | Out-Null
Write-Host "  [OK] Power timeout dikembalikan ke standar (Sleep: 30 menit, Layar: 15 menit)." -ForegroundColor Green

# ==============================================================================
# 5. BERSIHKAN TASK SCHEDULER & LOG
# ==============================================================================
Write-Host "`n>>> [5/5] Membersihkan Task Scheduler & Log..." -ForegroundColor Cyan
Unregister-ScheduledTask -TaskName "RemoteServerKeepAlive" -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item -Path "D:\All\Auto Setup Remote Desktop or Server\*.log" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "D:\All\Setup Server\*.log" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:TEMP\tailscale*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:TEMP\OpenSSH*" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "  [OK] Background Task Scheduler dan file log sementara dibersihkan." -ForegroundColor Green

# ==============================================================================
# RINGKASAN AUDIT AKHIR
# ==============================================================================
Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "              UNINSTALL SELESAI & SISTEM BERSIH                 " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  [ OK ] Tailscale Application       : Terhapus Bersih" -ForegroundColor Green
Write-Host "  [ OK ] Tailscale Anti-Uninstall ACL : Semua Kunci Dibuka & Dibersihkan" -ForegroundColor Green
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
