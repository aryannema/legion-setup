#!/usr/bin/env bash
# stage-aryan-setup.sh
#
# Prerequisites:
# - Ubuntu 24.04+ recommended
# - bash, coreutils
# - sudo privileges (required to write to /opt, /usr/local/bin, /var/log)
#
# Usage:
#   ./linux-setup/stage-aryan-setup.sh [--force] [--target-root /opt/aryan-setup] [--help]
#
# What it does:
# - Stages this repo's linux-setup/bin, linux-setup/actions, linux-setup/completions into TARGET_ROOT (default /opt/aryan-setup)
# - Installs wrapper commands:
#     /usr/local/bin/setup-aryan
#     /usr/local/bin/setup-aryan-log
# - Ensures:
#     /var/log/setup-aryan/
#     /var/log/setup-aryan/state-files/
# - Writes state file (NO JSON):
#     /var/log/setup-aryan/state-files/stage-linux-setup.state

set -euo pipefail

ACTION="stage-linux-setup"
VERSION="1.1.0"

TARGET_ROOT="/opt/aryan-setup"
LOG_ROOT="/var/log/setup-aryan"
STATE_ROOT="/var/log/setup-aryan/state-files"
LOG_PATH="${LOG_ROOT}/${ACTION}.log"
STATE_PATH="${STATE_ROOT}/${ACTION}.state"

FORCE="false"

usage() {
  cat <<'USAGE'
stage-aryan-setup.sh (Linux)

Prerequisites:
- sudo privileges (required)
- Repo cloned locally

Usage:
  ./linux-setup/stage-aryan-setup.sh [--force] [--target-root /opt/aryan-setup]
  ./linux-setup/stage-aryan-setup.sh --help

Options:
  --force                 Re-stage even if previous success is recorded
  --target-root <path>    Stage root (default: /opt/aryan-setup)
  -h, --help              Show this help
USAGE
}

ist_stamp() {
  TZ="Asia/Kolkata" date '+IST %d-%m-%Y %H:%M:%S'
}

log_line() {
  local level="$1"; shift
  local msg="$*"
  mkdir -p "${LOG_ROOT}" >/dev/null 2>&1 || true
  printf '%s %s %s\n' "$(ist_stamp)" "${level}" "${msg}" | tee -a "${LOG_PATH}" >/dev/null
}

need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: This script must run with sudo/root (needs /opt, /usr/local/bin, /var/log)." >&2
    echo "Run: sudo $0 $*" >&2
    exit 1
  fi
}

ensure_dirs() {
  mkdir -p "${TARGET_ROOT}" "${LOG_ROOT}" "${STATE_ROOT}"
}

read_state_kv() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  # shellcheck disable=SC1090
  source <(sed -n 's/^\([a-zA-Z0-9_]\+\)=\(.*\)$/\1="\2"/p' "$path")
}

write_state_kv() {
  local status="$1"
  local rc="$2"
  local started_at="$3"
  local finished_at="$4"
  local user="$5"
  local host="$6"
  local log_path="$7"
  local version="$8"

  local tmp="${STATE_PATH}.tmp"
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
target_root=${TARGET_ROOT}
EOF
  mv -f "${tmp}" "${STATE_PATH}"
}

copy_tree() {
  local src="$1"
  local dst="$2"
  mkdir -p "$dst"
  # Idempotent: overwrite staged contents
  rsync -a --delete "${src}/" "${dst}/"
}

install_wrapper() {
  local name="$1"
  local content="$2"
  local path="/usr/local/bin/${name}"
  local tmp="${path}.tmp"
  printf '%s\n' "${content}" > "${tmp}"
  chmod 0755 "${tmp}"
  mv -f "${tmp}" "${path}"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) FORCE="true"; shift ;;
      --target-root)
        TARGET_ROOT="${2:-}"
        if [[ -z "${TARGET_ROOT}" ]]; then echo "ERROR: --target-root requires a value" >&2; exit 1; fi
        shift 2
        ;;
      -h|--help) usage; exit 0 ;;
      *)
        echo "ERROR: Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

main() {
  parse_args "$@"
  need_root "$@"

  ensure_dirs

  local started_at finished_at user host rc status
  started_at="$(date --iso-8601=seconds)"
  user="$(logname 2>/dev/null || echo "${SUDO_USER:-root}")"
  host="$(hostname)"
  rc=0
  status="success"

  log_line "Info" "Starting ${ACTION} (version=${VERSION})"
  log_line "Info" "TARGET_ROOT=${TARGET_ROOT}"
  log_line "Info" "LOG_ROOT=${LOG_ROOT}"
  log_line "Info" "STATE_ROOT=${STATE_ROOT}"
  log_line "Info" "FORCE=${FORCE}"

  if [[ -f "${STATE_PATH}" && "${FORCE}" != "true" ]]; then
    # If last run succeeded, skip.
    if read_state_kv "${STATE_PATH}" && [[ "${status:-}" == "success" ]]; then
      log_line "Info" "Previous success recorded; skipping. Use --force to re-run."
      finished_at="$(date --iso-8601=seconds)"
      write_state_kv "skipped" 0 "${started_at}" "${finished_at}" "${user}" "${host}" "${LOG_PATH}" "${VERSION}"
      exit 0
    fi
  fi

  local repo_root script_dir src_base
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "${script_dir}/.." && pwd)"
  src_base="${repo_root}/linux-setup"

  if [[ ! -d "${src_base}" ]]; then
    log_line "Error" "Expected linux-setup directory not found at: ${src_base}"
    rc=1
    status="failed"
    finished_at="$(date --iso-8601=seconds)"
    write_state_kv "${status}" "${rc}" "${started_at}" "${finished_at}" "${user}" "${host}" "${LOG_PATH}" "${VERSION}"
    exit "${rc}"
  fi

  log_line "Info" "Staging bin/actions/completions into ${TARGET_ROOT}"
  mkdir -p "${TARGET_ROOT}/bin" "${TARGET_ROOT}/actions" "${TARGET_ROOT}/completions"

  # Use rsync --delete to ensure staged tree matches repo (idempotent).
  if [[ -d "${src_base}/bin" ]]; then
    copy_tree "${src_base}/bin" "${TARGET_ROOT}/bin"
  fi
  if [[ -d "${src_base}/actions" ]]; then
    copy_tree "${src_base}/actions" "${TARGET_ROOT}/actions"
  fi
  if [[ -d "${src_base}/completions" ]]; then
    copy_tree "${src_base}/completions" "${TARGET_ROOT}/completions"
  fi

  # Install wrapper scripts (not symlinks)
  install_wrapper "setup-aryan" "#!/usr/bin/env bash
exec \"${TARGET_ROOT}/bin/setup-aryan\" \"\$@\"
"
  install_wrapper "setup-aryan-log" "#!/usr/bin/env bash
exec \"${TARGET_ROOT}/bin/setup-aryan-log\" \"\$@\"
"

  log_line "Info" "Installed wrappers:"
  log_line "Info" "  /usr/local/bin/setup-aryan"
  log_line "Info" "  /usr/local/bin/setup-aryan-log"
  log_line "Info" "Done. Try: setup-aryan list"

  finished_at="$(date --iso-8601=seconds)"
  write_state_kv "${status}" "${rc}" "${started_at}" "${finished_at}" "${user}" "${host}" "${LOG_PATH}" "${VERSION}"
}

main "$@"
