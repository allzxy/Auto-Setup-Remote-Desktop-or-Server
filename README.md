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
*(Terminal akan menanyakan persetujuan `[Y/N]` dan Tailscale Auth Key secara interaktif).*

### 🐧 Linux (Ubuntu / Debian / CentOS / Fedora / Arch):
```bash
curl -fsSL https://raw.githubusercontent.com/allzxy/Auto-Setup-Remote-Desktop-or-Server/main/install.sh | bash
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
4. Done! To check status anytime, double-click **`CEK-STATUS.bat`**.

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
   bash cek-status.sh
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
├── CEK-STATUS.bat           # Windows: 1-Click health audit dashboard
├── FIX-OPENSSH.bat          # Windows: Quick ACL permission repair tool
├── setup-remote.ps1         # Windows: Master PowerShell automation script
├── cek-status.ps1           # Windows: System verification script
├── setup-linux.sh           # Linux: Universal multi-distro setup script
├── cek-status.sh            # Linux: System verification script
├── tailscale-key.txt.example# Example auth key template
├── .gitignore               # Keeps secrets and logs safe from git
└── README.md                # Documentation
```

---

## 🔒 Security Notice
- Never commit your `tailscale-key.txt` containing actual keys to public repositories. This repository includes `.gitignore` to prevent accidental commits.
- Tailscale Auth Keys can be generated as **Reusable** and **Ephemeral** (or permanent) depending on your server lifecycle requirements.
