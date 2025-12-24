# legion-setup

# Legion Pro 7i (Gen 10, 2025) Dual-Boot AI Workstation Playbook **Windows 11 Home + Ubuntu 24.04.x | Secure Boot ON | Dynamic Graphics | Clean storage | Battery/RAM optimized | RTX for AI**

> Includes: **Ventoy (Secure Boot)**, **Windows + WSL + Docker on D:**, **Linux /home dev universe**, **multi-Java + multi-Node + Miniconda**, **Android Studio**, **VS Code**, **Chrome profile/cache placement + iGPU targeting**, **shared NTFS data lake**, **root partition growth control**, **HWE kernel + GA fallback kernel + GRUB menu**, **snap removal (clean) + DEB restore**, and **Legion control stack (fans/power/keyboard)**.

---

## 0A) Repo automation scripts (setup-aryan) — staging + recovery (Windows/Linux kept separate)

This repo now includes **OS-specific setup frameworks** you can stage onto the system so you can re-run fixes anytime (even after breakage).

### Windows (KISS, CMD/BAT-only) — preferred workflow (added)

> **Correction note (Windows):** The PowerShell `setup-aryan` framework is now **legacy on Windows** and has been moved under:
>
> - `windows-setup-legacy\` _(PowerShell-only, historical reference, do not use for Windows going forward)_
>
> For Windows, use **manual installs + tiny batch helpers** only:
>
> - **No PowerShell automation**
> - **No `-Force`**
> - **No state management**
> - **No profile editing**
>
> The PowerShell content below is preserved for history/troubleshooting notes, but **do not follow it for Windows going forward**.

#### Where to install the batch helpers (updated)

1. From this repo, take the Windows batch helpers from your repo folder (example layout):

   - `windows-bat\bin\`

   _(If you renamed the folder, the key rule is: copy the `.bat` files into `C:\setup-aryan\bin\` as shown below.)_

2. Copy them into your machine at:

   - `C:\setup-aryan\bin\`

Your final on-disk layout should look like:

```text
C:\setup-aryan\bin\devdirs-create.bat
C:\setup-aryan\bin\devdirs-validate.bat
C:\setup-aryan\bin\environment-variables-validate.bat
C:\setup-aryan\bin\validate-windows-dev.bat

C:\setup-aryan\bin\new-python-project.bat
C:\setup-aryan\bin\new-node-project.bat
C:\setup-aryan\bin\new-java-project.bat
```

3. Add to **User PATH**:

- `C:\setup-aryan\bin`

Open a new **Command Prompt** and verify:

```bat
where devdirs-create
where devdirs-validate
where environment-variables-validate
where validate-windows-dev

where new-python-project
where new-node-project
where new-java-project
```

#### One-time Windows setup sequence (updated)

**Step 1 — create the standard `D:\dev\...` layout (safe if already exists):**

```bat
devdirs-create
```

**Step 2 — set environment variables (Windows GUI, one-time):**

Open:

- Start → search **Environment Variables** → “Edit the system environment variables” → “Environment Variables…”

Set these **User variables** (recommended, keep caches off C:):

**Java caches (D: only)**

- `GRADLE_USER_HOME = D:\dev\cache\gradle`
- `IVY_USER_DIR      = D:\dev\cache\ivy`

**Node caches (D: only)**

- `NPM_CONFIG_CACHE  = D:\dev\cache\npm`
- `PNPM_HOME         = D:\dev\tools\pnpm` _(and add `%PNPM_HOME%` to PATH if you use pnpm via corepack/npm)_
- _(Optional)_ set pnpm store to D via pnpm config later

**Python caches (D: only)**

- `UV_CACHE_DIR      = D:\dev\cache\uv`
- `PIP_CACHE_DIR     = D:\dev\cache\pip`

**Optional (recommended): TEMP/TMP to D**

- `TEMP = D:\dev\tmp`
- `TMP  = D:\dev\tmp`

Close terminals and open a new CMD after setting these.

**Step 3 — validate folders + env vars + tool presence (repeatable):**

Option A (quick folder-only check):

```bat
devdirs-validate
```

Option B (environment variables + binaries + caches check):

```bat
environment-variables-validate
```

Option C (one-shot full Windows dev audit: dirs + tool presence + versions):

```bat
validate-windows-dev
```

**Step 4 — create project scaffolds (repeatable):**

Python:

```bat
new-python-project --name MyApp
new-python-project --name MyApp --ai
new-python-project --name MyApp --ai --tf
```

Node (minimal; no template suggestions inside the generator):

```bat
new-node-project --name MyNodeApp
new-node-project --name MyNodeApp --ai
new-node-project --name MyNodeApp --tf
```

Java (plain JDK scaffold; no Maven/Gradle enforced):

```bat
new-java-project --name MyJavaApp
new-java-project --name MyJavaApp --ai
new-java-project --name MyJavaApp --tf
```

Flags:

- `--ai` adds AI/ML-friendly notes/deps where it makes sense (Python adds common DS deps).
- `--tf` is a dedicated TensorFlow flag:

  - Python: adds TensorFlow deps + a TF validation helper and TF warmup notes.
  - Node/Java: **does not** install TensorFlow; it adds **README guidance** recommending better alternatives (Python service / ONNX / DJL), plus iGPU-first UI notes.

### Repo layout (updated)

- `linux-setup/`

  - `stage-aryan-setup.sh` → stages Linux commands into: `/usr/local/aryan-setup/`
  - `bin/` → wrapper commands (`setup-aryan`, `setup-aryan-log`)
  - `actions/` → runnable actions (ex: `recover-linux-gui-igpu-deb`, `validate-linux-gpu`)
  - `completions/` → bash completion for `setup-aryan`

- `windows-setup-legacy/` _(legacy PowerShell history only — do not use on Windows going forward)_

  - Old staging + wrapper scripts, preserved for reference only.

- `windows-bat/` _(current Windows approach — tiny BAT helpers)_

  - `bin/` → the `.bat` project + validation helpers you copy to `C:\setup-aryan\bin`

### Linux staging target (added)

- Binaries/scripts: `/usr/local/aryan-setup/`
- Wrapper commands (symlinked): `/usr/local/bin/setup-aryan`, `/usr/local/bin/setup-aryan-log`
- Logs: `/var/log/setup-aryan/`
- State: `/var/log/setup-aryan/state-files/`

> Windows does not use staging or state-files anymore (Windows is BAT-only KISS).
> The state-files contract below remains relevant only for Linux.

### Standardized automation contract (Linux only)

This repo’s Linux `setup-aryan` actions must follow these invariants so you can safely re-run them during debugging and recovery:

**1) Shell consistency**

- Linux: **bash** (POSIX-ish bash scripts)

**2) Logs**

- Linux logs: `/var/log/setup-aryan/`
- Log line format (exact): `<TZ dd-mm-yyyy HH:MM:ss> <Error|Warning|Info|Debug> <message>`

**3) State-files (no JSON, no symlinks)**

- Linux state dir: `/var/log/setup-aryan/state-files/` (real directory)
- Each action writes: `<action>.state` with the fields below (as `key=value`):

  - `action`
  - `status` (`success|failed|skipped`)
  - `rc`
  - `started_at` (ISO8601)
  - `finished_at` (ISO8601)
  - `user`
  - `host`
  - `log_path`
  - `version`

**4) Idempotency + force semantics (Linux)**

- Default: if `<action>.state` exists and `status=success`, the action should **skip** safely.
- Force: Linux actions must support: `--force`

### Prerequisites (before staging or running any actions) (updated)

**Windows**

- Windows uses manual installs + BAT helpers only.
- No PowerShell execution policy steps are required for Windows going forward.

**Linux (Ubuntu 24.04.x)**

- `bash`, `sudo`, `git` installed.
- You should be able to run `sudo` and write to `/usr/local/` and `/var/log/`.

### Repo TODOs to incorporate (tracked work) (kept)

- **TODO #1** Fix Python toolchain workflow (Linux + Windows, uv+conda, PATH/activation, VS Code reliability)
- **TODO #2** Notebook hang / runaway VRAM investigation + validation
- **TODO #3** Add TensorFlow flag separate from AI/ML + TF JIT/first-run optimization + validation
- **TODO #4** Explain/validate Xorg showing in `nvidia-smi`, keep GUI iGPU-first (PRIME on-demand)

### Staging commands (Linux only)

**Linux (run from repo root):**

```bash
sudo bash ./linux-setup/stage-aryan-setup.sh
```

_(Windows PowerShell staging is legacy and now lives in `windows-setup-legacy/` only.)_

### How to use the staged scripts (Linux only)

This is the day-to-day workflow once Linux staging is done: you **list** actions, **run** the one you need, and use **logs + state-files** to confirm what happened.

#### A) Find what actions exist (Linux)

```bash
setup-aryan list
```

#### B) Run an action (Linux)

```bash
setup-aryan <action-name>
# force rerun (even if it previously succeeded)
setup-aryan <action-name> --force
```

#### C) Check logs (Linux)

- `/var/log/setup-aryan/`

#### D) Check state-files (Linux)

- `/var/log/setup-aryan/state-files/`

---

## 0) Your system model (what we’re building)

### Hardware + constraints

- CPU: Intel Core Ultra 9 (275HX)
- GPU: RTX 5080 16GB (Blackwell)
- RAM: 32GB
- Storage: 2×1TB NVMe Gen4
- Secure Boot: **ON**
- BIOS Graphics Mode: **Dynamic Graphics** (**default**)

### Confirmed wiring constraint (critical)

- **HDMI external output is physically routed to the NVIDIA dGPU.**
- You verified: switching BIOS to UMA killed HDMI output in Windows.
- Therefore:

  - You **cannot** fully power-off the RTX while HDMI is in use.
  - You **can** keep RTX **idle/on-demand** (best compromise), and only light it up for CUDA workloads.

### Storage architecture (authority rules)

**Disk 0 (Windows)**

- `C:` (200GB): Windows OS + core drivers only
- `D:` (550GB): Windows dev authority (WSL + Docker + repos + tools + caches)
- `E:` (100GB): OneDrive authority (personal/college sync)
- `F:` (100GB, **NTFS**): Shared data lake (datasets/weights/checkpoints/exports only)

**Disk 1 (Linux)**

- EFI (1GB), `/boot` (1GB), swap (32GB), `/` (200GB), `/home` (~720GB)

**Non-negotiable rule**

- **Do not store dev environments or repos on `F:` (NTFS) from Linux.**
- `F:` is for big, mostly-static data: datasets/weights/checkpoints/exports.

All dev environments + repos live on:

- Windows → `D:`
- Linux → `/home`

---

## 1) BIOS baseline (set once, then keep stable)

1. Boot BIOS (F2 / Fn+F2)
2. Ensure:

   - Boot Mode: **UEFI**
   - TPM / Intel PTT: **Enabled**
   - Virtualization (VT-x/VT-d): **Enabled** (WSL2/Docker)
   - Secure Boot: **Enabled**
   - Graphics: **Dynamic Graphics** (**keep this as default**)

> **UMA mode**: great for battery **laptop-only**, but it kills CUDA and kills HDMI on your unit. Dynamic is your “always-works” default.

---

## 2) Build a Secure-Boot Ventoy USB (installer + rescue stick)

### 2.1 What to put on the Ventoy stick (recommended)

**Required**

- Windows 11 ISO (x64) — repair tools + reinstall option
- Ubuntu 24.04.x Desktop ISO (amd64) — install + rescue environment

**Optional (only if you really want imaging from USB)**

- Rescuezilla ISO (recent versions focus on Secure Boot compatibility, but always test boot on your exact machine) ([Linuxiac][1])

**Also optional**

- `TOOLS/Lenovo/BIOS/` folder to keep Lenovo BIOS updaters (not required for Ventoy)

### 2.2 Create Ventoy with Secure Boot support (Windows)

1. Download Ventoy (Windows ZIP), extract it

2. Run `Ventoy2Disk.exe` as Administrator

3. Select your USB drive (**triple-check it’s the USB**)

4. Enable:

   - `Option → Secure Boot Support` ✅
   - (If available) `Option → Partition Style → GPT`

5. Click **Install** (wipes the USB)

Ventoy auto-creates:

- a small EFI boot partition
- a large data partition for ISOs

No manual partitioning needed.

(Ventoy’s Secure Boot flow is “Enroll Key / Enroll Hash”.) ([ventoy.net][2])

### 2.3 Copy ISOs (recommended layout)

On the large Ventoy partition:

```text
ISO/Windows/Win11.iso
ISO/Linux/Ubuntu_24.04.iso
ISO/Rescue/Rescuezilla.iso (optional)
TOOLS/Lenovo/BIOS/ (optional)
```

### 2.4 First boot with Secure Boot ON (one-time enrollment)

1. Reboot → Boot Menu (F12)
2. Choose USB (UEFI)
3. Ventoy will prompt one-time Secure Boot enrollment → complete it ([ventoy.net][2])
4. Test boot:

   - Ubuntu ISO → reach “Try / Install”
   - Windows ISO → reach Windows Setup

**Rule for encryption stability**

- If you later boot an unsigned ISO, you _might_ need to temporarily disable Secure Boot, and Windows may ask for a recovery key when you come back.
- If you want “Secure Boot always ON”, stick to signed ISOs (Windows/Ubuntu, and only Rescue ISOs you have personally tested on this machine).

---

## 3) Windows 11 Home: keep `C:` clean, move everything heavy to `D:`

### 3.1 One-time Windows hygiene

1. Run Windows Update fully

2. Install:

   - Lenovo Vantage
   - Legion Space

3. Refresh rate sanity (battery):

   - Internal: use 60/120Hz daily; 240Hz only when needed
   - External HDMI: avoid max refresh unless you need it

### 3.2 Disable Fast Startup (mandatory for safe NTFS dual-boot)

Fast Startup can leave NTFS “hibernated” and Linux will refuse to mount or corrupt it.

- Control Panel → Power Options → “Choose what the power buttons do”
- “Change settings that are currently unavailable”
- Disable **Turn on fast startup**

### 3.3 Windows encryption (Device Encryption on Home)

- Settings → Privacy & security → Device encryption
- If available, enable it and store the recovery key safely.

> **PCR7 binding not supported**: that Windows status can stay “not supported” depending on firmware/boot state history.

The practical takeaway for this playbook: keep **Secure Boot ON** consistently once you enable encryption, and avoid flipping core boot settings every week.

---

## 4) Windows Dev Storage Layout (so nothing piles on C:)

Create these folders:

- `D:\dev\repos\`
- `D:\dev\tools\`
- `D:\dev\envs\`
- `D:\dev\cache\`
- `D:\apps\` (large GUI apps)
- `D:\profiles\` (browser profiles)

**Policy**

- Git repos → `D:\dev\repos`
- Toolchains → `D:\dev\tools`
- Envs → `D:\dev\envs`
- Caches → `D:\dev\cache`
- Big GUI apps → `D:\apps`

---

## 5) Windows: WSL2 + Docker (move to D: and cap RAM)

### 5.1 Cap WSL2 RAM (stops “Windows uses 10GB+”)

Create: `C:\Users\<yourusername>\.wslconfig`

```ini
[wsl2]
memory=6GB
processors=6
swap=4GB
```

Apply (run in **CMD**):

```bat
wsl --shutdown
```

Tuning:

- Daily: 4–6GB
- Heavy tasks: 8–10GB temporarily → then reduce again

---

## 5.2) WSL 2 Optimization, Migration, and Physical Disk Mounting

### 5.2.1) Global Configuration (.wslconfig)

To configure resource limits globally for all WSL 2 distributions, the .wslconfig file must be placed in the Windows User Profile directory.
Path: `%UserProfile%\.wslconfig` (e.g., `C:\Users\<YourName>\.wslconfig`)
Application: Run `wsl --shutdown` in **CMD** to apply changes.

### 5.2.2 Relocating WSL Distribution to D: Drive

To move the Ubuntu installation from the C: drive to the D: drive to manage storage effectively:

```bat
REM 1. Export the current distribution to a temporary tarball
wsl --export Ubuntu D:\WSL\backup\Ubuntu.tar

REM 2. Unregister (delete) the distribution from the C: drive
wsl --unregister Ubuntu

REM 3. Create the new directory and import the distribution to the D: drive
mkdir D:\WSL\Ubuntu
wsl --import Ubuntu D:\WSL\Ubuntu D:\WSL\backup\Ubuntu.tar --version 2

REM 4. Set as default
wsl --set-default Ubuntu
```

To verify the registration path, query the registry from **CMD**:

```bat
reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss" /s
```

Look for the matching `DistributionName` and its `BasePath`.

### 5.2.3) Verifying Distribution and OS Version

To inspect the internal Linux OS version (e.g., Ubuntu 22.04) without an interactive login:

```bat
REM Check WSL Architecture version
wsl -l -v

REM Check internal OS Release version
wsl -d Ubuntu cat /etc/os-release
```

### 5.2.4) Mounting Physical Dual-Boot NVMe Disks

Mounting the Partition:

```bat
REM Mount the Root partition from the second NVMe disk
wsl --mount \\.\PHYSICALDRIVE1 --partition 4

REM Access via WSL terminal:
REM Files located at: /mnt/wsl/PHYSICALDRIVE1p4

REM Unmount before rebooting into Physical Linux
wsl --unmount \\.\PHYSICALDRIVE1
```

### 5.2.5) Post-Migration Cleanup

After verifying that the D: drive installation is running and the data is accessible, remove the temporary backup:

```bat
rmdir /s /q D:\WSL\backup
```

### 5.3) Move Docker Desktop storage to D:

Docker Desktop → Settings → Resources → Advanced

- Disk image location: `D:\DockerDesktop\`

Apply & restart.

---

## 6) Windows Dev Setup (Java-JDK 21, multi-Node, Miniconda)

---

### 🛠️ Manual Environment Restoration & Parity Guide (Windows 2025)

This guide provides the systematic steps to manually restore the **Legion Pro 7i** environment, purging the artifacts of failed automation and enforcing absolute storage authority.

#### 🧹 Phase 1: The "Nuclear" Cleanup

Before installing anything, we must remove the "clutter" (ghost folders, corrupted paths, and partial downloads) generated by previous automation attempts.

#### 1. File System Purge

Delete the following folders manually using File Explorer:

- **Legacy Framework:** `C:\Tools\aryan-setup` (Delete the entire folder, if it exists).

- **The Ghost Folders:** Search for and delete any folder named `-Force`. Look specifically in:

- `C:\Windows\System32\-Force`

- `D:\dev\tools\-Force`

- `C:\Users\aarya\AppData\Local\-Force`

- **The Temp Files:** Press `Win + R`, type `%temp%`, and delete all contents.

#### 2. Environment Variable Scrub

1. Search for "Edit the system environment variables" in Windows.
2. Under **User Variables**, delete: `JAVA_HOME`, `GRADLE_USER_HOME`, `UV_CACHE_DIR` (if incorrect).
3. Under **User Path**, delete any entry containing `-Force` or `C:\Tools\aryan-setup\bin`.
4. Under **System Variables**, check the **Path** and remove any `-Force` or invalid Java entries.

---

#### 🏗️ Phase 2: Systematic Manual Installation

#### 1. Java (JDK 21)

**Goal:** Global binary authority on C: with high-growth build caches on D:.

1. **Download:** Adoptium Temurin JDK 21 (MSI Installer) — [https://adoptium.net/temurin/releases/?version=21](https://adoptium.net/temurin/releases/?version=21)
2. **Install:** Run the MSI. Set the install path to: `C:\Program Files\Java\jdk-21`.
3. **Environment Variables:**

- Create **System Variable**: `JAVA_HOME` = `C:\Program Files\Java\jdk-21`.
- Edit **System Path**: Add `%JAVA_HOME%\bin`.

4. **Cache Redirection:**

- Create directory: `D:\dev\cache\.gradle`.
- Create **User Variable**: `GRADLE_USER_HOME` = `D:\dev\cache\.gradle`.

#### 2. Python (Conda & uv)

**Goal:** Total isolation on D: drive to mirror Linux `/home` parity.

1. **Miniconda:**

- **Download:** [https://docs.anaconda.com/miniconda/](https://docs.anaconda.com/miniconda/)

- **Install:** Choose "Just Me". Set path to: `D:\dev\tools\miniconda3`.

- **Config:** Open CMD and run:

```bat
conda config --set envs_dirs D:\dev\envs\conda
conda config --set pkgs_dirs D:\dev\cache\conda\pkgs
```

2. **uv (Fast Package Manager):**

- **Download:** [https://github.com/astral-sh/uv/releases](https://github.com/astral-sh/uv/releases)
- **Install:** Extract `uv.exe` to a stable tools location (example): `D:\dev\tools\bin\` and add that folder to PATH.
- **Env Var:** Create **User Variable** `UV_CACHE_DIR` = `D:\dev\cache\uv`.

#### 3. Node.js (NVM & pnpm)

**Goal:** Version management and global store managed entirely on D:.

1. **NVM-Windows:**

- **Download:** [https://github.com/coreybutler/nvm-windows/releases](https://github.com/coreybutler/nvm-windows/releases)
- **Install (recommended paths):**

  - NVM Home: `D:\dev\tools\nvm-windows`
  - Node Symlink: `D:\dev\tools\nodejs`

2. **Node & pnpm:**

- Open CMD: `nvm install lts` then `nvm use lts`.
- Install pnpm: `npm install -g pnpm`.

3. **pnpm Redirection:**

- Run in terminal (optional):

```bat
pnpm config set store-dir D:\dev\cache\pnpm\store
pnpm config set cache-dir D:\dev\cache\pnpm\cache
```

---

#### 🔍 Phase 3: Final Verification Registry

To ensure the manual setup is correct, verify the following outputs:

| Command                     | Expected Output Path                        |
| --------------------------- | ------------------------------------------- |
| `where.exe java`            | `C:\Program Files\Java\jdk-21\bin\java.exe` |
| `where.exe conda`           | `D:\dev\tools\miniconda3\Scripts\conda.exe` |
| `where.exe node`            | `D:\dev\tools\nodejs\node.exe`              |
| `echo %UV_CACHE_DIR%`       | `D:\dev\cache\uv`                           |
| `pnpm config get store-dir` | `D:\dev\cache\pnpm\store`                   |

---

#### 📂 Repository Alignment (updated)

- **Do not use any `.ps1` automation on Windows anymore.**
- Keep `windows-setup-legacy\` only as a history reference.
- Use the batch audit tool as your primary audit tool:

```bat
validate-windows-dev
```

---

**GPU policy on Windows (important)**

- Settings → System → Display → Graphics
- Chrome / VS Code / Discord / browsers → **Power saving (iGPU)**
- Training tools (Python, CUDA apps) → **High performance (NVIDIA)**

---

## 7) Ubuntu 24.04.x install (Disk 1) + keep `/` minimal

### 7.1 Manual partitioning (your agreed layout)

Disk 1:

- EFI 1GB FAT32 → mount `/boot/efi`
- `/boot` 1GB ext4 → mount `/boot`
- swap 32GB
- `/` 200GB ext4
- `/home` remaining ext4

### 7.2 First boot essentials

```bash
sudo apt update && sudo apt -y upgrade
sudo apt -y install build-essential dkms git curl wget unzip htop nvme-cli ca-certificates gnupg
```

---

## 8) Kernel strategy (MANDATORY): HWE + keep GA fallback + GRUB menu visible

### 8.1 Install HWE kernel (for 2025 hardware)

```bash
sudo apt -y install linux-generic-hwe-24.04
sudo reboot
```

Verify:

```bash
uname -r
```

**If you see `6.14.0-27-generic`: yes, that’s normal for the 24.04 HWE track in late 2025.** HWE is meant to move forward (6.11+, then newer) as hardware enablement evolves.

### 8.2 Keep a GA (older/stable) kernel installed as a fallback

This is how you guarantee “two kernels available” in GRUB.

```bash
sudo apt -y install linux-image-generic linux-headers-generic
sudo reboot
```

### 8.3 Make sure GRUB menu shows kernels every boot

Edit:

```bash
sudo nano /etc/default/grub
```

Set:

```ini
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=10

# Optional (more transparent boot for debugging)
GRUB_CMDLINE_LINUX_DEFAULT=""
```

Apply:

```bash
sudo update-grub
```

Now you’ll see:

- Normal Ubuntu entry
- **Advanced options for Ubuntu** → choose GA kernel or HWE kernel

> This “HWE + GA fallback” is the safest laptop strategy when you’re running cutting-edge NVIDIA + hybrid graphics.

---

## 9) NVIDIA on Ubuntu with Secure Boot ON (stable sequence for RTX 5080)

### 9.1 Why “open kernel modules” matter on modern NVIDIA

NVIDIA explicitly documents “Open Kernel Modules” installation routes on Ubuntu (packaged installs), vs proprietary modules and vs manual `.run` installs.
For an RTX 50-series laptop, prefer packaged installs + open module flavor when available.
([NVIDIA Docs][3])

### 9.2 Clean slate (if you’ve been experimenting)

If you already broke drivers previously and want to reset:

```bash
sudo apt purge -y '^nvidia-.*'
sudo apt autoremove -y --purge
sudo rm -f /etc/modprobe.d/nvidia*.conf /etc/modprobe.d/blacklist-nouveau.conf
sudo update-initramfs -u
```

Reboot into the iGPU path (it should still boot).

### 9.3 Install the recommended NVIDIA driver (Secure Boot flow)

1. Discover what Ubuntu recommends:

   ```bash
   sudo ubuntu-drivers devices
   ```

2. Install using ubuntu-drivers (this stays aligned with your system and updates):

   ```bash
   sudo ubuntu-drivers autoinstall
   ```

3. **Secure Boot MOK enrollment**

   - During install you may be asked to set a password.
   - On reboot you must complete MOK enrollment (blue screen).
   - Ubuntu’s Secure Boot chain uses shim + MokManager for this flow. ([Ubuntu Documentation][4])

4. Verify:

   ```bash
   nvidia-smi
   ```

### 9.4 If you specifically want the “open” flavor (when your repos provide it)

List open flavors available on your system:

```bash
apt-cache search nvidia-driver | grep -i open || true
apt-cache search nvidia-open || true
```

Then install the best available “open” package **that exists in your repo** (examples—don’t copy blindly if your apt-cache doesn’t show them):

```bash
# example pattern
sudo apt install -y nvidia-driver-580-open
# or (on some repos / naming schemes)
sudo apt install -y nvidia-open
```

Then reboot and verify with `nvidia-smi`.

### 9.5 Do you need to reinstall build-essential after a kernel upgrade?

No. But you **do** need headers for each installed kernel so DKMS modules can build.

---

## 10) Remove Snap (clean) + block it from returning (Ubuntu 24.04)

### 10.1 Remove snaps + snapd

```bash
sudo snap remove --purge firefox || true
sudo snap remove --purge thunderbird || true
sudo snap remove --purge gnome-42-2204 || true
sudo snap remove --purge gtk-common-themes || true
sudo snap remove --purge bare || true
sudo snap remove --purge core22 || true
sudo apt purge -y snapd
sudo apt autoremove --purge -y
rm -rf ~/snap
sudo rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd /usr/lib/snapd
```

### 10.2 Block snapd from being reinstalled

```bash
echo 'Package: snapd
Pin: release a=*
Pin-Priority: -10' | sudo tee /etc/apt/preferences.d/nosnap.pref
```

---

## 11) iGPU-first policy on Ubuntu (don’t wake RTX for GUI apps)

### 11.1 PRIME profile: on-demand (iGPU desktop, RTX on request)

```bash
sudo prime-select on-demand
sudo reboot
```

Verify:

```bash
sudo prime-select query
```

### 11.2 Install switcheroo-control (adds “Launch using Dedicated GPU” option)

This makes the **default** integrated, and dedicated is opt-in via right click.

```bash
sudo apt -y install switcheroo-control
sudo systemctl enable --now switcheroo-control
```

### 11.3 CUDA rule (how you intentionally use RTX)

- Keep desktop on iGPU (`prime-select on-demand`)
- Run training/inference on RTX using normal CUDA tools (PyTorch/TensorFlow will pick NVIDIA if driver is installed).
- Do **not** “force dGPU” for browsers/editors.

---

## 12) Chrome on Linux: GUI shortcut + iGPU + cache in /home (no `$HOME` bugs)

### Why your `$HOME` became literal in the `.desktop`

- `.desktop` `Exec=` is **not** a shell script; it doesn’t reliably expand `$HOME`.
- Editing system `.desktop` with `sudo` can also cause `/root` confusion.
- Correct fix: create a **wrapper script** (runs as your user → `$HOME` expands) and a **user-level desktop entry**.

### 12.1 Create cache/profile directories (in /home)

```bash
mkdir -p "$HOME/local_chrome_storage/cache"
mkdir -p "$HOME/profiles/chrome"
```

### 12.2 Create a wrapper launcher (safe, portable, no hardcoded /home/aryan)

```bash
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/chrome-igpu" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

exec /usr/bin/google-chrome-stable \
  --user-data-dir="$HOME/profiles/chrome" \
  --disk-cache-dir="$HOME/local_chrome_storage/cache" \
  --gpu-testing-vendor-id=0x8086 \
  "$@"
EOF
chmod +x "$HOME/.local/bin/chrome-igpu"
```

Ensure `~/.local/bin` is in PATH (Ubuntu usually does this already).
If not:

```bash
grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc || \
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### 12.3 Create a proper Ubuntu application shortcut (desktop icon)

Copy the system desktop file to your user area:

```bash
mkdir -p "$HOME/.local/share/applications"
cp /usr/share/applications/google-chrome.desktop \
  "$HOME/.local/share/applications/google-chrome-igpu.desktop"
```

Edit the Exec line:

```bash
sed -i 's|^Exec=.*|Exec=chrome-igpu %U|g' \
  "$HOME/.local/share/applications/google-chrome-igpu.desktop"
```

(Optional) Rename visible name:

```bash
sed -i 's|^Name=.*|Name=Google Chrome (iGPU)|g' \
  "$HOME/.local/share/applications/google-chrome-igpu.desktop"
```

Update app database:

```bash
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
```

Now you can launch Chrome from:

- Activities search
- Dock favorites
- App grid

…and it will use your wrapper (iGPU preference + cache in /home).

> Note: `%U` is a **valid desktop placeholder**. `%h` is **not** a standard `.desktop` placeholder. Use `%U` for multiple URLs or `%u` for single. (`%U` is what Chrome desktop files commonly use.)

---

## 13) VS Code on Linux: keep it on /home + optional “portable-ish” placement

By default, VS Code on Linux stores data under `/home` (good).

If you want to keep everything under your own structure:

### Option A (recommended): normal install (already safe)

Install via `.deb` and you’re done (data remains in `/home`).

### Option B: “self-contained” profile directories (keeps cache under ~/dev/cache)

Create dedicated directories:

```bash
mkdir -p ~/dev/cache/vscode
mkdir -p ~/dev/envs/vscode
```

Then create a desktop entry that launches Code with explicit paths (works for Code deb):

```bash
cat > "$HOME/.local/share/applications/code-homedirs.desktop" << 'EOF'
[Desktop Entry]
Name=VS Code (Home Dirs)
Comment=VS Code with cache/config pinned to /home
Exec=/usr/bin/code --user-data-dir=%h/dev/envs/vscode --extensions-dir=%h/dev/envs/vscode/extensions
Icon=code
Type=Application
Categories=Development;IDE;
Terminal=false
EOF
```

> `%h` in desktop entries expands to the user’s home directory **in many desktop environments**, but it’s not as universally dependable as using a wrapper script.

If you want maximum robustness, use the same wrapper technique as Chrome (recommended whenever you care about path expansion).

---

## 14) Linux shared data lake: mount `F:` (NTFS) at `/mnt/shared`

### 14.1 Create mount point

```bash
sudo mkdir -p /mnt/shared
```

### 14.2 Find UUID

```bash
lsblk -f
```

### 14.3 Add to `/etc/fstab` (ntfs3)

```bash
sudo nano /etc/fstab
```

Add (replace UUID):

```fstab
UUID=XXXX-XXXX /mnt/shared ntfs3 defaults,noatime,uid=1000,gid=1000,umask=022 0 0
```

Apply:

```bash
sudo mount -a
df -h | grep shared
```

Create structure:

```bash
mkdir -p /mnt/shared/{datasets,weights,checkpoints,exports,hf,torch}
```

---

## 15) Linux Dev Setup (all in /home): multi-Java, multi-Node, Miniconda, Android Studio

### 15.1 Canonical dev structure

```bash
mkdir -p ~/dev/{repos,tools,envs,cache,tmp}
mkdir -p ~/profiles
```

### 15.2 Node.js (multi-version) via NVM

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.bashrc
nvm install --lts
nvm install 20
nvm use --lts
node -v && npm -v
npm config set cache ~/dev/cache/npm --global
```

### 15.3 Java (multi-version) via SDKMAN

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

### 15.4 Miniconda in /home (envs/caches controlled)

Install Miniconda to `~/miniconda3`, then:

```bash
~/miniconda3/bin/conda init
source ~/.bashrc
conda config --set auto_activate_base false
conda config --add envs_dirs ~/dev/envs/conda
conda config --add pkgs_dirs ~/dev/cache/conda-pkgs
```

### 15.5 Android Studio on Linux (keep growth in /home)

Extract Android Studio tar.gz to:

- `~/dev/tools/android-studio/`

Launch:

```bash
~/dev/tools/android-studio/android-studio/bin/studio.sh
```

Set environment variables in `~/.bashrc`:

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

---

## 16) Keep Linux `/` (200GB) from growing beyond ~50–60%

Big offenders:

- systemd journal logs
- apt caches
- `/var/log` growth
- snap/flatpak (you’re removing snap)

### 16.1 Cap systemd journal size + retention

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

### 16.2 Weekly journald vacuum (systemd timer)

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

### 16.3 Monthly APT cache clean

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

### 16.4 Root usage quick check

```bash
df -h /
sudo du -xh /var | sort -h | tail -n 30
```

---

## 17) AI cache policy (prevents silent bloat)

### 17.1 Put AI assets on shared lake

- datasets → `/mnt/shared/datasets`
- weights → `/mnt/shared/weights`
- checkpoints → `/mnt/shared/checkpoints`
- exports → `/mnt/shared/exports`

### 17.2 Redirect ML caches to `/mnt/shared` (Linux)

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

## 18) Battery optimization on Linux (realistic for your wiring + goals)

### 18.1 Use balanced/power-saver profiles for daily work

Ubuntu ships power-profiles-daemon by default:

```bash
powerprofilesctl get
powerprofilesctl set balanced

# or for max battery (when not training)
powerprofilesctl set power-saver
```

### 18.2 Keep RTX “available but asleep” (best compromise)

- Default: `prime-select on-demand` (iGPU desktop, RTX only when used)
- If you need max battery **and** no HDMI: you can try Intel-only mode:

  - `sudo prime-select intel && reboot`
  - But: CUDA won’t work in that mode, and HDMI on your unit likely won’t work.

### 18.3 Wayland note (RAM + stability)

Ubuntu GNOME uses Wayland by default on many setups; RAM savings are not huge, but Wayland can reduce some compositor weirdness on hybrid systems.
Your real RAM win is still:

- limiting background apps
- keeping WSL capped (Windows side)
- keeping GUI apps on iGPU (Linux side via on-demand)

---

## 19) Legion-specific control stack on Linux (fans / power modes / battery conservation / monitoring / RGB)

Windows:

- Lenovo Vantage + Legion Space remain your “official” control suite.

Linux equivalents:

- **LenovoLegionLinux (LLL)**: DKMS kernel module + daemon (`legiond`) + CLI/GUI tooling for Legion controls (fan/power features vary by model).
  It’s packaged on some distros and commonly installed from source on Ubuntu.
  ([Debian Packages][5])

- **Keyboard RGB**: L5P-Keyboard-RGB supports many Legion generations on Linux/Windows (check your exact keyboard controller compatibility).
  ([GitHub][6])

### 19.1 Install LenovoLegionLinux on Ubuntu (source-based approach)

Because packaging varies on Ubuntu, the most reliable approach is “follow the repo install steps exactly”, but the standard pattern is:

```bash
sudo apt -y install dkms build-essential git
mkdir -p ~/dev/tools
cd ~/dev/tools
git clone
cd
# then follow repo: dkms install / make install / install.sh (repo-dependent)
```

**Important DKMS rule with dual kernels**
When you keep **GA + HWE** kernels installed, DKMS modules should build for both.
If one kernel is missing headers, you fix it with:

```bash
sudo apt -y install linux-headers-generic linux-headers-generic-hwe-24.04
```

### 19.2 Optional: GUI front-ends

Some desktop widgets/front-ends exist that talk to Legion features via the kernel module stack (availability varies). PlasmaVantage is one example in the ecosystem (KDE-oriented).
([about.gitlab.com][7])

---

## 20) Backup + fast recovery strategy (student-proof)

### 20.1 Cloud baseline

- Code: GitHub (all repos)
- Docs: OneDrive (E:)
- Important exports/results:

  - sync selectively to OneDrive
  - or store under `/mnt/shared/exports`

### 20.2 Windows recovery (fast)

- Hasleo images occasionally (before major risky changes)
- Ventoy Windows ISO always available for repair boot

### 20.3 Linux recovery (fast, no drama)

Make Linux reproducible:

- `~/dev/repos` is git
- export env specs
- keep a tiny “bootstrap” repo: `machine-setup`

Helpful exports:

```bash
conda env export > ~/dev/repos//env.yml
pip freeze > ~/dev/repos//requirements.txt
```

---

## 21) Validation checklist (run these to confirm you’re “done”)

### Windows checks

- `C:` stays clean (OS only)

- WSL memory stable:

  - Task Manager → Memory stable at idle

- WSL + Docker storage are on `D:`

- Chrome profile on `D:\profiles\...`

- Android SDK/AVD/Gradle caches on `D:`

- Graphics settings:

  - GUI apps → iGPU
  - training apps → NVIDIA

### Linux checks

- `/` usage stays < 60%:

  ```bash
  df -h /
  ```

- both kernels exist:

  ```bash
  dpkg -l | grep -E 'linux-image|linux-headers' | grep generic
  ```

- GRUB menu shows:

  ```bash
  grep -E 'GRUB_TIMEOUT_STYLE|GRUB_TIMEOUT' /etc/default/grub
  ```

- shared mounted:

  ```bash
  df -h | grep shared
  ```

- NVIDIA works when needed:

  ```bash
  nvidia-smi
  ```

- on-demand mode set:

  ```bash
  sudo prime-select query
  ```

- ML caches redirected:

  ```bash
  echo $HF_HOME
  echo $TORCH_HOME
  ```

---

# Quick execution order (recommended)

1. **Ventoy (Secure Boot)** → test boot Windows ISO + Ubuntu ISO
2. Windows: disable Fast Startup → cap WSL RAM → move WSL to D → move Docker to D
3. Windows: VS Code portable → Miniconda to D → Android Studio ZIP to D → Chrome profile to D → set GPU prefs
4. Ubuntu: install → **HWE kernel** → install **GA fallback kernel** → enable **GRUB menu**
5. Ubuntu: NVIDIA driver (Secure Boot MOK) → mount `/mnt/shared` → journald + timers
6. Ubuntu: **snap removal + block snap** → install Chrome/Thunderbird as DEB → **Chrome wrapper + desktop icon (iGPU + cache)**
7. Ubuntu: NVM + SDKMAN + Miniconda + Android Studio → redirect AI caches → validate

---

## Notes you asked about (kept here so you don’t forget)

- **HWE kernel showing 6.14.x** after `linux-generic-hwe-24.04` is normal in late 2025.
- After kernel upgrades you don’t “reinstall build-essential”; you just ensure **headers exist** for DKMS modules.
- HDMI is dGPU-wired → you can’t fully power off RTX while using HDMI, but you can keep GUI on iGPU and use RTX only for compute.

[1]: https://linuxiac.com/rescuezilla-2-6-released-with-secure-boot-fixes/ "Rescuezilla 2.6 Released with Secure Boot Fixes and ..."
[2]: https://ventoy.net/en/doc_secure.html "About Secure Boot in UEFI mode"
[3]: https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/ubuntu.html "Ubuntu — NVIDIA Driver Installation Guide"
[4]: https://documentation.ubuntu.com/security/security-features/platform-protections/secure-boot/ "UEFI Secure Boot"
[5]: https://packages.debian.org/source/sid/lenovolegionlinux "Details of source package lenovolegionlinux in sid"
[6]: https://github.com/4JX/L5P-Keyboard-RGB "4JX/L5P-Keyboard-RGB"
[7]: https://gitlab.com/Scias/plasmavantage "PlasmaVantage - Scias"
