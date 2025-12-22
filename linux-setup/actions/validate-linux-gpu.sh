#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# validate-linux-gpu.sh
#
# Purpose:
#   Validate iGPU-first behavior + Chrome wrapper setup on Ubuntu hybrid graphics.
#
# Prerequisites:
#   - prime-select (optional)
#   - nvidia-smi (optional)
#   - google-chrome-stable (optional)
#
# Usage:
#   setup-aryan validate-linux-gpu
#   setup-aryan validate-linux-gpu -- --user aryan
# ==============================================================================

TZ_NAME="Asia/Kolkata"
ACTION_NAME="validate-linux-gpu"
TARGET_USER="${SUDO_USER:-aryan}"

ts() { TZ="${TZ_NAME}" date "+%Z %d-%m-%Y %H:%M:%S"; }
log() { echo "$(ts) INFO ${ACTION_NAME}: $*"; }
warn() { echo "$(ts) WARNING ${ACTION_NAME}: $*" >&2; }

print_help() {
  cat <<EOF
${ACTION_NAME}

Usage:
  ${ACTION_NAME}.sh [--user <username>]

Checks:
  - Session type (Wayland/X11)
  - prime-select query (if available)
  - nvidia-smi process list (if available)
  - Chrome iGPU wrapper and desktop entry under user's home

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

TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6 || true)"
if [[ -z "${TARGET_HOME}" ]]; then
  TARGET_HOME="/home/${TARGET_USER}"
fi

need_cmd() { command -v "$1" >/dev/null 2>&1; }

log "Target user: ${TARGET_USER} (home: ${TARGET_HOME})"

log "Session:"
log "  XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unknown}"
log "  WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}"
log "  DISPLAY=${DISPLAY:-}"

if need_cmd prime-select; then
  log "PRIME mode:"
  sudo prime-select query || true
else
  warn "prime-select not found"
fi

if need_cmd nvidia-smi; then
  log "nvidia-smi summary:"
  nvidia-smi || true
  log "nvidia-smi processes (if any):"
  nvidia-smi pmon -c 1 2>/dev/null || true
  log "Tip: If you see gnome-shell, chrome, vscode in nvidia-smi process list while on-demand, something is off."
else
  warn "nvidia-smi not found (driver not installed or not working)"
fi

# Chrome wrapper checks
wrapper="${TARGET_HOME}/.local/bin/chrome-igpu"
desktop="${TARGET_HOME}/.local/share/applications/google-chrome-igpu.desktop"
cache_dir="${TARGET_HOME}/local_chrome_storage/cache"
profile_dir="${TARGET_HOME}/profiles/chrome"

log "Chrome wrapper checks:"
if [[ -f "${wrapper}" ]]; then
  log "  OK: wrapper exists: ${wrapper}"
  log "  wrapper head:"
  head -n 20 "${wrapper}" | sed 's/^/    /'
else
  warn "  MISSING: wrapper not found: ${wrapper}"
fi

if [[ -f "${desktop}" ]]; then
  log "  OK: desktop entry exists: ${desktop}"
  log "  Exec line:"
  grep -E '^Exec=' "${desktop}" | sed 's/^/    /' || true
  log "  Name line:"
  grep -E '^Name=' "${desktop}" | sed 's/^/    /' || true
else
  warn "  MISSING: desktop entry not found: ${desktop}"
fi

if [[ -d "${cache_dir}" ]]; then
  log "  OK: cache dir exists: ${cache_dir}"
else
  warn "  MISSING: cache dir not found: ${cache_dir}"
fi

if [[ -d "${profile_dir}" ]]; then
  log "  OK: profile dir exists: ${profile_dir}"
else
  warn "  MISSING: profile dir not found: ${profile_dir}"
fi

log "Done."
