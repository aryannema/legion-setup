#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# install-java-linux.sh
#
# Installs Java via apt (stable + idempotent on Ubuntu 24.04):
#   - Default: OpenJDK 21 (recommended baseline)
#   - Optional: OpenJDK 17 as well (--multi)
#
# Prerequisites:
#   - Ubuntu 24.04.x
#   - sudo access
#
# Usage:
#   setup-aryan install-java-linux
#   ./install-java-linux.sh [--multi]
#
# Flags:
#   --multi    Install both OpenJDK 21 and OpenJDK 17
#
# Logging:
#   - Logs to: /var/log/setup-aryan/install-java-linux.log
#   - State to: /var/log/setup-aryan/state-files/install-java-linux.state
# ==============================================================================

ACTION_NAME="install-java-linux"
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

MULTI="false"

usage() {
  cat <<EOF
${ACTION_NAME}

Usage:
  ${ACTION_NAME} [--multi]
  ${ACTION_NAME} --help

Default:
  - Installs OpenJDK 21 (openjdk-21-jdk)

--multi:
  - Installs OpenJDK 21 + OpenJDK 17
  - Switch using: sudo update-alternatives --config java
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --multi) MULTI="true"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown argument: $1 (use --help)" ;;
    esac
  done
}

install_java() {
  log "Info" "Updating apt index..."
  apt-get update -y

  log "Info" "Installing OpenJDK 21..."
  apt-get install -y openjdk-21-jdk

  if [[ "$MULTI" == "true" ]]; then
    log "Info" "Installing OpenJDK 17 (multi mode)..."
    apt-get install -y openjdk-17-jdk
  fi

  log "Info" "Java versions available:"
  java -version 2>&1 | tee -a "$LOG_FILE" >/dev/null || true
}

write_state() {
  cat > "$STATE_FILE" <<EOF
installed=true
multi=${MULTI}
timestamp="$(ts)"
EOF
  chmod 0644 "$STATE_FILE"
  log "Debug" "State updated: $STATE_FILE"
}

main() {
  ensure_root "$@"
  parse_args "$@"

  log "Info" "Starting ${ACTION_NAME}"
  install_java
  write_state
  log "Info" "Done: ${ACTION_NAME}"
  if [[ "$MULTI" == "true" ]]; then
    log "Info" "To switch Java: sudo update-alternatives --config java"
  fi
}

main "$@"

