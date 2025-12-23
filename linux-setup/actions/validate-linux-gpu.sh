#!/usr/bin/env bash
# validate-linux-gpu.sh
#
# Prerequisites:
# - NVIDIA driver installed (nvidia-smi present)
#
# Usage:
#   setup-aryan validate-linux-gpu [--force] [--help]
#
# What it does:
# - Prints nvidia-smi summary
# - Explains why Xorg may appear in nvidia-smi (often normal if PRIME render offload / dGPU present)
# - Records state

set -euo pipefail

ACTION="validate-linux-gpu"
VERSION="1.1.0"

LOG_ROOT="/var/log/setup-aryan"
STATE_ROOT="/var/log/setup-aryan/state-files"
LOG_PATH="${LOG_ROOT}/${ACTION}.log"
STATE_PATH="${STATE_ROOT}/${ACTION}.state"

FORCE="false"

usage() {
  cat <<'USAGE'
validate-linux-gpu.sh

Prerequisites:
- NVIDIA driver installed (nvidia-smi)

Usage:
  setup-aryan validate-linux-gpu [--force]
  setup-aryan validate-linux-gpu --help
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

  if ! command -v nvidia-smi >/dev/null 2>&1; then
    log_line "Error" "nvidia-smi not found. NVIDIA driver not installed or not loaded."
    rc=1
    status="failed"
  else
    log_line "Info" "nvidia-smi output:"
    nvidia-smi | sudo tee -a "${LOG_PATH}" >/dev/null

    log_line "Info" "Why Xorg can show up in nvidia-smi (often normal):"
    log_line "Info" "- On laptops with NVIDIA dGPU present, the driver may keep a minimal context."
    log_line "Info" "- PRIME render offload / on-demand setups can still show Xorg using a few MiB."
    log_line "Info" "- The goal is iGPU-first for desktop; dGPU should not be primary renderer unless explicitly selected."
  fi

  finished_at="$(date --iso-8601=seconds)"
  write_state_kv "${status}" "${rc}" "${started_at}" "${finished_at}" "${user}" "${host}" "${LOG_PATH}" "${VERSION}"
  exit "${rc}"
}

main "$@"
