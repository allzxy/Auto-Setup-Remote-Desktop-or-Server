#!/usr/bin/env bash
# ==============================================================================
# Linux Server Requirement & Health Check
# ==============================================================================

echo ""
echo "========================================================"
echo "         AUDIT STATUS REMOTE SERVER & REQUIREMENT        "
echo "========================================================"
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

# 3. Tailscale IP
TS_IP=$(tailscale ip -4 2>/dev/null || echo "")
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

echo ""
echo "--------------------------------------------------------"

if [ "$all_passed" = true ]; then
    echo -e "\e[32mSTATUS KESELURUHAN: SEMPURNA (SIAP DI-REMOTE 24/7)\e[0m"
    if [ -n "$TS_IP" ]; then
        echo -e "\n\e[33mCara Remote dari Luar Jaringan:\e[0m"
        echo -e "  SSH : ssh $USER@$TS_IP"
    fi
else
    echo -e "\e[33mSTATUS KESELURUHAN: MASIH ADA YANG KURANG\e[0m"
    echo -e "Jalankan 'sudo bash setup-linux.sh' sekali lagi."
fi

echo "========================================================"
echo ""
