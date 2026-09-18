#!/usr/bin/env bash
# ==============================================================================
# Auto Setup Remote Desktop or Server - Health & Status Audit (Linux)
# Run via terminal:
# curl -fsSL https://raw.githubusercontent.com/allzxy/Auto-Setup-Remote-Desktop-or-Server/main/Status/status.sh | bash
# ==============================================================================

NO_WAIT=false
for arg in "$@"; do
    if [ "$arg" = "--no-wait" ]; then
        NO_WAIT=true
    fi
done

if [ "$NO_WAIT" = false ]; then
    clear
fi
echo ""
echo "================================================================"
echo "        AUDIT STATUS REMOTE SERVER & REQUIREMENT (LINUX)        "
echo "================================================================"
echo ""

all_passed=true

print_status() {
    local name="$1"
    local is_ok="$2"
    local detail="$3"
    
    if [ "$is_ok" = true ]; then
        echo -e "  \e[32m[ OK ]\e[0m \e[1m$name\e[0m \e[90m($detail)\e[0m"
    else
        echo -e "  \e[31m[FAIL]\e[0m \e[33m$name\e[0m \e[31m($detail)\e[0m"
        all_passed=false
    fi
}

# 1. Internet
if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 || ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    print_status "Koneksi Internet" true "Online"
else
    print_status "Koneksi Internet" false "Offline / Gangguan"
fi

# 2. Tailscale App & Service
if command -v tailscale >/dev/null 2>&1; then
    print_status "Tailscale App" true "Terinstall ($(which tailscale))"
else
    print_status "Tailscale App" false "Belum Terinstall"
fi

if systemctl is-active --quiet tailscaled 2>/dev/null; then
    print_status "Tailscale Service" true "Running"
else
    print_status "Tailscale Service" false "Service Berhenti"
fi

# 3. Tailscale IP & Hostname
TS_IP=$(tailscale ip -4 2>/dev/null || echo "")
TS_HOST=$(hostname 2>/dev/null || echo "linux-server")

if [[ "$TS_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    print_status "Tailscale Mesh Network" true "Terhubung! IP Mesin: $TS_IP"
else
    print_status "Tailscale Mesh Network" false "Belum Login / Belum Konek"
fi

# 4. OpenSSH
SSH_INSTALLED=false
if command -v sshd >/dev/null 2>&1 || [ -f /usr/sbin/sshd ]; then
    SSH_INSTALLED=true
fi
print_status "OpenSSH Server" $SSH_INSTALLED "$(if [ "$SSH_INSTALLED" = true ]; then echo "Terpasang di System"; else echo "Belum Terpasang"; fi)"

SSH_RUNNING=false
if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
    SSH_RUNNING=true
fi
print_status "OpenSSH Service" $SSH_RUNNING "$(if [ "$SSH_RUNNING" = true ]; then echo "Running (Port 22)"; else echo "Belum Aktif"; fi)"

# 5. Anti-Sleep Mode
if [ "$(systemctl is-enabled sleep.target 2>/dev/null)" = "masked" ]; then
    print_status "Anti-Sleep Mode" true "Aktif (Server Tidak Akan Sleep)"
else
    print_status "Anti-Sleep Mode" false "Masih Bisa Sleep / Suspend"
fi

# 6. Auto-Logon tty1 (Auto masuk ke User Biasa pas reboot)
if [ -f /etc/systemd/system/getty@tty1.service.d/autologin.conf ]; then
    print_status "Auto-Logon User Biasa" true "Aktif (Otomatis login ke console)"
else
    print_status "Auto-Logon User Biasa" false "Belum Diatur"
fi

echo ""
echo "----------------------------------------------------------------"

if [ "$all_passed" = true ]; then
    echo -e "\e[32mSTATUS KESELURUHAN: SEMPURNA (SIAP DI-REMOTE 24/7)\e[0m"
    if [ -n "$TS_IP" ]; then
        echo ""
        echo "================================================================"
        echo -e "\e[36m               DATA KONEKSI UNTUK APLIKASI TERMIUS              \e[0m"
        echo "================================================================"
        echo "  Buka Termius -> Klik '+ New Host' -> Masukkan data ini:"
        echo ""
        TARGET_USER=${SUDO_USER:-$USER}
        echo -e "  Label / Alias : \e[33m$TS_HOST (Admin)\e[0m"
        echo -e "  Hostname / IP : \e[33m$TS_IP\e[0m"
        echo -e "  Port          : \e[33m22\e[0m"
        echo -e "  Username      : \e[33mroot\e[0m"
        echo -e "  Password      : \e[33m(KOSONGKAN / Biarkan Blank di Termius)\e[0m"
        echo -e "  Hak Akses     : \e[32mRoot Administrator (Sesi Remote Berhak Penuh)\e[0m"
        echo -e "  User Fisik    : \e[90m$TARGET_USER (Otomatis login sebagai User Biasa di layar fisik)\e[0m"
        echo "----------------------------------------------------------------"
        echo -e "  Quick SSH CLI : \e[36mssh root@$TS_IP\e[0m"
        echo "================================================================"
    fi
else
    echo -e "\e[33mSTATUS KESELURUHAN: MASIH ADA YANG KURANG\e[0m"
    echo -e "Jalankan installer sekali lagi:"
    echo -e "  curl -fsSL https://raw.githubusercontent.com/allzxy/Auto-Setup-Remote-Desktop-or-Server/main/install.sh | bash"
fi

if [ "$NO_WAIT" = false ]; then
    echo ""
    echo -e "\e[90mJendela tidak akan ditutup otomatis agar Anda bisa melihat log di atas.\e[0m"
    read -p "Tekan tombol ENTER untuk keluar..." _ < /dev/tty || true
fi
