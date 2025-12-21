# legion-setup

# Legion Pro 7i (Gen 10, 2025) Dual-Boot AI Workstation Playbook

**Windows 11 Home + Ubuntu 24.04.x | Secure Boot ON | Dynamic Graphics | Clean storage | Battery/RAM optimized | RTX for AI**

> This is a **cut-paste-ready**, end-to-end playbook you can follow step by step.
> It includes: **Ventoy (Secure Boot)**, **Windows + WSL + Docker on D:**, **Linux /home dev universe**, **multi-Java + multi-Node + Miniconda**, **Android Studio**, **VS Code**, **Chrome profile/cache placement**, **shared NTFS data lake**, and **root partition growth control**.

---

## 0) Your system model (what we’re building)

### Hardware and constraints

* CPU: Intel Core Ultra 9 (275HX)
* GPU: RTX 5080 16GB (Blackwell)
* RAM: 32GB
* Storage: 2×1TB NVMe Gen4
* Secure Boot: **ON**
* BIOS Graphics Mode: **Dynamic Graphics** (you want this as the default)

### Confirmed wiring constraint (critical)

* **HDMI external display is physically routed to the RTX (dGPU).**

  * You proved this by switching BIOS to UMA and HDMI stopped working.
* Therefore:

  * You **cannot fully power off** the RTX when HDMI is connected.
  * You **can** still keep the RTX **idle/low-power** when not training.

### Storage architecture (authority rules)

**Disk 0 (Windows)**

* `C:` (200GB): Windows OS + core drivers only
* `D:` (550GB): Windows dev authority (WSL + Docker + repos + tools + caches)
* `E:` (100GB): OneDrive authority (personal/college sync)
* `F:` (100GB, NTFS): Shared data lake (datasets/weights/checkpoints/exports only)

**Disk 1 (Linux)**

* EFI (1GB), `/boot` (1GB), swap (32GB), `/` (200GB), `/home` (~720GB)

**Non-negotiable rule**

* **Do not store dev environments or repos on `F:`** (NTFS) in Linux.

  * `F:` is for big, mostly-static data (datasets/weights/checkpoints).
* **All dev environments + repos live on:**

  * Windows: `D:`
  * Linux: `/home`

---

## 1) BIOS baseline (set once, then keep stable)

1. Boot BIOS (F2 / Fn+F2)
2. Ensure:

   * Boot Mode: **UEFI**
   * TPM / Intel PTT: **Enabled**
   * Virtualization (VT-x/VT-d): **Enabled** (WSL2/Docker)
   * Secure Boot: **Enabled**
   * Graphics: **Dynamic Graphics** (keep this as your default)

> Optional note: If you ever want maximum battery while laptop-only, UMA is great — but UMA disables RTX (no CUDA) and HDMI won’t work. Your requested default is Dynamic, so we design around Dynamic.

---

## 2) Build a Secure-Boot Ventoy USB (your installer + rescue stick)

### 2.1 What to put on the Ventoy stick (recommended)

**Required**

* Windows 11 ISO (x64) — repair tools + reinstall option
* Ubuntu 24.04.x Desktop ISO (amd64) — install + rescue environment

**Optional**

* Rescuezilla ISO — only if you want GUI imaging/clone capability

**Also optional**

* `TOOLS\Lenovo\BIOS\` folder for keeping Lenovo BIOS updater files (not required for Ventoy)

### 2.2 Create Ventoy with Secure Boot support (Windows)

1. Download Ventoy (Windows zip), extract it
2. Run `Ventoy2Disk.exe` as Administrator
3. Select your USB drive (**triple-check it’s the USB**)
4. Enable:

   * `Option → Secure Boot Support` ✅
   * (If available) `Option → Partition Style → GPT`
5. Click **Install** (this wipes the USB)

Ventoy will auto-create:

* a small EFI boot partition
* a large data partition for ISOs
  No manual partitioning needed.

### 2.3 Copy ISOs (recommended folder layout)

On the large Ventoy partition:

```
ISO\Windows\Win11.iso
ISO\Linux\Ubuntu_24.04.iso
TOOLS\Lenovo\BIOS\   (optional)
```

### 2.4 First boot with Secure Boot ON (one-time enrollment)

1. Reboot → Boot menu (F12)
2. Choose USB (UEFI)
3. Ventoy will prompt one-time Secure Boot enrollment (key/hash) → complete it
4. Test boot:

   * Ubuntu ISO → reach “Try / Install”
   * Windows ISO → reach Windows Setup

If both work, Ventoy is done.

---

## 3) Windows 11 Home: keep `C:` clean, move everything heavy to `D:`

### 3.1 One-time Windows hygiene

1. Run Windows Update fully
2. Install Lenovo Vantage + Legion Space (keep them)
3. Set display refresh for daily use (battery sanity):

   * Internal: prefer 60/120Hz daily, 240Hz only when needed
   * External HDMI: keep reasonable (avoid max refresh if not needed)

### 3.2 Disable Fast Startup (mandatory for safe NTFS dual-boot)

Fast Startup can leave NTFS in a hibernated state and cause mount issues in Linux.

* Control Panel → Power Options → “Choose what the power buttons do”
* “Change settings that are currently unavailable”
* Disable **Turn on fast startup**

### 3.3 Windows encryption (Device Encryption on Home)

* Settings → Privacy & security → Device encryption
* If available, enable it and ensure your recovery key is safely stored (Microsoft account).

**Important stability rule**

* Keep Secure Boot ON consistently once encryption is enabled.
* Avoid constantly flipping boot settings.

---

## 4) Windows Dev Storage Layout (so nothing piles on C:)

Create these folders:

* `D:\dev\repos\`
* `D:\dev\tools\`
* `D:\dev\envs\`
* `D:\dev\cache\`
* `D:\apps\` (large GUI apps that can be installed/extracted here)
* `D:\profiles\` (browser profiles)

**Policy**

* Git repos → `D:\dev\repos`
* Language toolchains → `D:\dev\tools`
* Environments → `D:\dev\envs`
* Caches → `D:\dev\cache`
* Large apps → `D:\apps`

---

## 5) Windows: WSL2 + Docker (move to D: and cap RAM)

### 5.1 Cap WSL2 RAM (stops “Windows uses 10GB+”)

Create: `C:\Users\<you>\.wslconfig`

```ini
[wsl2]
memory=6GB
processors=6
swap=4GB
```

Apply:

```powershell
wsl --shutdown
```

**Tuning**

* Daily: 4–6GB
* Heavy tasks: 8–10GB temporarily, then reduce again

### 5.2 Move WSL distro storage to D: (export/import)

1. List distros:

```powershell
wsl --list --verbose
```

2. Export distro (example Ubuntu):

```powershell
mkdir D:\WSL\backup
wsl --export Ubuntu D:\WSL\backup\Ubuntu.tar
```

3. Unregister old distro:

```powershell
wsl --unregister Ubuntu
```

4. Import to D:

```powershell
mkdir D:\WSL\Ubuntu
wsl --import Ubuntu D:\WSL\Ubuntu D:\WSL\backup\Ubuntu.tar --version 2
```

5. Set default:

```powershell
wsl --set-default Ubuntu
```

### 5.3 Move Docker Desktop storage to D:

In Docker Desktop:

* Settings → Resources → Advanced
* Set Disk image location to: `D:\DockerDesktop\`
* Apply & restart

---

## 6) Windows Dev Setup (multi-Java, multi-Node, Miniconda, Android Studio, VS Code)

### 6.1 VS Code on Windows: **Portable Mode** (best for C: hygiene)

1. Download VS Code ZIP (not installer)
2. Extract to: `D:\apps\VSCode\`
3. Create: `D:\apps\VSCode\data\`
4. Launch: `D:\apps\VSCode\Code.exe`

Now extensions/settings live inside `D:\apps\VSCode\data\` (not in `%APPDATA%` on C:).

### 6.2 Multi-Java on Windows (version-safe and D:-resident)

**Recommended approach**

* Download **JDK ZIP** distributions (Temurin/Oracle zip builds)
* Extract to:

  * `D:\dev\tools\jdk\jdk-21\`
  * `D:\dev\tools\jdk\jdk-17\`
  * `D:\dev\tools\jdk\jdk-8\` (only if you truly need it)

**Per-shell switching (no permanent PATH mess)**
Create PowerShell scripts:

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

Use:

```powershell
. D:\dev\tools\scripts\java21.ps1
```

### 6.3 Multi-Node on Windows

**Option A (native):** NVM for Windows

* Install NVM for Windows
* Configure node versions stored on `D:\dev\tools\nvm\`
* Configure npm cache:

  * `D:\dev\cache\npm\`

**Option B (cleanest isolation):** Node only in WSL

* Use NVM inside WSL and keep Windows lightweight

### 6.4 Miniconda on Windows: everything on D:

Install Miniconda to:

* `D:\dev\tools\miniconda3\`

Configure env + cache locations:
Open Anaconda Prompt:

```bat
conda config --set auto_activate_base false
conda config --add envs_dirs D:\dev\envs\conda
conda config --add pkgs_dirs D:\dev\cache\conda-pkgs
```

### 6.5 Android Studio on Windows: ZIP install + SDK/Gradle/AVD on D:

**Install Studio**

1. Download Android Studio ZIP
2. Extract to: `D:\apps\AndroidStudio\`
3. Launch: `D:\apps\AndroidStudio\android-studio\bin\studio64.exe`

**During setup wizard**

* Set Android SDK location to:

  * `D:\dev\envs\Android\Sdk`

**Move Gradle cache**
Set Windows User Environment Variable:

* `GRADLE_USER_HOME = D:\dev\cache\gradle`

**Move Emulator AVD images**
Set Windows User Environment Variable:

* `ANDROID_AVD_HOME = D:\dev\envs\Android\.android\avd`

> This prevents silent 20–80GB growth on C: from SDKs, Gradle, and emulators.

---

## 7) Windows Chrome: put profile + cache on D:

### 7.1 Create directories

* `D:\profiles\Chrome\UserData\`
* `D:\profiles\Chrome\Cache\`

### 7.2 Create a dedicated Chrome shortcut (recommended)

Target:

```text
"C:\Program Files\Google\Chrome\Application\chrome.exe" --user-data-dir="D:\profiles\Chrome\UserData" --disk-cache-dir="D:\profiles\Chrome\Cache"
```

This forces:

* profile (extensions/bookmarks/history) → D:
* disk cache → D:

> Don’t try to share the same Chrome profile between Windows and Linux via F:. Keep separate profiles per OS.

---

## 8) Ubuntu 24.04.x install (Disk 1) + keep `/` minimal

### 8.1 Manual partitioning (your agreed layout)

Disk 1:

* EFI 1GB FAT32 → mount `/boot/efi`
* /boot 1GB ext4 → mount `/boot`
* swap 32GB
* `/` 200GB ext4
* `/home` remaining ext4

### 8.2 First boot essentials

```bash
sudo apt update && sudo apt -y upgrade
sudo apt -y install build-essential git curl wget unzip htop nvme-cli
```

### 8.3 NVIDIA driver with Secure Boot ON (MOK flow)

Install driver:

```bash
sudo ubuntu-drivers devices
sudo ubuntu-drivers autoinstall
sudo reboot
```

If prompted, complete MOK enrollment on reboot.

Verify:

```bash
nvidia-smi
```

---

## 9) Linux shared data lake: mount `F:` NTFS at `/mnt/shared`

### 9.1 Create mount point

```bash
sudo mkdir -p /mnt/shared
```

### 9.2 Find UUID

```bash
lsblk -f
```

### 9.3 Add to `/etc/fstab`

```bash
sudo nano /etc/fstab
```

Add (replace UUID):

```fstab
UUID=XXXX-XXXX  /mnt/shared  ntfs3  defaults,uid=1000,gid=1000,umask=022  0  0
```

Apply:

```bash
sudo mount -a
df -h | grep shared
```

### 9.4 Create shared structure (AI assets only)

```bash
mkdir -p /mnt/shared/{datasets,weights,checkpoints,exports,hf,torch}
```

---

## 10) Linux Dev Setup (all in /home): multi-Java, multi-Node, Miniconda, Android Studio, VS Code, Chrome

### 10.1 Canonical dev structure

```bash
mkdir -p ~/dev/{repos,tools,envs,cache,tmp}
mkdir -p ~/profiles
```

Repos:

* `~/dev/repos`

Tools:

* `~/dev/tools`

Envs:

* `~/dev/envs`

Caches:

* `~/dev/cache`

### 10.2 Node.js (multi-version) via NVM

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.bashrc
nvm install --lts
nvm install 20
nvm use --lts
node -v && npm -v
```

Redirect npm cache (optional):

```bash
npm config set cache ~/dev/cache/npm --global
```

### 10.3 Java (multi-version) via SDKMAN

```bash
curl -s "https://get.sdkman.io" | bash
source ~/.bashrc
sdk version
sdk list java
sdk install java 21.0.?.tem
sdk install java 17.0.?.tem
sdk use java 21.0.?.tem
java -version
```

### 10.4 Miniconda in /home (envs/caches controlled)

Install Miniconda to:

* `~/miniconda3`

Then:

```bash
~/miniconda3/bin/conda init
source ~/.bashrc
conda config --set auto_activate_base false
conda config --add envs_dirs ~/dev/envs/conda
conda config --add pkgs_dirs ~/dev/cache/conda-pkgs
```

### 10.5 Android Studio on Linux (keep growth in /home, not `/`)

**Install**

1. Download Android Studio (Linux tar.gz)
2. Extract to:

   * `~/dev/tools/android-studio/` (recommended)

Launch:

```bash
~/dev/tools/android-studio/android-studio/bin/studio.sh
```

**Set SDK location**

* `~/Android/Sdk` (this is on `/home`, good)

**Move Gradle + AVD**
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

### 10.6 VS Code on Linux (safe by default)

Linux VS Code data lives in `/home` already, so it won’t bloat `/`.

Recommended install route:

* Install via official `.deb` or via your preferred package method

### 10.7 Chrome on Linux: install + profile/cache control

**Simple approach (recommended)**

* Install Chrome normally
* Default profile location is under `/home` (safe)

**Optional: relocate profile/cache**
Create:

```bash
mkdir -p ~/profiles/chrome
mkdir -p ~/dev/cache/chrome
```

Launch Chrome with:

```bash
google-chrome --user-data-dir="$HOME/profiles/chrome" --disk-cache-dir="$HOME/dev/cache/chrome"
```

---

## 11) Keep Linux `/` (200GB) from growing beyond ~50–60%

Your `/` must stay OS-only. The biggest offenders:

* systemd journal logs
* APT cache
* stray large logs under `/var/log`
* snap/flatpak caches (if used heavily)

### 11.1 Cap systemd journal size + retention

Edit:

```bash
sudo nano /etc/systemd/journald.conf
```

Recommended:

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

### 11.2 Weekly journald vacuum (systemd timer)

Script:

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
```

Service:

```bash
sudo nano /etc/systemd/system/journal-vacuum.service
```

```ini
[Unit]
Description=Vacuum systemd journal logs

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/journal-vacuum.sh
```

Timer:

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

### 11.3 Monthly APT cache clean (systemd timer)

Service:

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

Timer:

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

### 11.4 Root usage quick check (habit)

Run monthly:

```bash
df -h /
sudo du -xh /var | sort -h | tail -n 30
```

---

## 12) RTX “AI-only” behavior: realistic optimization on this hardware

### Windows: force most apps to iGPU (saves power)

* Settings → System → Display → Graphics

  * Set Chrome, VS Code, etc. → **Power saving (iGPU)**
  * Set training apps (Python, CUDA tools) → **High performance (NVIDIA)**

### Linux: keep RTX idle unless training

Because HDMI needs RTX when connected, the best approach is:

* avoid unnecessary GPU-accelerated heavy apps
* keep refresh rates sane
* run training/inference intentionally (not constantly “open”)

---

## 13) AI data + cache policy (prevents silent bloat)

### 13.1 Put AI assets on shared lake (F: → /mnt/shared)

* datasets → `/mnt/shared/datasets`
* weights → `/mnt/shared/weights`
* checkpoints → `/mnt/shared/checkpoints`
* exports → `/mnt/shared/exports`

### 13.2 Redirect ML caches to `/mnt/shared` (Linux)

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

## 14) Backup + fast recovery strategy (practical)

### 14.1 Cloud baseline

* Code: GitHub (all repos)
* Docs: OneDrive (E:)
* Important exports/results: OneDrive or `/mnt/shared/exports` (selectively sync)

### 14.2 Windows recovery

* Keep Hasleo images occasionally (before major changes)
* Keep Ventoy Windows ISO for repair boot

### 14.3 Linux recovery

Best student-friendly method:

* keep your Linux dev state reproducible:

  * `~/dev/repos` is git
  * `conda env export` for critical envs
  * a small “bootstrap script” repo (`machine-setup`)

**Helpful exports**

```bash
conda env export > ~/dev/repos/<your-setup-repo>/env.yml
pip freeze > ~/dev/repos/<your-setup-repo>/requirements.txt
```

---

## 15) Validation checklist (run these to confirm you’re “done”)

### Windows checks

* `C:` free space stays high (OS only)
* WSL memory does not balloon:

  * Task Manager → Memory stable at idle
* WSL + Docker storage paths are on `D:`
* Chrome profile is on `D:\profiles\...`
* Android SDK/AVD/Gradle caches are on D:

### Linux checks

* `/` usage stays < 60%:

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
* caches redirected:

  ```bash
  echo $HF_HOME
  echo $TORCH_HOME
  ```

---

# Quick execution order (recommended)

1. Build Ventoy (Secure Boot) and test boot Windows + Ubuntu ISO
2. Windows: `.wslconfig` cap → move WSL to D → move Docker to D
3. Windows: install VS Code portable → Miniconda to D → Android Studio ZIP to D → set SDK/Gradle/AVD env vars → Chrome profile to D
4. Ubuntu: install → NVIDIA driver + MOK → mount `/mnt/shared` → set journald + timers
5. Ubuntu: NVM + SDKMAN + Miniconda + Android Studio + Chrome profile strategy → redirect AI caches to `/mnt/shared`
6. Validate disk usage and GPU behavior

---

## If you want, I can also generate a “1-page checklist version”

Same content, but compressed into a punch-list you can follow during setup day without scrolling.
