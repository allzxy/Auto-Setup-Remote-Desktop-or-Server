#!/usr/bin/env bash
# ==============================================================================
# Auto Setup Remote Desktop or Server - Web One-Liner Installer (Linux)
# Run: curl -fsSL https://raw.githubusercontent.com/allzxy/Auto-Setup-Remote-Desktop-or-Server/main/install.sh | bash
# ==============================================================================

set -e

# Pastikan root
if [ "$EUID" -ne 0 ]; then
    echo "[!] Meminta izin root (sudo)..."
    exec sudo bash "$0" "$@"
fi

clear
echo ""
echo "================================================================"
echo "         AUTO SETUP REMOTE DESKTOP OR SERVER (LINUX)            "
echo "================================================================"
echo ""
echo "  Script ini akan mengonfigurasi:"
echo "   1. Tailscale Mesh VPN (Akses aman tanpa port forwarding)"
echo "   2. OpenSSH Server (Terminal remote via Port 22)"
echo "   3. Anti-Sleep 24/7 (Menonaktifkan sleep/suspend pada server)"
echo ""

# 1. Konfirmasi User (Gunakan /dev/tty agar kompatibel dengan curl | bash)
read -p "Apakah Anda setuju untuk melanjutkan instalasi & setup? (y/N): " confirm < /dev/tty
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "\n\e[31m[x] Instalasi dibatalkan oleh pengguna.\e[0m\n"
    exit 0
fi

# 2. Input Auth Key
echo ""
echo "Dapatkan Auth Key di: https://login.tailscale.com/admin/settings/keys"
read -p "Masukkan Tailscale Auth Key (kosongkan jika mau login browser manual): " auth_key < /dev/tty
auth_key=$(echo "$auth_key" | tr -d '\r\n ')

# Gunakan Hostname & User Default Linux (Tanpa Prompt Tambahan)
CUSTOM_HOST=$(hostname 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "linux-server")
SSH_USER=${SUDO_USER:-$USER}
DISPLAY_PASS="(Password akun '$SSH_USER' / Kosongkan di Termius jika tanpa password)"

# Pastikan user default memiliki hak akses root/sudo
usermod -aG sudo "$SSH_USER" 2>/dev/null || usermod -aG wheel "$SSH_USER" 2>/dev/null || true

echo ""
echo "----------------------------------------------------------------"
echo "                 MEMULAI PROSES INSTALASI                       "
echo "----------------------------------------------------------------"

# 1. OpenSSH
echo -e "\n\e[36m>>> [1/3] Menginstall & Mengonfigurasi OpenSSH Server...\e[0m"
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
else
    SSH_SERVICE="sshd"
fi

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

systemctl enable "$SSH_SERVICE" 2>/dev/null || true
systemctl restart "$SSH_SERVICE" 2>/dev/null || systemctl start "$SSH_SERVICE" 2>/dev/null || true
echo -e "\e[32m  [OK] OpenSSH Server Aktif & Terkonfigurasi (Support Blank Password).\e[0m"

# Firewall 22
if command -v ufw >/dev/null 2>&1; then
    ufw allow 22/tcp >/dev/null 2>&1 || true
elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
fi

# 2. Anti-Sleep Mode
echo -e "\n\e[36m>>> [2/3] Mengatur Anti-Sleep Mode...\e[0m"
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true
echo -e "\e[32m  [OK] Sleep & Suspend dimatikan (Server 24/7).\e[0m"

# 3. Tailscale
echo -e "\n\e[36m>>> [3/3] Menginstall & Mengonfigurasi Tailscale...\e[0m"
if ! command -v tailscale >/dev/null 2>&1; then
    curl -fsSL https://tailscale.com/install.sh | sh
fi

systemctl enable --now tailscaled 2>/dev/null || true

if [ -n "$auth_key" ]; then
    echo "Menghubungkan ke Tailscale dengan Auth Key & Hostname '$CUSTOM_HOST'..."
    tailscale up --auth-key="$auth_key" --hostname="$CUSTOM_HOST" --unattended --accept-routes --reset=false >/dev/null 2>&1 || true
    sleep 3
else
    echo "Login manual via Tailscale (Hostname: $CUSTOM_HOST)..."
    tailscale up --hostname="$CUSTOM_HOST" --accept-routes
fi

FINAL_IP=$(tailscale ip -4 2>/dev/null || echo "")

echo ""
echo "================================================================"
echo -e "\e[32m              SETUP BERHASIL & SERVER SIAP DIREMOTE             \e[0m"
echo "================================================================"
if [ -n "$FINAL_IP" ]; then
    echo -e "  Status Mesin  : \e[32mOnline di Tailscale Network\e[0m"
    echo -e "  Hostname      : \e[1m$CUSTOM_HOST\e[0m"
    echo -e "  IP Tailscale  : \e[33m$FINAL_IP\e[0m"
    echo ""
    echo "================================================================"
    echo -e "\e[36m               DATA KONEKSI UNTUK APLIKASI TERMIUS              \e[0m"
    echo "================================================================"
    echo "  Buka Termius -> Klik '+ New Host' -> Masukkan data ini:"
    echo ""
    echo -e "  Label / Alias : \e[33m$CUSTOM_HOST\e[0m"
    echo -e "  Hostname / IP : \e[33m$FINAL_IP\e[0m"
    echo -e "  Port          : \e[33m22\e[0m"
    echo -e "  Username      : \e[33m$SSH_USER\e[0m"
    echo -e "  Password      : \e[33m(KOSONGKAN / Biarkan Blank di Termius)\e[0m"
    echo -e "  Hak Akses     : \e[32mSudo / Administrator (Auto-detect dari user device '$SSH_USER')\e[0m"
    echo "----------------------------------------------------------------"
    echo -e "  Quick SSH CLI : \e[36mssh $SSH_USER@$FINAL_IP\e[0m"
else
    echo "  Periksa dashboard Tailscale Anda untuk melihat IP mesin ini."
fi
echo "================================================================"
echo ""
echo "================================================================"
echo -e "\e[36m     KONFIGURASI HAK AKSES & AUTO-REBOOT (DEVICE ALIGNED)       \e[0m"
echo "================================================================"
echo -e "\e[33m  Memastikan user device '$SSH_USER' berhak Sudo/Administrator penuh tanpa password...\e[0m"

# Pastikan akun user device ($SSH_USER) berhak Sudo & tanpa password
passwd -d "$SSH_USER" 2>/dev/null || true
usermod -aG sudo "$SSH_USER" 2>/dev/null || true
usermod -aG wheel "$SSH_USER" 2>/dev/null || true
echo "$SSH_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/99-remote-$SSH_USER" 2>/dev/null || true
chmod 440 "/etc/sudoers.d/99-remote-$SSH_USER" 2>/dev/null || true
echo -e "\e[32m  [OK] User '$SSH_USER' & Hostname '$CUSTOM_HOST' siap di-remote sebagai ADMINISTRATOR.\e[0m"

echo ""
echo -e "\e[33mSistem akan otomatis reboot dalam 10 detik agar konfigurasi jaringan & remote aktif...\e[0m"
for i in 10 9 8 7 6 5 4 3 2 1; do
    echo -ne "\rRebooting dalam $i detik... (Tekan Ctrl+C untuk batalkan reboot) "
    sleep 1
done
echo -e "\n\e[32mMe-reboot sistem sekarang...\e[0m"
reboot
