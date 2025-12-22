#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# install-node-toolchain-linux.sh
#
# Installs:
#   - nvm (user-owned)
#   - Node LTS via nvm
#   - pnpm via corepack (preferred) OR npm fallback
#   - Pins pnpm store + npm cache under ~/dev/cache to avoid bloat
#
# Prerequisites:
#   - Ubuntu 24.04.x
#   - sudo access
#   - curl
#
# Usage:
#   setup-aryan install-node-toolchain-linux
#   OR:
#     ./install-node-toolchain-linux.sh
#
# Logging:
#   - Logs to: /var/log/setup-aryan/install-node-toolchain-linux.log
#   - State to: /var/log/setup-aryan/state-files/install-node-toolchain-linux.state
# ==============================================================================

ACTION_NAME="install-node-toolchain-linux"
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

DEV_ROOT="${TARGET_HOME}/dev"
CACHE_DIR="${DEV_ROOT}/cache"
PNPM_STORE_DIR="${CACHE_DIR}/pnpm-store"
NPM_CACHE_DIR="${CACHE_DIR}/npm-cache"

usage() {
  cat <<EOF
${ACTION_NAME}

Usage:
  ${ACTION_NAME}
  ${ACTION_NAME} --help

What it does:
  - Installs nvm for ${TARGET_USER}
  - Installs Node LTS
  - Enables corepack and activates pnpm
  - Pins pnpm store to: ${PNPM_STORE_DIR}
  - Pins npm cache to: ${NPM_CACHE_DIR}
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      *) die "Unknown argument: $1 (use --help)" ;;
    esac
  done
}

require_cmd() {
  local c="$1"
  command -v "$c" >/dev/null 2>&1 || die "Missing prerequisite command: $c"
}

ensure_dirs() {
  log "Info" "Ensuring cache dirs exist..."
  install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" "$CACHE_DIR" "$PNPM_STORE_DIR" "$NPM_CACHE_DIR"
}

install_prereqs() {
  log "Info" "Installing prerequisites (if needed)..."
  apt-get update -y
  apt-get install -y --no-install-recommends ca-certificates curl git
}

install_nvm() {
  if [[ -s "${TARGET_HOME}/.nvm/nvm.sh" ]]; then
    log "Info" "nvm already installed."
    return 0
  fi

  log "Info" "Installing nvm for user ${TARGET_USER}..."
  # Use bash -lc so it runs with a login shell environment
  sudo -u "$TARGET_USER" bash -lc 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash' >/dev/null

  [[ -s "${TARGET_HOME}/.nvm/nvm.sh" ]] || die "nvm install failed (missing ~/.nvm/nvm.sh)"
  log "Info" "nvm installed."
}

install_node_lts() {
  log "Info" "Installing Node LTS via nvm (idempotent)..."
  sudo -u "$TARGET_USER" bash -lc '
    set -euo pipefail
    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1091
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    nvm install --lts
    nvm alias default "lts/*"
    node -v
    npm -v
  ' | tee -a "$LOG_FILE" >/dev/null
}

install_pnpm() {
  log "Info" "Enabling corepack and activating pnpm..."
  sudo -u "$TARGET_USER" bash -lc '
    set -euo pipefail
    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1091
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    corepack enable || true
    corepack prepare pnpm@latest --activate || true
    if ! command -v pnpm >/dev/null 2>&1; then
      npm install -g pnpm
    fi
    pnpm -v
  ' | tee -a "$LOG_FILE" >/dev/null
}

configure_stores() {
  log "Info" "Configuring pnpm store + npm cache under ~/dev/cache..."
  sudo -u "$TARGET_USER" bash -lc "
    set -euo pipefail
    export NVM_DIR=\"\$HOME/.nvm\"
    # shellcheck disable=SC1091
    [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
    npm config set cache \"${NPM_CACHE_DIR}\"
    pnpm config set store-dir \"${PNPM_STORE_DIR}\"
  " | tee -a "$LOG_FILE" >/dev/null

  log "Info" "pnpm store pinned to: ${PNPM_STORE_DIR}"
  log "Info" "npm cache pinned to: ${NPM_CACHE_DIR}"
}

write_state() {
  cat > "$STATE_FILE" <<EOF
installed=true
pnpm_store_dir=${PNPM_STORE_DIR}
npm_cache_dir=${NPM_CACHE_DIR}
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
  require_cmd sudo

  log "Info" "Starting ${ACTION_NAME} (target user: ${TARGET_USER})"
  install_prereqs
  ensure_dirs
  install_nvm
  install_node_lts
  install_pnpm
  configure_stores
  write_state
  log "Info" "Done: ${ACTION_NAME}"
  log "Info" "Next (per-project): use pnpm in repos to avoid node_modules bloat."
}

main "$@"

