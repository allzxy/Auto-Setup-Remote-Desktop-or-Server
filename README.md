# 🚀 Auto Setup Remote Desktop or Server (Windows & Linux)

One-click automated setup to turn any **Windows** or **Linux** machine into an always-on, secure remote desktop and server using **OpenSSH**, **Tailscale (Mesh VPN)**, and **RDP**. Accessible from anywhere outside your local network without port-forwarding or public IP.

---

## ✨ Features

- ⚡ **100% Automated**: 1-click execution on Windows, 1-command on Linux.
- 🌐 **No Port Forwarding**: Powered by Tailscale Mesh Network (direct P2P encrypted tunnel).
- 🔑 **Headless Auto-Join**: Joins your Tailscale mesh network silently via Auth Key without opening a browser.
- 🔄 **Auto-Recovery & SCM**: Auto-starts on boot (before user login) and auto-restarts on failure.
- ⚡ **Anti-Sleep 24/7**: Automatically disables system standby, sleep, and hibernate.
- 🛡️ **Zero-Friction Firewall**: Automatically allows OpenSSH (port 22) and RDP (port 3389).
- 📊 **Built-in Health Audit**: Visual verification checklist for both Windows & Linux.

---

## ⚡ Instant 1-Line Terminal Install (Recommended)

Tidak perlu download file atau git clone manual! Cukup copy-paste command ini ke terminal server target:

### 🪟 Windows (PowerShell Administrator):
```powershell
irm https://raw.githubusercontent.com/allzxy/Auto-Setup-Remote-Desktop-or-Server/main/install.ps1 | iex
```
*(Otomatis mendeteksi Hostname & Username device target, support login Termius & RDP tanpa password, dan akses remote penuh sebagai Administrator).*

### 🐧 Linux (Ubuntu / Debian / CentOS / Fedora / Arch):
```bash
curl -fsSL https://raw.githubusercontent.com/allzxy/Auto-Setup-Remote-Desktop-or-Server/main/install.sh | bash
```
*(Otomatis mendeteksi Hostname & Username device target, support login Termius tanpa password via PAM nullok, dan akses remote penuh Sudo).*

---

## 📊 Instant 1-Line Status Check (Audit Server)

Mau cek apakah server aktif, IP Tailscale, port 22/3389 terbuka, atau butuh data kartu login Termius tanpa download repo? Cukup jalankan:

### 🪟 Windows (PowerShell):
```powershell
irm https://raw.githubusercontent.com/allzxy/Auto-Setup-Remote-Desktop-or-Server/main/Status/status.ps1 | iex
```

### 🐧 Linux:
```bash
curl -fsSL https://raw.githubusercontent.com/allzxy/Auto-Setup-Remote-Desktop-or-Server/main/Status/status.sh | bash
```

---

## 🖥️ Manual Offline Start: Windows Server

Supports Windows 10, Windows 11, and Windows Server 2016/2019/2022/2025.

1. Clone or download this repository:
   ```cmd
   git clone https://github.com/allzxy/Auto-Setup-Remote-Desktop-or-Server.git
   cd Auto-Setup-Remote-Desktop-or-Server
   ```
2. Copy `tailscale-key.txt.example` to `tailscale-key.txt` and paste your [Tailscale Auth Key](https://login.tailscale.com/admin/settings/keys):
   ```cmd
   copy tailscale-key.txt.example tailscale-key.txt
   ```
3. Double-click **`1-KLIK-START.bat`** and click **Yes** on the UAC prompt.
4. Done! To check status anytime, double-click **`Status/1-KLIK-STATUS.bat`** (atau **`Status/CEK-STATUS.bat`**).

---

## 🐧 Manual Offline Start: Linux Server

Supports Ubuntu, Debian, CentOS, RHEL, Rocky Linux, AlmaLinux, Fedora, Arch, and openSUSE.

1. Clone or download this repository:
   ```bash
   git clone https://github.com/allzxy/Auto-Setup-Remote-Desktop-or-Server.git
   cd Auto-Setup-Remote-Desktop-or-Server
   ```
2. Copy `tailscale-key.txt.example` to `tailscale-key.txt` and insert your Tailscale Auth Key:
   ```bash
   cp tailscale-key.txt.example tailscale-key.txt
   nano tailscale-key.txt
   ```
3. Run the installer:
   ```bash
   sudo bash setup-linux.sh
   ```
4. Done! To verify health anytime:
   ```bash
   bash Status/status.sh
   ```

---

## 📱 How to Remote Connect from Anywhere

Once the server is set up, connect from any laptop, PC, or phone connected to the same Tailscale account:

### 1. Terminal (SSH)
```bash
ssh username@<TAILSCALE_IP>
```

### 2. Remote Desktop (RDP - Windows Only)
Open Remote Desktop Connection (`mstsc`) and connect to:
```text
<TAILSCALE_IP>
```

---

## 📁 Repository Structure

```text
├── 1-KLIK-START.bat         # Windows: 1-Click launcher with auto-elevation
├── 1-KLIK-START.vbs         # Windows: Background silent launcher
├── FIX-OPENSSH.bat          # Windows: Quick ACL permission repair tool
├── setup-remote.ps1         # Windows: Master PowerShell automation script
├── setup-linux.sh           # Linux: Universal multi-distro setup script
├── install.ps1              # Windows: 1-Line Web Terminal Installer
├── install.sh               # Linux: 1-Line Web Terminal Installer
├── tailscale-key.txt.example# Example auth key template
├── .gitignore               # Keeps secrets and logs safe from git
├── README.md                # Documentation
├── Status/                  # Dedicated Status & Health Audit Suite
│   ├── 1-KLIK-STATUS.bat    # Windows: 1-Click status check launcher
│   ├── CEK-STATUS.bat       # Windows: Alternative status check launcher
│   ├── status.ps1           # Windows: Master status audit & Termius card script
│   └── status.sh            # Linux: Master status audit & Termius card script
└── Uninstall/               # Folder Clean Uninstaller
    ├── 1-KLIK-UNINSTALL.bat # Windows: 1-Click uninstaller
    ├── uninstall.ps1        # Windows: Master uninstaller script
    └── uninstall.sh         # Linux: Master uninstaller script
```

---

## 🗑️ Clean Uninstaller (Windows & Linux)

Ingin menghapus seluruh konfigurasi remote server dan mengembalikan sistem ke kondisi awal? Cukup copy-paste 1-line command uninstaller ini:

### 🪟 Windows (PowerShell Administrator):
```powershell
irm https://raw.githubusercontent.com/allzxy/Auto-Setup-Remote-Desktop-or-Server/main/Uninstall/uninstall.ps1 | iex
```
*(Atau double-click file `Uninstall/1-KLIK-UNINSTALL.bat`).*

### 🐧 Linux (Ubuntu / Debian / CentOS / Fedora / Arch):
```bash
curl -fsSL https://raw.githubusercontent.com/allzxy/Auto-Setup-Remote-Desktop-or-Server/main/Uninstall/uninstall.sh | bash
```

---

## 🔒 Security Notice
- Never commit your `tailscale-key.txt` containing actual keys to public repositories. This repository includes `.gitignore` to prevent accidental commits.
- Tailscale Auth Keys can be generated as **Reusable** and **Ephemeral** (or permanent) depending on your server lifecycle requirements.
