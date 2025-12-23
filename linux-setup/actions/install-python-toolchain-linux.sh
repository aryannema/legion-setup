#!/usr/bin/env bash
# install-python-toolchain-linux.sh
#
# Prerequisites:
# - Ubuntu 24.04+
# - curl, bzip2
#
# Usage:
#   setup-aryan install-python-toolchain-linux [--force] [--help]
#
# What it does (user-level):
# - Installs Miniconda to ~/miniconda3 (idempotent)
# - Ensures conda base init hint (does not auto-edit your shell rc aggressively)
# - Installs uv (user-level) via official installer
#
# Notes:
# - Project envs are created by project generators under:
#     ~/dev/envs/conda/<project>
#
# Logs:  /var/log/setup-aryan/install-python-toolchain-linux.log
# State: /var/log/setup-aryan/state-files/install-python-toolchain-linux.state  (NO JSON)

set -euo pipefail

ACTION="install-python-toolchain-linux"
VERSION="1.1.0"

LOG_ROOT="/var/log/setup-aryan"
STATE_ROOT="/var/log/setup-aryan/state-files"
LOG_PATH="${LOG_ROOT}/${ACTION}.log"
STATE_PATH="${STATE_ROOT}/${ACTION}.state"

FORCE="false"

MINICONDA_DIR="${HOME}/miniconda3"
UV_BIN="${HOME}/.local/bin/uv"

usage() {
  cat <<'USAGE'
install-python-toolchain-linux.sh

Prerequisites:
- Ubuntu 24.04+
- curl, bzip2
- Internet access (downloads Miniconda + uv)

Usage:
  setup-aryan install-python-toolchain-linux [--force]
  setup-aryan install-python-toolchain-linux --help

Installs:
- Miniconda (~/miniconda3)
- uv (~/.local/bin/uv)
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
miniconda_dir=${MINICONDA_DIR}
uv_path=${UV_BIN}
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
  command -v bzip2 >/dev/null 2>&1 || { echo "ERROR: bzip2 not found" >&2; exit 1; }
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

  if [[ ! -d "${MINICONDA_DIR}" ]]; then
    log_line "Info" "Installing Miniconda to ${MINICONDA_DIR}"
    tmp="/tmp/miniconda.sh.$$"
    curl -fsSL -o "${tmp}" "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
    bash "${tmp}" -b -p "${MINICONDA_DIR}"
    rm -f "${tmp}"
  else
    log_line "Info" "Miniconda already present at ${MINICONDA_DIR}"
  fi

  # Ensure conda binary is visible in this run
  export PATH="${MINICONDA_DIR}/bin:${PATH}"

  if ! command -v conda >/dev/null 2>&1; then
    log_line "Error" "conda not found after install. Check PATH: ${MINICONDA_DIR}/bin"
    rc=1
    status="failed"
  else
    log_line "Info" "conda version: $(conda --version 2>/dev/null || echo unknown)"
    log_line "Info" "Hint: run '${MINICONDA_DIR}/bin/conda init' once for your shell if conda isn't auto-available."
  fi

  # Install uv (user-level) if missing or force
  if [[ "${FORCE}" == "true" || ! -x "${UV_BIN}" ]]; then
    log_line "Info" "Installing uv (user-level) via official installer"
    curl -LsSf https://astral.sh/uv/install.sh | sh
  else
    log_line "Info" "uv already present at ${UV_BIN}"
  fi

  if [[ -x "${UV_BIN}" ]]; then
    log_line "Info" "uv version: $("${UV_BIN}" --version 2>/dev/null || echo unknown)"
  else
    log_line "Warning" "uv not found at expected path: ${UV_BIN}"
  fi

  finished_at="$(date --iso-8601=seconds)"
  write_state_kv "${status}" "${rc}" "${started_at}" "${finished_at}" "${user}" "${host}" "${LOG_PATH}" "${VERSION}"
  exit "${rc}"
}

main "$@"
