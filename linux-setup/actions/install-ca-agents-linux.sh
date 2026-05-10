#!/usr/bin/env bash
# install-ca-agents-linux.sh
#
# Prerequisites:
# - setup-vigyan-scaffold-linux (for env vars)
# - install-node-toolchain-linux (for pnpm)
# - install-python-toolchain-linux (for uv)
#
# Usage:
#   setup-aryan install-ca-agents-linux [--force] [--help]
#
# What it does:
# - Installs AI agents (claude, gemini, etc.) using pnpm/uv.
# - Ensures they use content-addressable storage (via /vigyan).
#
# Logs:  /var/log/setup-aryan/install-ca-agents-linux.log
# State: /var/log/setup-aryan/state-files/install-ca-agents-linux.state

set -euo pipefail

ACTION="install-ca-agents-linux"
VERSION="1.0.0"

LOG_ROOT="/var/log/setup-aryan"
STATE_ROOT="/var/log/setup-aryan/state-files"
LOG_PATH="${LOG_ROOT}/${ACTION}.log"
STATE_PATH="${STATE_ROOT}/${ACTION}.state"

FORCE="false"

usage() {
  cat <<'USAGE'
install-ca-agents-linux.sh

Installs AI agents using content-addressable tools (pnpm, uv).

Usage:
  setup-aryan install-ca-agents-linux [--force]
  setup-aryan install-ca-agents-linux --help

Agents:
- @anthropic-ai/claude-code (pnpm)
- @google/gemini-cli (pnpm)
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

  log_line "Info" "Starting ${ACTION} FORCE=${FORCE}"

  if [[ -f "${STATE_PATH}" && "${FORCE}" != "true" ]]; then
    if read_state_kv "${STATE_PATH}" && [[ "${status:-}" == "success" ]]; then
      log_line "Info" "Previous success recorded; skipping."
      exit 0
    fi
  fi

  # Ensure env vars are loaded for this session if not already
  [[ -z "${PNPM_HOME:-}" ]] && [[ -f /etc/profile.d/vigyan-env.sh ]] && . /etc/profile.d/vigyan-env.sh

  # 1) Node agents via pnpm global
  if command -v pnpm >/dev/null 2>&1; then
    log_line "Info" "Installing Node-based agents via pnpm global..."
    # pnpm will use PNPM_STORE_PATH from vigyan-env.sh
    pnpm add -g @anthropic-ai/claude-code @google/gemini-cli || {
      log_line "Warning" "pnpm agents install failed. Check logs."
    }
  else
    log_line "Error" "pnpm not found. Run: setup-aryan install-node-toolchain-linux"
    rc=1
    status="failed"
  fi

  # 2) Python agents via uv tool install
  UV_CMD=""
  if command -v uv >/dev/null 2>&1; then
    UV_CMD="uv"
  elif [[ -x "${HOME}/.local/bin/uv" ]]; then
    UV_CMD="${HOME}/.local/bin/uv"
  fi

  if [[ -n "${UV_CMD}" ]]; then
    log_line "Info" "Installing Python-based agents via uv tool..."
    # Add any specific python agents here if needed
    # Example: ${UV_CMD} tool install some-agent
    log_line "Info" "uv tools ready."
  else
    log_line "Error" "uv not found. Run: setup-aryan install-python-toolchain-linux"
    rc=1
    status="failed"
  fi

  finished_at="$(date --iso-8601=seconds)"
  write_state_kv "${status}" "${rc}" "${started_at}" "${finished_at}" "${user}" "${host}" "${LOG_PATH}" "${VERSION}"
  exit "${rc}"
}

main "$@"
