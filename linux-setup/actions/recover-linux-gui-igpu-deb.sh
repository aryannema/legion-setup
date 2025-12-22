#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# recover-linux-gui-igpu-deb.sh
#
# Purpose:
#   Idempotent recovery action for Ubuntu 24.04:
#     - Remove snap/snapd safely
#     - Block snapd from returning
#     - Ensure Chrome is installed via DEB repo (keyring method)
#     - Ensure Thunderbird is installed via apt (mozillateam PPA preferred)
#     - Keep iGPU-first behavior (prime-select on-demand if available)
#     - Install Chrome iGPU wrapper + user desktop entry (no $HOME bugs)
#
# Prerequisites:
#   - Ubuntu 24.04.x
#   - sudo privileges
#   - apt, curl, gpg, add-apt-repository
#
# Usage:
#   setup-aryan recover-linux-gui-igpu-deb
#   setup-aryan recover-linux-gui-igpu-deb -- --user aryan
#
# Logging:
#   Managed by setup-aryan wrapper.
# ==============================================================================

TZ_NAME="Asia/Kolkata"
ACTION_NAME="recover-linux-gui-igpu-deb"

ts() { TZ="${TZ_NAME}" date "+%Z %d-%m-%Y %H:%M:%S"; }
log() { echo "$(ts) INFO ${ACTION_NAME}: $*"; }
warn() { echo "$(ts) WARNING ${ACTION_NAME}: $*" >&2; }

TARGET_USER="${SUDO_USER:-aryan}"

print_help() {
  cat <<EOF
${ACTION_NAME}

Usage:
  ${ACTION_NAME}.sh [--user <username>]

EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      TARGET_USER="${2:-}"
      shift 2
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      warn "Unknown arg: $1"
      shift
      ;;
  esac
done

if [[ -z "${TARGET_USER}" ]]; then
  TARGET_USER="aryan"
fi

TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6 || true)"
if [[ -z "${TARGET_HOME}" ]]; then
  TARGET_HOME="/home/${TARGET_USER}"
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

sudo_apt_update_once() {
  # Avoid spamming updates: state file lives in /var/log/setup-aryan/state-files
  local state="/var/log/setup-aryan/state-files/${ACTION_NAME}.apt-updated"
  if [[ -f "${state}" ]]; then
    return 0
  fi
  log "apt update (one-time per machine unless state file removed)"
  sudo apt update
  sudo mkdir -p "$(dirname "${state}")"
  sudo touch "${state}"
  sudo chown "${TARGET_USER}:${TARGET_USER}" "${state}" || true
}

ensure_file_exact() {
  local path="$1"
  local content="$2"
  local tmp
  tmp="$(mktemp)"
  printf "%s" "${content}" > "${tmp}"
  if sudo test -f "${path}"; then
    if sudo cmp -s "${tmp}" "${path}"; then
      rm -f "${tmp}"
      return 0
    fi
  fi
  sudo mkdir -p "$(dirname "${path}")"
  sudo cp "${tmp}" "${path}"
  sudo chmod 0644 "${path}" || true
  rm -f "${tmp}"
}

remove_snap_if_present() {
  if ! need_cmd snap; then
    return 0
  fi

  log "Removing common snaps (ignore errors if already absent)"
  sudo snap remove --purge firefox 2>/dev/null || true
  sudo snap remove --purge thunderbird 2>/dev/null || true
  sudo snap remove --purge gnome-42-2204 2>/dev/null || true
  sudo snap remove --purge gtk-common-themes 2>/dev/null || true
  sudo snap remove --purge bare 2>/dev/null || true
  sudo snap remove --purge core22 2>/dev/null || true

  log "Purging snapd via apt (idempotent)"
  sudo apt purge -y snapd || true
  sudo apt autoremove --purge -y || true

  log "Cleaning leftover snap directories (idempotent)"
  rm -rf "${TARGET_HOME}/snap" || true
  sudo rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd /usr/lib/snapd || true
}

block_snapd() {
  log "Blocking snapd re-install via apt pin"
  ensure_file_exact "/etc/apt/preferences.d/nosnap.pref" \
'Package: snapd
Pin: release a=*
Pin-Priority: -10
'
}

ensure_chrome_repo() {
  log "Ensuring Google Chrome keyring + repo exists"
  sudo mkdir -p /usr/share/keyrings

  # Keyring: download and dearmor into keyring file
  if [[ ! -f /usr/share/keyrings/google-chrome.gpg ]]; then
    log "Installing google-chrome.gpg keyring"
    curl -fSsL https://dl.google.com/linux/linux_signing_key.pub \
      | gpg --dearmor \
      | sudo tee /usr/share/keyrings/google-chrome.gpg >/dev/null
    sudo chmod 0644 /usr/share/keyrings/google-chrome.gpg || true
  else
    log "Keyring already present: /usr/share/keyrings/google-chrome.gpg"
  fi

  ensure_file_exact "/etc/apt/sources.list.d/google-chrome.list" \
'deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main
'
}

ensure_thunderbird_deb() {
  log "Ensuring mozillateam PPA is configured (for deb Thunderbird preference)"
  if ! need_cmd add-apt-repository; then
    sudo_apt_update_once
    sudo apt install -y software-properties-common
  fi

  # Add PPA only if not already present
  if ! ls /etc/apt/sources.list.d/*mozillateam* >/dev/null 2>&1; then
    sudo add-apt-repository ppa:mozillateam/ppa -y
  else
    log "mozillateam PPA already present"
  fi

  ensure_file_exact "/etc/apt/preferences.d/mozilla-ppa" \
'Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
'
}

install_debs() {
  sudo_apt_update_once
  log "Installing (or ensuring) core desktop packages + Chrome + Thunderbird"
  sudo apt install -y --reinstall ubuntu-desktop gnome-shell gnome-control-center gnome-terminal || true
  sudo apt install -y google-chrome-stable || true
  sudo apt install -y thunderbird || true
}

set_prime_ondemand() {
  if need_cmd prime-select; then
    local cur
    cur="$(sudo prime-select query 2>/dev/null || true)"
    log "Current prime-select: ${cur:-unknown}"
    if [[ "${cur}" != "on-demand" ]]; then
      log "Setting prime-select on-demand"
      sudo prime-select on-demand || true
    else
      log "prime-select already on-demand"
    fi
  else
    warn "prime-select not found; skipping PRIME mode set"
  fi
}

install_user_chrome_wrapper_and_desktop() {
  log "Creating user Chrome iGPU wrapper + desktop entry (no \$HOME expansion bugs)"

  # Create dirs as target user
  sudo -u "${TARGET_USER}" mkdir -p "${TARGET_HOME}/local_chrome_storage/cache"
  sudo -u "${TARGET_USER}" mkdir -p "${TARGET_HOME}/profiles/chrome"
  sudo -u "${TARGET_USER}" mkdir -p "${TARGET_HOME}/.local/bin"
  sudo -u "${TARGET_USER}" mkdir -p "${TARGET_HOME}/.local/share/applications"

  # Wrapper
  local wrapper="${TARGET_HOME}/.local/bin/chrome-igpu"
  if [[ ! -f "${wrapper}" ]]; then
    sudo -u "${TARGET_USER}" bash -lc "cat > '${wrapper}' << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

exec /usr/bin/google-chrome-stable \\
  --user-data-dir=\"\$HOME/profiles/chrome\" \\
  --disk-cache-dir=\"\$HOME/local_chrome_storage/cache\" \\
  --gpu-testing-vendor-id=0x8086 \\
  \"\$@\"
EOF"
    sudo chmod +x "${wrapper}" || true
  else
    log "Wrapper already exists: ${wrapper}"
  fi

  # Ensure PATH export exists (idempotent append)
  local bashrc="${TARGET_HOME}/.bashrc"
  if [[ -f "${bashrc}" ]]; then
    if ! sudo -u "${TARGET_USER}" grep -q 'export PATH="\$HOME/.local/bin:\$PATH"' "${bashrc}"; then
      sudo -u "${TARGET_USER}" bash -lc "echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> '${bashrc}'"
    fi
  fi

  # Desktop entry (copy system chrome desktop if present)
  local sys_desktop="/usr/share/applications/google-chrome.desktop"
  local user_desktop="${TARGET_HOME}/.local/share/applications/google-chrome-igpu.desktop"
  if [[ -f "${sys_desktop}" ]]; then
    if [[ ! -f "${user_desktop}" ]]; then
      sudo -u "${TARGET_USER}" cp "${sys_desktop}" "${user_desktop}"
    fi
    # Exec + Name
    sudo -u "${TARGET_USER}" sed -i 's|^Exec=.*|Exec=chrome-igpu %U|g' "${user_desktop}" || true
    sudo -u "${TARGET_USER}" sed -i 's|^Name=.*|Name=Google Chrome (iGPU)|g' "${user_desktop}" || true
    sudo -u "${TARGET_USER}" update-desktop-database "${TARGET_HOME}/.local/share/applications" 2>/dev/null || true
  else
    warn "System desktop file not found at ${sys_desktop}; skipping desktop entry"
  fi
}

main() {
  log "Target user: ${TARGET_USER} (home: ${TARGET_HOME})"

  remove_snap_if_present
  block_snapd

  ensure_chrome_repo
  ensure_thunderbird_deb

  install_debs
  set_prime_ondemand
  install_user_chrome_wrapper_and_desktop

  log "Done."
  log "Notes:"
  log "  - If PRIME mode was changed, a reboot may be required for full effect."
  log "  - Validate with: setup-aryan validate-linux-gpu"
}

main
