#!/usr/bin/env bash
# install-node-toolchain-linux.sh
#
# Prerequisites:
# - Ubuntu 24.04+
# - curl, git
#
# Usage:
#   setup-aryan install-node-toolchain-linux [--force] [--help]
#
# What it does (user-level):
# - Installs/updates nvm in ~/.nvm
# - Installs Node LTS via nvm
# - Enables corepack + activates pnpm
#
# Logs:  /var/log/setup-aryan/install-node-toolchain-linux.log
# State: /var/log/setup-aryan/state-files/install-node-toolchain-linux.state   (NO JSON)

set -euo pipefail

ACTION="install-node-toolchain-linux"
VERSION="1.1.0"

LOG_ROOT="/var/log/setup-aryan"
STATE_ROOT="/var/log/setup-aryan/state-files"
LOG_PATH="${LOG_ROOT}/${ACTION}.log"
STATE_PATH="${STATE_ROOT}/${ACTION}.state"

FORCE="false"

usage() {
  cat <<'USAGE'
install-node-toolchain-linux.sh

Prerequisites:
- Ubuntu 24.04+
- curl, git
- Internet access (downloads nvm)

Usage:
  setup-aryan install-node-toolchain-linux [--force]
  setup-aryan install-node-toolchain-linux --help

Installs:
- nvm (user-level)
- Node.js LTS via nvm
- pnpm via corepack
USAGE
}

ist_stamp() { TZ="Asia/Kolkata" date '+IST %d-%m-%Y %H:%M:%S'; }

log_line() {
  local level="$1"; shift
  local msg="$*"
  sudo mkdir -p "${LOG_ROOT}" "${STATE_ROOT}" >/dev/null 2>&1 || true
  printf '%s %s %s\n' "$(ist_stamp)" "${level}" "${msg}" | sudo tee -a "${LOG_PATH}" >/dev/null
}

read_state_kv() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  # shellcheck disable=SC1090
  source <(sudo sed -n 's/^\([a-zA-Z0-9_]\+\)=\(.*\)$/\1="\2"/p' "$path")
}

write_state_kv() {
  local status="$1" rc="$2" started_at="$3" finished_at="$4" user="$5" host="$6" log_path="$7" version="$8"
  local tmp="/tmp/${ACTION}.state.$$"
  cat > "${tmp}" <<EOF
action=${ACTION}
status=${status}
rc=${rc}
started_at=${started_at}
finished_at=${finished_at}
user=${user}
host=${host}
log_path=${log_path}
version=${version}
EOF
  sudo mv -f "${tmp}" "${STATE_PATH}"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) FORCE="true"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; usage; exit 1 ;;
    esac
  done
}

ensure_prereq() {
  command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found" >&2; exit 1; }
  command -v git  >/dev/null 2>&1 || { echo "ERROR: git not found" >&2; exit 1; }
}

load_nvm() {
  export NVM_DIR="${HOME}/.nvm"
  # shellcheck disable=SC1090
  [[ -s "${NVM_DIR}/nvm.sh" ]] && . "${NVM_DIR}/nvm.sh"
}

main() {
  parse_args "$@"
  ensure_prereq

  local started_at finished_at user host rc status
  started_at="$(date --iso-8601=seconds)"
  finished_at=""
  user="$(id -un)"
  host="$(hostname)"
  rc=0
  status="success"

  log_line "Info" "Starting ${ACTION} (version=${VERSION}) FORCE=${FORCE}"

  if [[ -f "${STATE_PATH}" && "${FORCE}" != "true" ]]; then
    if read_state_kv "${STATE_PATH}" && [[ "${status:-}" == "success" ]]; then
      log_line "Info" "Previous success recorded; skipping. Use --force to re-run."
      finished_at="$(date --iso-8601=seconds)"
      write_state_kv "skipped" 0 "${started_at}" "${finished_at}" "${user}" "${host}" "${LOG_PATH}" "${VERSION}"
      exit 0
    fi
  fi

  # Install nvm (idempotent)
  if [[ ! -d "${HOME}/.nvm" ]]; then
    log_line "Info" "Installing nvm (user-level) into ~/.nvm"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  else
    log_line "Info" "nvm already present at ~/.nvm"
  fi

  load_nvm
  if ! command -v nvm >/dev/null 2>&1; then
    log_line "Error" "nvm not available in this shell after install. Open a new terminal or source ~/.nvm/nvm.sh"
    rc=1
    status="failed"
  else
    log_line "Info" "Installing Node LTS via nvm"
    nvm install --lts >/dev/null
    nvm alias default 'lts/*' >/dev/null || true
    nvm use default >/dev/null

    log_line "Info" "Enabling corepack + preparing pnpm"
    corepack enable >/dev/null 2>&1 || true
    corepack prepare pnpm@latest --activate >/dev/null 2>&1 || true

    log_line "Info" "Node: $(node -v 2>/dev/null || echo unknown)"
    log_line "Info" "pnpm: $(pnpm -v 2>/dev/null || echo unknown)"
  fi

  finished_at="$(date --iso-8601=seconds)"
  write_state_kv "${status}" "${rc}" "${started_at}" "${finished_at}" "${user}" "${host}" "${LOG_PATH}" "${VERSION}"
  exit "${rc}"
}

main "$@"
