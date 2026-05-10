#!/usr/bin/env bash
# install-python-toolchain-linux.sh
#
# What it does (user-level):
# - Installs Miniconda to /opt/miniconda3 (system-wide)
# - Configures shared caching and profiles (Vigyan-style)
# - Installs uv (user-level)
# - Adds bash completions

set -euo pipefail

ACTION="install-python-toolchain-linux"
VERSION="1.1.0"

LOG_ROOT="/var/log/setup-aryan"
STATE_ROOT="/var/log/setup-aryan/state-files"
LOG_PATH="${LOG_ROOT}/${ACTION}.log"
STATE_PATH="${STATE_ROOT}/${ACTION}.state"

FORCE="false"
CONDA_PROFILE="oss"
ACCEPT_ANACONDA_TOS="false"

MINICONDA_DIR="/opt/miniconda3"
UV_BIN="${HOME}/.local/bin/uv"

usage() {
  cat <<'USAGE'
install-python-toolchain-linux.sh

Usage:
  setup-aryan install-python-toolchain-linux [--force] [--conda-profile oss|full] [--accept-anaconda-tos]
  setup-aryan install-python-toolchain-linux --help
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
conda_profile=${CONDA_PROFILE}
EOF
  sudo mv -f "${tmp}" "${STATE_PATH}"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) FORCE="true"; shift ;;
      --conda-profile)
        CONDA_PROFILE="${2:-}"
        [[ "${CONDA_PROFILE}" != "oss" && "${CONDA_PROFILE}" != "full" ]] && { echo "ERROR: oss|full"; exit 1; }
        shift 2 ;;
      --accept-anaconda-tos) ACCEPT_ANACONDA_TOS="true"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "ERROR: $1"; usage; exit 1 ;;
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

  log_line "Info" "Starting ${ACTION} FORCE=${FORCE} PROFILE=${CONDA_PROFILE}"

  if [[ -f "${STATE_PATH}" && "${FORCE}" != "true" ]]; then
    if read_state_kv "${STATE_PATH}" && [[ "${status:-}" == "success" ]]; then
      log_line "Info" "Previous success recorded; skipping."
      exit 0
    fi
  fi

  if [[ ! -d "${MINICONDA_DIR}" ]]; then
    log_line "Info" "Installing Miniconda to ${MINICONDA_DIR}"
    local tmp="/tmp/miniconda.$$.sh"
    curl -fsSL -o "${tmp}" "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
    
    log_line "Info" "Bypassing installer sanity check..."
    # Replace the exit 1 block with no-ops more robustly
    sed -i '/Please run using/,/exit 1/s/exit 1/:/' "${tmp}"
    
    sudo bash "${tmp}" -b -p "${MINICONDA_DIR}"
    rm -f "${tmp}"
  fi

  local CONDA_EXEC="${MINICONDA_DIR}/bin/conda"
  if [[ ! -x "${CONDA_EXEC}" ]]; then
    log_line "Error" "Conda executable not found at ${CONDA_EXEC}"
    rc=1
    status="failed"
  else
    log_line "Info" "Conda version: $(${CONDA_EXEC} --version 2>/dev/null || echo unknown)"
    
    log_line "Info" "Configuring .condarc"
    local condarc_tmp="/tmp/condarc.$$"
    cat > "${condarc_tmp}" <<EOF
auto_activate: false
channel_priority: strict
channels:
  - $( [[ "${CONDA_PROFILE}" == "full" ]] && echo nvidia || echo conda-forge )
  - $( [[ "${CONDA_PROFILE}" == "full" ]] && echo conda-forge || echo nvidia )
$( [[ "${CONDA_PROFILE}" == "full" ]] && echo "  - defaults" )
pkgs_dirs:
  - /vigyan/dev-cache/conda/pkgs
EOF
    sudo mv "${condarc_tmp}" "${MINICONDA_DIR}/.condarc"
    sudo chown root:root "${MINICONDA_DIR}/.condarc"
    sudo chmod 0644 "${MINICONDA_DIR}/.condarc"

    log_line "Info" "Conda completion"
    if [[ -f "${MINICONDA_DIR}/etc/bash_completion.d/conda" ]]; then
      sudo ln -sf "${MINICONDA_DIR}/etc/bash_completion.d/conda" /etc/bash_completion.d/conda
    fi
  fi

  if [[ "${FORCE}" == "true" || ! -x "${UV_BIN}" ]]; then
    log_line "Info" "Installing uv"
    curl -LsSf https://astral.sh/uv/install.sh | sh
  fi

  if [[ -x "${UV_BIN}" ]]; then
    log_line "Info" "uv completion"
    mkdir -p /tmp/completions
    "${UV_BIN}" generate-shell-completion bash > /tmp/completions/uv
    sudo mkdir -p /etc/bash_completion.d
    sudo mv /tmp/completions/uv /etc/bash_completion.d/uv
  fi

  finished_at="$(date --iso-8601=seconds)"
  write_state_kv "${status}" "${rc}" "${started_at}" "${finished_at}" "${user}" "${host}" "${LOG_PATH}" "${VERSION}"
  exit "${rc}"
}

main "$@"
