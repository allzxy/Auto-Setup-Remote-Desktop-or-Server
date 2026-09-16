#!/usr/bin/env bash
# ==============================================================================
# Auto Setup Remote Desktop or Server (Linux)
# Debian/Ubuntu, RHEL/CentOS/Alma/Rocky, Fedora, Arch, openSUSE
# ==============================================================================

set -e

# Pastikan berjalan sebagai root
if [ "$EUID" -ne 0 ]; then
    echo "[!] Meminta izin root (sudo)..."
    exec sudo bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/setup-remote.log"

log() {
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1" >> "$LOG_FILE"
    echo -e "$1"
}

echo ""
echo "========================================================"
echo "      AUTO SETUP REMOTE DESKTOP OR SERVER (LINUX)       "
echo "========================================================"
echo ""

# Gunakan Hostname & User Default Linux (Tanpa Prompt Tambahan)
CUSTOM_HOST=$(hostname 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "linux-server")
SSH_USER=${SUDO_USER:-$USER}
DISPLAY_PASS="(Password akun '$SSH_USER')"

# Pastikan user default memiliki hak akses root/sudo
usermod -aG sudo "$SSH_USER" 2>/dev/null || usermod -aG wheel "$SSH_USER" 2>/dev/null || true

echo ""
# 1. Deteksi Package Manager
log "\e[36m>>> [1/4] Menginstall & Mengonfigurasi OpenSSH Server...\e[0m"
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y openssh-server curl
    SSH_SERVICE="ssh"
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y openssh-server curl
    SSH_SERVICE="sshd"
elif command -v yum >/dev/null 2>&1; then
    yum install -y openssh-server curl
    SSH_SERVICE="sshd"
elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm openssh curl
    SSH_SERVICE="sshd"
elif command -v zypper >/dev/null 2>&1; then
    zypper install -y openssh curl
    SSH_SERVICE="sshd"
else
    SSH_SERVICE="sshd"
fi

# Hardening SSH Config: Batasi Brute Force & Zombie Connections
SSHD_CONFIG="/etc/ssh/sshd_config"
if [ -f "$SSHD_CONFIG" ]; then
    grep -q "^MaxAuthTries" "$SSHD_CONFIG" && sed -i 's/^MaxAuthTries.*/MaxAuthTries 4/' "$SSHD_CONFIG" || echo "MaxAuthTries 4" >> "$SSHD_CONFIG"
    grep -q "^LoginGraceTime" "$SSHD_CONFIG" && sed -i 's/^LoginGraceTime.*/LoginGraceTime 30/' "$SSHD_CONFIG" || echo "LoginGraceTime 30" >> "$SSHD_CONFIG"
    grep -q "^ClientAliveInterval" "$SSHD_CONFIG" && sed -i 's/^ClientAliveInterval.*/ClientAliveInterval 300/' "$SSHD_CONFIG" || echo "ClientAliveInterval 300" >> "$SSHD_CONFIG"
fi

# Aktifkan dan jalankan OpenSSH
systemctl enable "$SSH_SERVICE" 2>/dev/null || true
systemctl restart "$SSH_SERVICE" 2>/dev/null || systemctl start "$SSH_SERVICE" 2>/dev/null || true
log "\e[32m  [OK] OpenSSH Server Aktif, Hardened & Berjalan.\e[0m"

# Buka firewall port 22 jika ada ufw atau firewalld
if command -v ufw >/dev/null 2>&1; then
    ufw allow 22/tcp >/dev/null 2>&1 || true
elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
fi

# 2. Disable Sleep / Hibernation pada Server Linux
log "\n\e[36m>>> [2/4] Mengatur Anti-Sleep Mode...\e[0m"
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true
log "\e[32m  [OK] Sleep & Suspend dinonaktifkan (Server Aktif 24/7).\e[0m"

# 3. Install Tailscale
log "\n\e[36m>>> [3/4] Menginstall & Mengonfigurasi Tailscale...\e[0m"
if ! command -v tailscale >/dev/null 2>&1; then
    log "\e[33mMendownload installer resmi Tailscale...\e[0m"
    curl -fsSL https://tailscale.com/install.sh | sh
fi

systemctl enable --now tailscaled 2>/dev/null || true
log "\e[32m  [OK] Tailscale Service Berjalan di Background.\e[0m"

# 4. Hubungkan ke Tailscale Network via Auth Key
log "\n\e[36m>>> [4/4] Mendaftarkan Server ke Mesin Tailscale...\e[0m"
KEY_FILE="$SCRIPT_DIR/tailscale-key.txt"
AUTH_KEY=""

if [ -f "$KEY_FILE" ]; then
    chmod 600 "$KEY_FILE" 2>/dev/null || true
    AUTH_KEY=$(grep -v "^#" "$KEY_FILE" | grep "tskey-auth" | head -n 1 | tr -d '\r\n ')
fi

if [ -n "$AUTH_KEY" ]; then
    log "\e[33mMenghubungkan dengan Auth Key & Hostname '$CUSTOM_HOST'...\e[0m"
    tailscale up --auth-key="$AUTH_KEY" --hostname="$CUSTOM_HOST" --unattended --accept-routes --reset=false >/dev/null 2>&1 || true
    sleep 3
    TS_IP=$(tailscale ip -4 2>/dev/null || echo "")
    if [ -n "$TS_IP" ]; then
        log "\e[32m  [OK] Tailscale Berhasil Terhubung! IP Mesin: $TS_IP\e[0m"
    fi
else
    log "\e[33m  [INFO] Auth Key tidak ditemukan. Jalankan 'tailscale up --hostname=$CUSTOM_HOST' manual jika belum login.\e[0m"
fi

echo ""
echo "========================================================"
echo "                AUDIT KELENGKAPAN SISTEM                "
echo "========================================================"

if [ -f "$SCRIPT_DIR/Status/status.sh" ]; then
    bash "$SCRIPT_DIR/Status/status.sh" --no-wait
fi

TS_IP=$(tailscale ip -4 2>/dev/null || echo "")

if [ -n "$TS_IP" ]; then
    echo ""
    echo "================================================================"
    echo -e "\e[36m               DATA KONEKSI UNTUK APLIKASI TERMIUS              \e[0m"
    echo "================================================================"
    echo "  Buka Termius -> Klik '+ New Host' -> Masukkan data ini:"
    echo ""
    echo -e "  Label / Alias : \e[33m$CUSTOM_HOST\e[0m"
    echo -e "  Hostname / IP : \e[33m$TS_IP\e[0m"
    echo -e "  Port          : \e[33m22\e[0m"
    echo -e "  Username      : \e[33m$SSH_USER\e[0m"
    echo -e "  Password      : \e[33m$DISPLAY_PASS\e[0m"
    echo "----------------------------------------------------------------"
    echo -e "  Quick SSH CLI : \e[36mssh $SSH_USER@$TS_IP\e[0m"
    echo "================================================================"
fi

echo ""
echo -e "\e[90mJendela tidak akan ditutup otomatis agar Anda bisa menyalin data di atas.\e[0m"
read -p "Tekan tombol ENTER untuk keluar..." _ < /dev/tty || true
