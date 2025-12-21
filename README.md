# legion-setup

# Legion Pro 7i (Gen 10, 2025) Dual-Boot AI Workstation Playbook
**Windows 11 Home + Ubuntu 24.04.x | Secure Boot ON | Dynamic Graphics | Clean storage | Battery/RAM optimized | RTX for AI**

> This is a **cut-paste-ready**, end-to-end playbook you can follow step by step.
> It includes: **Ventoy (Secure Boot)**, **Windows + WSL + Docker on D:**, **Ubuntu with HWE kernel**, **Linux /home dev universe**, **multi-Java + multi-Node + Miniconda**, **Android Studio**, **VS Code**, **Chrome profile/cache placement + launchers**, **shared NTFS data lake**, **Snap removal/disable**, **battery optimization**, and **root partition growth control**.

---

## 0) Your system model (what we’re building)

### Hardware and constraints
- CPU: Intel Core Ultra 9 (275HX)
- GPU: RTX 5080 16GB (Blackwell)
- RAM: 32GB
- Storage: 2×1TB NVMe Gen4
- Secure Boot: **ON**
- BIOS Graphics Mode: **Dynamic Graphics** (default)

### Confirmed wiring constraint (critical)
- **HDMI external display is physically routed to the RTX (dGPU).**
  - Proven: UMA mode breaks HDMI output in Windows.
- Therefore:
  - You **cannot fully power off** RTX when HDMI is connected.
  - You **can** keep RTX **idle/low-power** when not training.

### Storage architecture (authority rules)

**Disk 0 (Windows)**
- `C:` (200GB): Windows OS + core drivers only
- `D:` (550GB): Windows dev authority (**WSL + Docker + repos + tools + caches**)
- `E:` (100GB): OneDrive authority (personal/college sync)
- `F:` (100GB, NTFS): Shared data lake (**datasets/weights/checkpoints/exports only**)

**Disk 1 (Linux)**
- EFI (1GB), `/boot` (1GB), swap (32GB), `/` (200GB), `/home` (~720GB)

**Non-negotiable rule**
- **Do not store dev environments or repos on `F:`** in Linux.
  - `F:` is for big, mostly-static data (datasets/weights/checkpoints).
- Dev lives on:
  - Windows: `D:`
  - Linux: `/home`

---

## 1) BIOS baseline (set once, then keep stable)

1. Boot BIOS (F2 / Fn+F2)
2. Ensure:
   - Boot Mode: **UEFI**
   - TPM / Intel PTT: **Enabled**
   - Virtualization (VT-x/VT-d): **Enabled** (WSL2/Docker)
   - Secure Boot: **Enabled**
   - Graphics: **Dynamic Graphics** (default)

> UMA gives best battery but disables CUDA and HDMI. Your default is Dynamic; we design around it.

---

## 2) Build a Secure-Boot Ventoy USB (installer + rescue stick)

### 2.1 What to put on the Ventoy stick
**Required**
- Windows 11 ISO (x64)
- Ubuntu 24.04.x Desktop ISO (amd64)

**Optional**
- Rescuezilla ISO (only if you want GUI disk imaging)
- `TOOLS\Lenovo\BIOS\` folder (optional)

### 2.2 Create Ventoy with Secure Boot support (Windows)
1. Download Ventoy (Windows zip), extract
2. Run `Ventoy2Disk.exe` as Administrator
3. Select USB drive (triple-check)
4. Enable:
   - `Option → Secure Boot Support` ✅
   - `Option → Partition Style → GPT` (if available)
5. Install (wipes USB)

### 2.3 Copy ISOs
```

ISO\Windows\Win11.iso
ISO\Linux\Ubuntu_24.04.iso
TOOLS\Lenovo\BIOS\   (optional)

````

### 2.4 First boot (Secure Boot ON)
- Boot menu (F12) → USB (UEFI)
- Enroll Ventoy key once
- Test boot both ISOs

---

## 3) Windows 11 Home: keep `C:` clean, move heavy to `D:`

### 3.1 One-time Windows hygiene
- Windows Update fully
- Install Lenovo Vantage + Legion Space
- Daily refresh rate sanity:
  - Internal: 60/120Hz daily, 240Hz when needed
  - External HDMI: avoid max refresh unless required

### 3.2 Disable Fast Startup (important for NTFS dual-boot)
- Control Panel → Power Options → “Choose what the power buttons do”
- Disable **Turn on fast startup**

### 3.3 Windows encryption (Device Encryption)
- Settings → Privacy & security → Device encryption (if available)
- Keep Secure Boot ON after enabling

---

## 4) Windows Dev Storage Layout (so nothing piles on C:)
Create:
- `D:\dev\repos\`
- `D:\dev\tools\`
- `D:\dev\envs\`
- `D:\dev\cache\`
- `D:\apps\`
- `D:\profiles\`

---

## 5) Windows: WSL2 + Docker (move to D: and cap RAM)

### 5.1 Cap WSL2 RAM
Create: `C:\Users\<you>\.wslconfig`
```ini
[wsl2]
memory=6GB
processors=6
swap=4GB
````

Apply:

```powershell
wsl --shutdown
```

### 5.2 Move WSL distro to D:

```powershell
wsl --list --verbose

mkdir D:\WSL\backup
wsl --export Ubuntu D:\WSL\backup\Ubuntu.tar

wsl --unregister Ubuntu

mkdir D:\WSL\Ubuntu
wsl --import Ubuntu D:\WSL\Ubuntu D:\WSL\backup\Ubuntu.tar --version 2

wsl --set-default Ubuntu
```

### 5.3 Move Docker Desktop storage to D:

Docker Desktop → Settings → Resources → Advanced → Disk image location: `D:\DockerDesktop\` → Apply & Restart

---

## 6) Windows Dev Setup (multi-Java, multi-Node, Miniconda, Android Studio, VS Code)

### 6.1 VS Code on Windows (Portable Mode)

* Extract VS Code ZIP to: `D:\apps\VSCode\`
* Create: `D:\apps\VSCode\data\`
* Run: `D:\apps\VSCode\Code.exe`

**Pin shortcut**

* Right-click `Code.exe` → Create shortcut → Pin to taskbar/Start

### 6.2 Multi-Java on Windows (JDK zips on D:)

* `D:\dev\tools\jdk\jdk-21\`
* `D:\dev\tools\jdk\jdk-17\`

Switcher scripts:

`D:\dev\tools\scripts\java21.ps1`

```powershell
$env:JAVA_HOME="D:\dev\tools\jdk\jdk-21"
$env:Path="$env:JAVA_HOME\bin;$env:Path"
java -version
```

`D:\dev\tools\scripts\java17.ps1`

```powershell
$env:JAVA_HOME="D:\dev\tools\jdk\jdk-17"
$env:Path="$env:JAVA_HOME\bin;$env:Path"
java -version
```

### 6.3 Multi-Node on Windows

* NVM for Windows storing versions in `D:\dev\tools\nvm\`
* npm cache: `D:\dev\cache\npm\`
  (or do Node only in WSL)

### 6.4 Miniconda on Windows (everything on D:)

Install to: `D:\dev\tools\miniconda3\`

```bat
conda config --set auto_activate_base false
conda config --add envs_dirs D:\dev\envs\conda
conda config --add pkgs_dirs D:\dev\cache\conda-pkgs
```

### 6.5 Android Studio on Windows (ZIP + SDK/Gradle/AVD on D:)

* Studio: `D:\apps\AndroidStudio\`
* SDK: `D:\dev\envs\Android\Sdk`

Env vars:

* `GRADLE_USER_HOME = D:\dev\cache\gradle`
* `ANDROID_AVD_HOME = D:\dev\envs\Android\.android\avd`

---

## 7) Windows Chrome: put profile + cache on D:

Create:

* `D:\profiles\Chrome\UserData\`
* `D:\profiles\Chrome\Cache\`

Shortcut target:

```text
"C:\Program Files\Google\Chrome\Application\chrome.exe" --user-data-dir="D:\profiles\Chrome\UserData" --disk-cache-dir="D:\profiles\Chrome\Cache"
```

---

## 8) Ubuntu 24.04.x install (Disk 1) + HWE kernel (mandatory for 2025 hardware)

### 8.1 Manual partitioning

Disk 1:

* EFI 1GB FAT32 → `/boot/efi`
* /boot 1GB ext4 → `/boot`
* swap 32GB
* `/` 200GB ext4
* `/home` remaining ext4

### 8.2 First boot essentials

```bash
sudo apt update && sudo apt -y upgrade
sudo apt -y install build-essential git curl wget unzip htop nvme-cli
```

### 8.3 Upgrade to HWE kernel (required)

Install HWE stack (Ubuntu 24.04):

```bash
sudo apt -y install linux-generic-hwe-24.04
sudo reboot
```

Verify kernel (should be newer than base GA; typically 6.11+ on 24.04.3+):

```bash
uname -r
```

### 8.4 NVIDIA driver with Secure Boot ON (MOK)

```bash
sudo ubuntu-drivers devices
sudo ubuntu-drivers autoinstall
sudo reboot
```

Verify:

```bash
nvidia-smi
```

---

## 9) Linux shared data lake: mount `F:` NTFS at `/mnt/shared`

```bash
sudo mkdir -p /mnt/shared
lsblk -f
sudo nano /etc/fstab
```

Add:

```fstab
UUID=XXXX-XXXX  /mnt/shared  ntfs3  defaults,uid=1000,gid=1000,umask=022  0  0
```

Apply:

```bash
sudo mount -a
df -h | grep shared
mkdir -p /mnt/shared/{datasets,weights,checkpoints,exports,hf,torch}
```

---

## 10) Linux Dev Setup (all in /home): multi-Java, multi-Node, Miniconda, Android Studio, VS Code, Chrome

### 10.1 Canonical dev structure

```bash
mkdir -p ~/dev/{repos,tools,envs,cache,tmp}
mkdir -p ~/profiles
```

### 10.2 Node (NVM)

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.bashrc
nvm install --lts
nvm install 20
nvm use --lts
node -v && npm -v
npm config set cache ~/dev/cache/npm --global
```

### 10.3 Java (SDKMAN)

```bash
curl -s "https://get.sdkman.io" | bash
source ~/.bashrc
sdk list java
sdk install java 21.0.?.tem
sdk install java 17.0.?.tem
sdk use java 21.0.?.tem
java -version
```

### 10.4 Miniconda (envs + pkgs on /home)

```bash
# install Miniconda to ~/miniconda3, then:
~/miniconda3/bin/conda init
source ~/.bashrc
conda config --set auto_activate_base false
conda config --add envs_dirs ~/dev/envs/conda
conda config --add pkgs_dirs ~/dev/cache/conda-pkgs
```

### 10.5 Android Studio (Linux)

Extract to: `~/dev/tools/android-studio/` and run:

```bash
~/dev/tools/android-studio/android-studio/bin/studio.sh
```

Add to `~/.bashrc`:

```bash
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export GRADLE_USER_HOME="$HOME/dev/cache/gradle"
export ANDROID_AVD_HOME="$HOME/dev/envs/android/avd"
```

Apply:

```bash
source ~/.bashrc
mkdir -p "$GRADLE_USER_HOME" "$ANDROID_AVD_HOME"
```

### 10.6 VS Code on Ubuntu: optional “Dev Data” launcher

```bash
mkdir -p ~/dev/tools/vscode-data/user-data
mkdir -p ~/dev/tools/vscode-data/extensions
mkdir -p ~/.local/share/applications
cp /usr/share/applications/code.desktop ~/.local/share/applications/code-dev.desktop
nano ~/.local/share/applications/code-dev.desktop
```

Use:

```ini
Name=Visual Studio Code (Dev Data)
Exec=/usr/bin/code --user-data-dir=%h/dev/tools/vscode-data/user-data --extensions-dir=%h/dev/tools/vscode-data/extensions %F
```

### 10.7 Chrome on Ubuntu: custom launcher with profile/cache in `/home`

```bash
mkdir -p ~/profiles/chrome
mkdir -p ~/dev/cache/chrome
mkdir -p ~/.local/share/applications
cp /usr/share/applications/google-chrome.desktop ~/.local/share/applications/google-chrome-custom.desktop
nano ~/.local/share/applications/google-chrome-custom.desktop
```

Use:

```ini
Name=Google Chrome (Custom Profile)
Exec=/usr/bin/google-chrome-stable --user-data-dir=%h/profiles/chrome --disk-cache-dir=%h/dev/cache/chrome %U
```

---

## 11) Disable Snap on Ubuntu (remove + block reinstall)

> Removing Snap may remove Snap-managed apps. Reinstall alternatives via APT as needed.

### 11.1 Remove snap packages (best-effort)

```bash
snap list || true

sudo snap remove --purge firefox || true
sudo snap remove --purge snap-store || true
sudo snap remove --purge gnome-3-38-2004 || true
sudo snap remove --purge gtk-common-themes || true
sudo snap remove --purge bare || true
sudo snap remove --purge core20 || true
sudo snap remove --purge core22 || true
sudo snap remove --purge snapd || true
```

### 11.2 Purge snapd + clean directories

```bash
sudo apt -y purge snapd
sudo apt -y autoremove --purge

rm -rf ~/snap
sudo rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd
```

### 11.3 Block snapd from reinstall

```bash
sudo nano /etc/apt/preferences.d/nosnap.pref
```

Paste:

```text
Package: snapd
Pin: release a=*
Pin-Priority: -10
```

### 11.4 Install replacements (optional)

```bash
sudo apt update
sudo apt -y install firefox || true
```

---

## 12) Battery optimization on Linux (Dynamic Graphics reality)

### 12.1 Key reality check

* If HDMI is in use, RTX must stay enabled for display routing.
* Goal becomes: **minimize RTX usage + keep it idle**, not “off”.

### 12.2 Install power + battery tools

```bash
sudo apt -y install tlp tlp-rdw powertop
sudo systemctl enable --now tlp
```

Optional calibration/inspection:

```bash
sudo powertop --auto-tune
```

### 12.3 Prefer iGPU for desktop rendering (hybrid behavior)

* On Dynamic Graphics laptops, Ubuntu + NVIDIA drivers generally run hybrid by default.
* Practical discipline:

  * don’t force GPU acceleration for everything
  * keep refresh rates sane
  * launch heavy AI only when needed

### 12.4 Use power profiles

Ubuntu supports power profiles:

```bash
powerprofilesctl get
powerprofilesctl set power-saver
# when training:
powerprofilesctl set performance
```

### 12.5 Optional: limit background GPU wakeups

* Avoid always-on GPU apps (electron apps with GPU acceleration, etc.)
* Don’t keep training notebooks running when not training
* Consider disabling “continue running background apps” for Chrome if you notice GPU wakeups

---

## 13) Keep Linux `/` (200GB) from growing beyond ~50–60%

### 13.1 Cap systemd journal size + retention

```bash
sudo nano /etc/systemd/journald.conf
```

Use:

```ini
[Journal]
Storage=persistent
SystemMaxUse=500M
SystemMaxFileSize=50M
SystemKeepFree=2G
MaxRetentionSec=6month
```

Apply:

```bash
sudo systemctl restart systemd-journald
journalctl --disk-usage
```

### 13.2 Weekly journald vacuum (systemd timer)

```bash
sudo nano /usr/local/sbin/journal-vacuum.sh
```

```bash
#!/usr/bin/env bash
set -euo pipefail
/usr/bin/journalctl --vacuum-time=6months
/usr/bin/journalctl --vacuum-size=500M
```

```bash
sudo chmod +x /usr/local/sbin/journal-vacuum.sh
sudo nano /etc/systemd/system/journal-vacuum.service
```

```ini
[Unit]
Description=Vacuum systemd journal logs

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/journal-vacuum.sh
```

```bash
sudo nano /etc/systemd/system/journal-vacuum.timer
```

```ini
[Unit]
Description=Run journal vacuum weekly

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
```

Enable:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now journal-vacuum.timer
```

### 13.3 Monthly APT cache clean (systemd timer)

```bash
sudo nano /etc/systemd/system/apt-clean.service
```

```ini
[Unit]
Description=Clean apt cache

[Service]
Type=oneshot
ExecStart=/usr/bin/apt-get clean
```

```bash
sudo nano /etc/systemd/system/apt-clean.timer
```

```ini
[Unit]
Description=Run apt clean monthly

[Timer]
OnCalendar=monthly
Persistent=true

[Install]
WantedBy=timers.target
```

Enable:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now apt-clean.timer
```

---

## 14) AI data + cache policy (prevents silent bloat)

### 14.1 Put AI assets on shared lake (F: → /mnt/shared)

* datasets → `/mnt/shared/datasets`
* weights → `/mnt/shared/weights`
* checkpoints → `/mnt/shared/checkpoints`
* exports → `/mnt/shared/exports`

### 14.2 Redirect ML caches to `/mnt/shared` (Linux)

Add to `~/.bashrc`:

```bash
export HF_HOME=/mnt/shared/hf
export TRANSFORMERS_CACHE=/mnt/shared/hf/transformers
export HF_DATASETS_CACHE=/mnt/shared/hf/datasets
export TORCH_HOME=/mnt/shared/torch
```

Apply:

```bash
source ~/.bashrc
```

---

## 15) Backup + fast recovery strategy (practical)

### 15.1 Cloud baseline

* Code: GitHub (repos)
* Docs: OneDrive (E:)
* Important exports: OneDrive or `/mnt/shared/exports`

### 15.2 Windows recovery

* Hasleo images before major changes
* Ventoy Windows ISO for repair boot

### 15.3 Linux recovery

Keep setup reproducible:

```bash
conda env export > ~/dev/repos/<your-setup-repo>/env.yml
pip freeze > ~/dev/repos/<your-setup-repo>/requirements.txt
```

---

## 16) Validation checklist

### Windows

* `C:` stays mostly empty (OS only)
* WSL RAM stable at idle
* WSL + Docker on `D:`
* Chrome profile/cache on `D:`
* Android SDK/AVD/Gradle on `D:`
* VS Code portable data in `D:\apps\VSCode\data\`

### Linux

* Kernel is HWE:

  ```bash
  uname -r
  ```
* `/` stays < 60%:

  ```bash
  df -h /
  ```
* shared mounted:

  ```bash
  df -h | grep shared
  ```
* NVIDIA works when needed:

  ```bash
  nvidia-smi
  ```
* Snap is gone:

  ```bash
  snap --version || echo "snap removed"
  ```
* Power profile works:

  ```bash
  powerprofilesctl get
  ```

---

# Quick execution order (recommended)

1. Build Ventoy (Secure Boot) → test boot Windows + Ubuntu ISO
2. Windows: `.wslconfig` cap → move WSL to D → move Docker to D
3. Windows: VS Code portable → Miniconda to D → Android Studio ZIP to D → set SDK/Gradle/AVD env vars → Chrome profile to D
4. Ubuntu: install → upgrade to HWE kernel → NVIDIA driver + MOK → mount `/mnt/shared`
5. Ubuntu: (optional) remove/disable Snap → NVM + SDKMAN + Miniconda + Android Studio + VS Code launcher + Chrome launcher → redirect AI caches to `/mnt/shared`
6. Battery tuning (TLP + powerprofiles) → journald + timers → validate

---


