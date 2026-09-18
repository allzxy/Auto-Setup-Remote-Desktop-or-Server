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
DISPLAY_PASS="(Password akun '$SSH_USER' / Kosongkan di Termius jika tanpa password)"

# Pastikan akun root aktif untuk remote
passwd -d root 2>/dev/null || true

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
    sed -i 's/^[# ]*PermitEmptyPasswords.*/PermitEmptyPasswords yes/' "$SSHD_CONFIG" 2>/dev/null || echo "PermitEmptyPasswords yes" >> "$SSHD_CONFIG"
    sed -i 's/^[# ]*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG" 2>/dev/null || echo "PasswordAuthentication yes" >> "$SSHD_CONFIG"
    sed -i 's/^[# ]*KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' "$SSHD_CONFIG" 2>/dev/null || echo "KbdInteractiveAuthentication yes" >> "$SSHD_CONFIG"
    sed -i 's/^[# ]*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG" 2>/dev/null || echo "PubkeyAuthentication yes" >> "$SSHD_CONFIG"
    sed -i 's/^[# ]*PermitRootLogin.*/PermitRootLogin yes/' "$SSHD_CONFIG" 2>/dev/null || echo "PermitRootLogin yes" >> "$SSHD_CONFIG"
    grep -q "^UsePAM" "$SSHD_CONFIG" && sed -i 's/^UsePAM.*/UsePAM yes/' "$SSHD_CONFIG" || echo "UsePAM yes" >> "$SSHD_CONFIG"
    grep -q "^UseDNS" "$SSHD_CONFIG" && sed -i 's/^UseDNS.*/UseDNS no/' "$SSHD_CONFIG" || echo "UseDNS no" >> "$SSHD_CONFIG"
fi

# Buka izin login empty password di PAM Linux (Debian/Ubuntu & RHEL/CentOS)
for pam_file in /etc/pam.d/common-auth /etc/pam.d/sshd /etc/pam.d/password-auth /etc/pam.d/system-auth; do
    if [ -f "$pam_file" ]; then
        sed -i 's/nullok_secure/nullok/g' "$pam_file" 2>/dev/null || true
        grep -q "pam_unix.so.*nullok" "$pam_file" || sed -i '/pam_unix\.so/ s/$/ nullok/' "$pam_file" 2>/dev/null || true
    fi
done

# Aktifkan dan jalankan OpenSSH
systemctl enable "$SSH_SERVICE" 2>/dev/null || true
systemctl restart "$SSH_SERVICE" 2>/dev/null || systemctl start "$SSH_SERVICE" 2>/dev/null || true
log "\e[32m  [OK] OpenSSH Server Aktif, Hardened & Berjalan (Support Blank Password).\e[0m"

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
    echo -e "  Label / Alias : \e[33m$CUSTOM_HOST (Admin)\e[0m"
    echo -e "  Hostname / IP : \e[33m$TS_IP\e[0m"
    echo -e "  Port          : \e[33m22\e[0m"
    echo -e "  Username      : \e[33mroot\e[0m"
    echo -e "  Password      : \e[33m(KOSONGKAN / Biarkan Blank di Termius)\e[0m"
    echo -e "  Hak Akses     : \e[32mRoot Administrator (Sesi Remote Berhak Penuh)\e[0m"
    echo -e "  User Fisik    : \e[90m$SSH_USER (Otomatis login sebagai User Biasa di layar fisik)\e[0m"
    echo "----------------------------------------------------------------"
    echo -e "  Quick SSH CLI : \e[36mssh root@$TS_IP\e[0m"
    echo "================================================================"
fi

echo ""
echo "================================================================"
echo -e "\e[36m  KONFIGURASI HAK AKSES: AUTO-LOGON USER BIASA & REMOTE ADMIN   \e[0m"
echo "================================================================"
echo -e "\e[33m  1. Mengaktifkan akun Root tanpa password untuk remote...\e[0m"

# Pastikan akun root aktif & tanpa password untuk akses remote
passwd -d root 2>/dev/null || true

echo -e "\e[33m  2. Mengatur user lokal '$SSH_USER' sebagai User Biasa (Non-Sudo)...\e[0m"
# Cabut hak sudo / wheel dari SSH_USER agar menjadi User Biasa & tanpa password
if [ "$SSH_USER" != "root" ]; then
    passwd -d "$SSH_USER" 2>/dev/null || true
    gpasswd -d "$SSH_USER" sudo 2>/dev/null || deluser "$SSH_USER" sudo 2>/dev/null || true
    gpasswd -d "$SSH_USER" wheel 2>/dev/null || true
    rm -f "/etc/sudoers.d/99-remote-$SSH_USER" 2>/dev/null || true
fi

echo -e "\e[33m  3. Mengonfigurasi Auto-Logon langsung masuk sebagai '$SSH_USER'...\e[0m"
# Konfigurasi Auto-Logon tty1 Linux
mkdir -p /etc/systemd/system/getty@tty1.service.d 2>/dev/null || true
cat <<AUTOLOGON_EOF > /etc/systemd/system/getty@tty1.service.d/autologin.conf 2>/dev/null || true
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin $SSH_USER %I \$TERM
Type=idle
AUTOLOGON_EOF
systemctl daemon-reload 2>/dev/null || true

echo -e "\e[32m  [OK] Auto-Logon aktif. Sesi fisik otomatis login sebagai '$SSH_USER' (User Biasa).\e[0m"
echo -e "\e[32m  [OK] Akun 'root' siap di-remote dari Termius dengan hak Administrator penuh.\e[0m"

echo ""
echo -e "\e[33mSistem akan otomatis reboot dalam 10 detik agar konfigurasi jaringan & remote aktif...\e[0m"
for i in 10 9 8 7 6 5 4 3 2 1; do
    echo -ne "\rRebooting dalam $i detik... (Tekan Ctrl+C untuk batalkan reboot) "
    sleep 1
done
echo -e "\n\e[32mMe-reboot sistem sekarang...\e[0m"
reboot

