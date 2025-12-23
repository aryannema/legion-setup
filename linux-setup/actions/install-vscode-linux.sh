#!/usr/bin/env bash
# install-vscode-linux.sh
#
# Prerequisites:
# - Ubuntu 24.04+
# - sudo privileges
# - curl, gpg
#
# Usage:
#   setup-aryan install-vscode-linux [--force] [--help]
#
# Notes:
# - Adds Microsoft apt repo (idempotent)
# - Installs "code" package

set -euo pipefail

ACTION="install-vscode-linux"
VERSION="1.1.0"

LOG_ROOT="/var/log/setup-aryan"
STATE_ROOT="/var/log/setup-aryan/state-files"
LOG_PATH="${LOG_ROOT}/${ACTION}.log"
STATE_PATH="${STATE_ROOT}/${ACTION}.state"

FORCE="false"

usage() {
  cat <<'USAGE'
install-vscode-linux.sh

Prerequisites:
- Ubuntu 24.04+
- sudo privileges
- curl, gpg

Usage:
  setup-aryan install-vscode-linux [--force]
  setup-aryan install-vscode-linux --help

Installs:
- Visual Studio Code (code)
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

main() {
  parse_args "$@"

  local started_at finished_at user host rc status
  started_at="$(date --iso-8601=seconds)"
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

  if command -v code >/dev/null 2>&1 && [[ "${FORCE}" != "true" ]]; then
    log_line "Info" "VS Code already present (code). Use --force to re-run."
    finished_at="$(date --iso-8601=seconds)"
    write_state_kv "skipped" 0 "${started_at}" "${finished_at}" "${user}" "${host}" "${LOG_PATH}" "${VERSION}"
    exit 0
  fi

  log_line "Info" "Installing dependencies"
  sudo apt-get update -y
  sudo apt-get install -y wget gpg apt-transport-https

  log_line "Info" "Configuring Microsoft apt repo (idempotent)"
  sudo mkdir -p /etc/apt/keyrings
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/keyrings/packages.microsoft.gpg >/dev/null

  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
    | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null

  sudo apt-get update -y
  sudo apt-get install -y code

  log_line "Info" "VS Code version: $(code --version 2>/dev/null | head -n 1 || echo unknown)"

  finished_at="$(date --iso-8601=seconds)"
  write_state_kv "${status}" "${rc}" "${started_at}" "${finished_at}" "${user}" "${host}" "${LOG_PATH}" "${VERSION}"
}

main "$@"
