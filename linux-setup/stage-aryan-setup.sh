#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# stage-aryan-setup.sh
#
# Purpose:
#   Idempotently stage Linux "setup-aryan" framework + action scripts from this
#   repo into system locations:
#     - /usr/local/aryan-setup/
#     - /usr/local/bin/setup-aryan        (symlink)
#     - /usr/local/bin/setup-aryan-log    (symlink)
#     - /etc/bash_completion.d/setup-aryan
#     - /var/log/setup-aryan/ (logs)
#     - /var/log/setup-aryan/state-files/ (state)
#
# Prerequisites:
#   - Ubuntu 24.04+ (or compatible)
#   - bash, coreutils
#   - sudo/root (required)
#
# Usage:
#   sudo bash ./linux-setup/stage-aryan-setup.sh
#   sudo bash ./linux-setup/stage-aryan-setup.sh --help
#
# Notes:
#   - This script is safe to run multiple times (idempotent).
#   - It copies scripts from this repo's linux-setup/{bin,actions,completions}.
# ==============================================================================

SCRIPT_NAME="stage-aryan-setup"
TZ_NAME="Asia/Kolkata"

log_dir="/var/log/setup-aryan"
state_dir="${log_dir}/state-files"
system_root="/usr/local/aryan-setup"
system_bin="${system_root}/bin"
system_actions="${system_root}/actions"
system_completions="${system_root}/completions"
system_log_link="/var/log/aryan-setup"      # compatibility link (optional)
system_state_link="/var/log/aryan-setup/state-files"

print_help() {
  cat <<EOF
${SCRIPT_NAME}

Stages the repo's linux-setup framework into:
  - ${system_root}
  - /usr/local/bin/setup-aryan
  - /usr/local/bin/setup-aryan-log
  - /etc/bash_completion.d/setup-aryan
  - ${log_dir}
  - ${state_dir}

Usage:
  sudo bash ./linux-setup/stage-aryan-setup.sh

EOF
}

ts() { TZ="${TZ_NAME}" date "+%Z %d-%m-%Y %H:%M:%S"; }
log() { echo "$(ts) INFO ${SCRIPT_NAME}: $*"; }
warn() { echo "$(ts) WARNING ${SCRIPT_NAME}: $*" >&2; }
err() { echo "$(ts) ERROR ${SCRIPT_NAME}: $*" >&2; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "Must be run as root (use sudo)."
    exit 1
  fi
}

repo_root() {
  # Resolve repo root robustly: script path -> parent of linux-setup
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "${here}/.." && pwd
}

ensure_dir() {
  local d="$1" mode="${2:-}"
  if [[ ! -d "${d}" ]]; then
    mkdir -p "${d}"
  fi
  if [[ -n "${mode}" ]]; then
    chmod "${mode}" "${d}" || true
  fi
}

copy_tree_idempotent() {
  local src="$1" dst="$2"
  ensure_dir "${dst}"
  if [[ -d "${src}" ]]; then
    # Copy files preserving mode/time; remove deleted files? (NO) — safe staging.
    # We copy/overwrite only.
    cp -a "${src}/." "${dst}/"
  fi
}

safe_symlink() {
  local target="$1" linkpath="$2"
  if [[ -L "${linkpath}" ]]; then
    local cur
    cur="$(readlink -f "${linkpath}" || true)"
    if [[ "${cur}" == "$(readlink -f "${target}")" ]]; then
      return 0
    fi
    rm -f "${linkpath}"
  elif [[ -e "${linkpath}" ]]; then
    warn "Not overwriting existing non-symlink: ${linkpath}"
    return 0
  fi
  ln -s "${target}" "${linkpath}"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print_help
    exit 0
  fi

  require_root

  local root user home
  root="$(repo_root)"

  user="${SUDO_USER:-aryan}"
  home="$(getent passwd "${user}" | cut -d: -f6 || true)"
  if [[ -z "${home}" ]]; then
    home="/home/${user}"
  fi

  log "Repo root: ${root}"
  log "Target user: ${user} (home: ${home})"

  # System directories
  ensure_dir "${system_root}" 0755
  ensure_dir "${system_bin}" 0755
  ensure_dir "${system_actions}" 0755
  ensure_dir "${system_completions}" 0755

  # Log/state directories (make user-owned as requested)
  ensure_dir "${log_dir}" 0750
  ensure_dir "${state_dir}" 0750
  chown -R "${user}:${user}" "${log_dir}" || true

  # Compatibility symlink /var/log/aryan-setup -> /var/log/setup-aryan
  if [[ -e "${system_log_link}" && ! -L "${system_log_link}" ]]; then
    warn "Path exists and is not a symlink; leaving as-is: ${system_log_link}"
  else
    ln -sfn "${log_dir}" "${system_log_link}"
  fi
  if [[ -e "${system_state_link}" && ! -L "${system_state_link}" ]]; then
    warn "Path exists and is not a symlink; leaving as-is: ${system_state_link}"
  else
    ln -sfn "${state_dir}" "${system_state_link}"
  fi

  # Copy staged content from repo
  copy_tree_idempotent "${root}/linux-setup/bin" "${system_bin}"
  copy_tree_idempotent "${root}/linux-setup/actions" "${system_actions}"
  copy_tree_idempotent "${root}/linux-setup/completions" "${system_completions}"

  # Ensure wrappers executable
  if [[ -f "${system_bin}/setup-aryan" ]]; then chmod +x "${system_bin}/setup-aryan" || true; fi
  if [[ -f "${system_bin}/setup-aryan-log" ]]; then chmod +x "${system_bin}/setup-aryan-log" || true; fi
  find "${system_actions}" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

  # Install bash completion
  if [[ -f "${system_completions}/setup-aryan.bash" ]]; then
    ensure_dir "/etc/bash_completion.d" 0755
    cp -a "${system_completions}/setup-aryan.bash" "/etc/bash_completion.d/setup-aryan"
    chmod 0644 "/etc/bash_completion.d/setup-aryan" || true
  else
    warn "Missing completion file: ${system_completions}/setup-aryan.bash"
  fi

  # Symlink wrappers into PATH
  safe_symlink "${system_bin}/setup-aryan" "/usr/local/bin/setup-aryan"
  safe_symlink "${system_bin}/setup-aryan-log" "/usr/local/bin/setup-aryan-log"

  log "Staging complete."
  log "Try:"
  log "  setup-aryan list"
  log "  setup-aryan validate-linux-gpu"
  log "  setup-aryan recover-linux-gui-igpu-deb"
  log "Logs: ${log_dir}"
}

main "$@"
