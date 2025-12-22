#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# install-vscode-linux.sh
#
# Prerequisites:
#   - Ubuntu 24.04.x
#   - sudo access
#   - curl, gpg, apt
#
# Usage:
#   setup-aryan install-vscode-linux
#   OR run directly:
#     ./install-vscode-linux.sh [--portable-dirs]
#
# Flags:
#   --portable-dirs   Create a "self-contained" user profile/extension location
#                    under ~/dev/envs/vscode and a launcher helper.
#
# Logging:
#   - Logs to: /var/log/setup-aryan/install-vscode-linux.log
#   - State to: /var/log/setup-aryan/state-files/install-vscode-linux.state
# ==============================================================================

ACTION_NAME="install-vscode-linux"
LOG_DIR="/var/log/setup-aryan"
STATE_DIR="/var/log/setup-aryan/state-files"
LOG_FILE="${LOG_DIR}/${ACTION_NAME}.log"
STATE_FILE="${STATE_DIR}/${ACTION_NAME}.state"

ts() { TZ="Asia/Kolkata" date '+%Z %d-%m-%Y %H:%M:%S'; }
log() {
  local level="$1"; shift
  local msg="$*"
  mkdir -p "$LOG_DIR" "$STATE_DIR"
  printf '%s %s %s\n' "$(ts)" "$level" "$msg" | tee -a "$LOG_FILE" >/dev/null
}
die() { log "Error" "$*"; exit 1; }

ensure_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    exec sudo -E bash "$0" "$@"
  fi
}

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
PORTABLE_DIRS="false"

usage() {
  cat <<EOF
${ACTION_NAME}

Usage:
  ${ACTION_NAME} [--portable-dirs]
  ${ACTION_NAME} --help

Flags:
  --portable-dirs   Create VS Code profile/extension dirs under:
                    ${TARGET_HOME}/dev/envs/vscode
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --portable-dirs) PORTABLE_DIRS="true"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown argument: $1 (use --help)" ;;
    esac
  done
}

require_cmd() {
  local c="$1"
  command -v "$c" >/dev/null 2>&1 || die "Missing prerequisite command: $c"
}

install_prereqs() {
  log "Info" "Installing prerequisites (if needed)..."
  apt-get update -y
  apt-get install -y --no-install-recommends ca-certificates curl gnupg apt-transport-https
}

setup_vscode_repo() {
  local keyring="/usr/share/keyrings/microsoft-vscode.gpg"
  local listfile="/etc/apt/sources.list.d/vscode.list"

  log "Info" "Ensuring Microsoft VS Code apt repo is configured..."
  mkdir -p /usr/share/keyrings

  if [[ ! -f "$keyring" ]]; then
    log "Info" "Adding Microsoft keyring: $keyring"
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
      | gpg --dearmor \
      | tee "$keyring" >/dev/null
    chmod 0644 "$keyring"
  else
    log "Debug" "Keyring already present: $keyring"
  fi

  # Ensure the repo line exists and is correct
  local repo_line="deb [arch=amd64 signed-by=${keyring}] https://packages.microsoft.com/repos/code stable main"
  if [[ ! -f "$listfile" ]] || ! grep -Fq "$repo_line" "$listfile"; then
    log "Info" "Writing repo file: $listfile"
    printf '%s\n' "$repo_line" > "$listfile"
    chmod 0644 "$listfile"
  else
    log "Debug" "Repo file already correct: $listfile"
  fi
}

install_vscode() {
  if dpkg -s code >/dev/null 2>&1; then
    log "Info" "VS Code is already installed (dpkg reports 'code')."
    return 0
  fi

  log "Info" "Installing VS Code (package: code)..."
  apt-get update -y
  apt-get install -y code
}

create_portableish_dirs() {
  log "Info" "Configuring 'portable-ish' VS Code profile dirs for user: ${TARGET_USER}"

  local base="${TARGET_HOME}/dev/envs/vscode"
  local user_data="${base}/user-data"
  local extensions="${base}/extensions"
  local wrapper="${TARGET_HOME}/.local/bin/code-homedirs"

  # Ensure directories exist and are owned by the user
  install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" "$user_data" "$extensions" "${TARGET_HOME}/.local/bin"

  # Wrapper ensures absolute paths (desktop entries do NOT reliably expand \$HOME)
  cat > "$wrapper" <<EOF
#!/usr/bin/env bash
exec /usr/bin/code --user-data-dir="${user_data}" --extensions-dir="${extensions}" "\$@"
EOF
  chmod 0755 "$wrapper"
  chown "$TARGET_USER:$TARGET_USER" "$wrapper"

  # Desktop entry (user-local)
  local desktop_dir="${TARGET_HOME}/.local/share/applications"
  local desktop_file="${desktop_dir}/code-homedirs.desktop"
  install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" "$desktop_dir"

  cat > "$desktop_file" <<EOF
[Desktop Entry]
Name=VS Code (Home Dirs)
Comment=VS Code with profile/extensions pinned under ${TARGET_HOME}/dev/envs/vscode
Exec=${wrapper} %F
Icon=code
Type=Application
Categories=Development;IDE;
Terminal=false
EOF
  chown "$TARGET_USER:$TARGET_USER" "$desktop_file"
  chmod 0644 "$desktop_file"

  log "Info" "Portable-ish launcher created: ${desktop_file}"
}

write_state() {
  cat > "$STATE_FILE" <<EOF
installed=true
portable_dirs=${PORTABLE_DIRS}
timestamp="$(ts)"
EOF
  chmod 0644 "$STATE_FILE"
  log "Debug" "State updated: $STATE_FILE"
}

main() {
  ensure_root "$@"
  parse_args "$@"

  require_cmd apt-get
  require_cmd curl
  require_cmd gpg

  log "Info" "Starting ${ACTION_NAME} (target user: ${TARGET_USER})"
  install_prereqs
  setup_vscode_repo
  install_vscode

  if [[ "$PORTABLE_DIRS" == "true" ]]; then
    create_portableish_dirs
  else
    log "Info" "Portable-ish dirs not requested; leaving VS Code default profile in /home."
  fi

  write_state
  log "Info" "Done: ${ACTION_NAME}"
}

main "$@"

