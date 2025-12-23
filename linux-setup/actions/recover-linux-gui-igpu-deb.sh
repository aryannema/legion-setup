#!/usr/bin/env bash
# recover-linux-gui-igpu-deb.sh
#
# Prerequisites:
# - Ubuntu 24.04+
# - sudo privileges
#
# Usage:
#   setup-aryan recover-linux-gui-igpu-deb [--force] [--help]
#
# What it does (safe defaults):
# - Prints guidance checks for PRIME on-demand / iGPU-first behavior
# - Does NOT blindly rewrite graphics configs (keeps it low-risk)
# - Records state

set -euo pipefail

ACTION="recover-linux-gui-igpu-deb"
VERSION="1.1.0"

LOG_ROOT="/var/log/setup-aryan"
STATE_ROOT="/var/log/setup-aryan/state-files"
LOG_PATH="${LOG_ROOT}/${ACTION}.log"
STATE_PATH="${STATE_ROOT}/${ACTION}.state"

FORCE="false"

usage() {
  cat <<'USAGE'
recover-linux-gui-igpu-deb.sh

Prerequisites:
- Ubuntu 24.04+
- sudo privileges

Usage:
  setup-aryan recover-linux-gui-igpu-deb [--force]
  setup-aryan recover-linux-gui-igpu-deb --help

This action is intentionally conservative:
- It prints checks and recommended commands for iGPU-first GUI (PRIME on-demand style)
- It does NOT forcefully modify Xorg/Wayland configs without an explicit "dangerous" flag (not implemented here).
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

  log_line "Info" "Checks for iGPU-first GUI (PRIME on-demand goal):"
  log_line "Info" "1) See current session type:"
  log_line "Info" "   echo \$XDG_SESSION_TYPE"
  log_line "Info" "2) Check renderer:"
  log_line "Info" "   glxinfo -B | egrep 'OpenGL vendor|OpenGL renderer'  (install mesa-utils if needed)"
  log_line "Info" "3) If using NVIDIA, verify PRIME render offload variables only for apps that need dGPU:"
  log_line "Info" "   __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia <app>"
  log_line "Info" "4) Xorg showing in nvidia-smi with a few MiB can be normal; focus on default renderer being iGPU."

  finished_at="$(date --iso-8601=seconds)"
  write_state_kv "${status}" "${rc}" "${started_at}" "${finished_at}" "${user}" "${host}" "${LOG_PATH}" "${VERSION}"
}

main "$@"
