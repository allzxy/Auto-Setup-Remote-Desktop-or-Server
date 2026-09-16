#!/usr/bin/env bash
# ==============================================================================
# Auto Setup Remote Desktop or Server - Clean Uninstaller (Linux)
# Run via terminal:
# curl -fsSL https://raw.githubusercontent.com/allzxy/Auto-Setup-Remote-Desktop-or-Server/main/Uninstall/uninstall.sh | bash
# ==============================================================================

set -e

# Pastikan berjalan sebagai root
if [ "$EUID" -ne 0 ]; then
    echo "[!] Meminta izin root (sudo)..."
    exec sudo bash "$0" "$@"
fi

clear
echo ""
echo "================================================================"
echo -e "\e[31m       UNINSTALLER: AUTO SETUP REMOTE DESKTOP OR SERVER (LINUX) \e[0m"
echo "================================================================"
echo ""
echo "  Tindakan pembersihan yang akan dilakukan:"
echo "   1. Logout & Hapus aplikasi Tailscale beserta service & datanya"
echo "   2. Hentikan & Nonaktifkan OpenSSH Server"
echo "   3. Tutup aturan Firewall Port 22"
echo "   4. Kembalikan pengaturan Sleep & Suspend sistem"
echo ""

# 1. Konfirmasi User (Gunakan /dev/tty agar kompatibel dengan curl | bash)
read -p "Apakah Anda YAKIN ingin MENGHAPUS SEMUA komponen remote server? (y/N): " confirm < /dev/tty
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "\n\e[33m[x] Proses uninstall dibatalkan oleh pengguna.\e[0m\n"
    exit 0
fi

echo ""
echo "----------------------------------------------------------------"
echo "                 MEMULAI PROSES PEMBERSIHAN                     "
echo "----------------------------------------------------------------"

# 1. Tailscale
echo -e "\n\e[36m>>> [1/4] Membersihkan Tailscale...\e[0m"
if command -v tailscale >/dev/null 2>&1; then
    tailscale logout 2>/dev/null || true
    tailscale down 2>/dev/null || true
fi

systemctl stop tailscaled 2>/dev/null || true
systemctl disable tailscaled 2>/dev/null || true

if command -v apt-get >/dev/null 2>&1; then
    apt-get purge -y tailscale 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/tailscale.list
    rm -f /usr/share/keyrings/tailscale-archive-keyring.gpg
elif command -v dnf >/dev/null 2>&1; then
    dnf remove -y tailscale 2>/dev/null || true
elif command -v yum >/dev/null 2>&1; then
    yum remove -y tailscale 2>/dev/null || true
elif command -v pacman >/dev/null 2>&1; then
    pacman -Rns --noconfirm tailscale 2>/dev/null || true
fi

rm -rf /var/lib/tailscale /etc/tailscale
echo -e "\e[32m  [OK] Tailscale berhasil dihapus sepenuhnya.\e[0m"

# 2. OpenSSH Server
echo -e "\n\e[36m>>> [2/4] Menangani OpenSSH Server...\e[0m"
systemctl stop ssh 2>/dev/null || systemctl stop sshd 2>/dev/null || true
systemctl disable ssh 2>/dev/null || systemctl disable sshd 2>/dev/null || true
echo -e "\e[32m  [OK] OpenSSH Server dinonaktifkan.\e[0m"

# 3. Firewall
echo -e "\n\e[36m>>> [3/4] Menutup Port 22 di Firewall...\e[0m"
if command -v ufw >/dev/null 2>&1; then
    ufw delete allow 22/tcp 2>/dev/null || true
elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --remove-service=ssh 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
fi
echo -e "\e[32m  [OK] Aturan Firewall Port 22 dibersihkan.\e[0m"

# 4. Anti-Sleep (Restore normal sleep)
echo -e "\n\e[36m>>> [4/4] Mengaktifkan Kembali Fitur Sleep/Suspend...\e[0m"
systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true
echo -e "\e[32m  [OK] Sleep & Suspend dikembalikan ke fungsi normal.\e[0m"

echo ""
echo "================================================================"
echo -e "\e[32m              UNINSTALL SELESAI & SISTEM BERSIH                 \e[0m"
echo "================================================================"
echo -e "  \e[32m[ OK ]\e[0m Tailscale Application       : Terhapus Bersih"
echo -e "  \e[32m[ OK ]\e[0m Tailscale Mesh Network       : Terputus & Dihapus"
echo -e "  \e[32m[ OK ]\e[0m OpenSSH Server Service      : Dinonaktifkan"
echo -e "  \e[32m[ OK ]\e[0m Firewall Rule Port 22       : Ditutup & Dihapus"
echo -e "  \e[32m[ OK ]\e[0m Power Management (Sleep)    : Kembali Normal"
echo "----------------------------------------------------------------"
echo "  Status Sistem: Komputer Anda telah kembali ke kondisi awal."
echo "================================================================"
echo ""
echo -e "\e[90mJendela tidak akan ditutup otomatis agar Anda bisa melihat log di atas.\e[0m"
read -p "Tekan tombol ENTER untuk keluar..." _ < /dev/tty || true
