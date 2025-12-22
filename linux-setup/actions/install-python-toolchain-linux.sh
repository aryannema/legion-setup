#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# install-python-toolchain-linux.sh
#
# Installs:
#   - Miniconda (user-owned) under ~/dev/tools/miniconda3
#   - Configures conda env/pkgs to live under ~/dev/envs and ~/dev/cache
#   - Installs uv (user-owned) and pins UV cache under ~/dev/cache/uv
#
# Prerequisites:
#   - Ubuntu 24.04.x
#   - sudo access
#   - curl
#
# Usage:
#   setup-aryan install-python-toolchain-linux
#   OR:
#     ./install-python-toolchain-linux.sh
#
# Logging:
#   - Logs to: /var/log/setup-aryan/install-python-toolchain-linux.log
#   - State to: /var/log/setup-aryan/state-files/install-python-toolchain-linux.state
# ==============================================================================

ACTION_NAME="install-python-toolchain-linux"
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

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

DEV_ROOT="${TARGET_HOME}/dev"
TOOLS_DIR="${DEV_ROOT}/tools"
ENVS_DIR="${DEV_ROOT}/envs"
CACHE_DIR="${DEV_ROOT}/cache"

MINICONDA_DIR="${TOOLS_DIR}/miniconda3"
CONDA_ENVS_DIR="${ENVS_DIR}/conda"
CONDA_PKGS_DIR="${CACHE_DIR}/conda-pkgs"

UV_CACHE_DIR_PATH="${CACHE_DIR}/uv"
UV_BIN="${TARGET_HOME}/.local/bin/uv"

usage() {
  cat <<EOF
${ACTION_NAME}

Installs:
  - Miniconda: ${MINICONDA_DIR}
  - Conda envs: ${CONDA_ENVS_DIR}
  - Conda pkgs: ${CONDA_PKGS_DIR}
  - uv cache: ${UV_CACHE_DIR_PATH}

Usage:
  ${ACTION_NAME}
  ${ACTION_NAME} --help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      *) die "Unknown argument: $1 (use --help)" ;;
    esac
  done
}

require_cmd() {
  local c="$1"
  command -v "$c" >/dev/null 2>&1 || die "Missing prerequisite command: $c"
}

ensure_dirs() {
  log "Info" "Ensuring dev directories exist under ${DEV_ROOT}..."
  install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" \
    "$TOOLS_DIR" "$ENVS_DIR" "$CACHE_DIR" \
    "$CONDA_ENVS_DIR" "$CONDA_PKGS_DIR" "$UV_CACHE_DIR_PATH" \
    "${TARGET_HOME}/.local/bin"
}

install_miniconda() {
  if [[ -x "${MINICONDA_DIR}/bin/conda" ]]; then
    log "Info" "Miniconda already installed: ${MINICONDA_DIR}"
    return 0
  fi

  log "Info" "Installing Miniconda into ${MINICONDA_DIR} (user-owned)..."
  local tmp="/tmp/miniconda-installer.sh"
  curl -fsSL "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh" -o "$tmp"
  chmod +x "$tmp"

  # Run installer as TARGET_USER so the whole tree is user-owned
  sudo -u "$TARGET_USER" bash "$tmp" -b -p "$MINICONDA_DIR"
  rm -f "$tmp"

  log "Info" "Miniconda installed."
}

configure_conda() {
  log "Info" "Configuring conda (auto_activate_base=false, envs_dirs/pkgs_dirs moved)..."

  local conda_bin="${MINICONDA_DIR}/bin/conda"
  [[ -x "$conda_bin" ]] || die "conda not found at ${conda_bin}"

  # Make sure conda config writes into the TARGET_USER's home
  sudo -u "$TARGET_USER" "$conda_bin" config --set auto_activate_base false >/dev/null

  # We prefer writing a deterministic ~/.condarc (idempotent)
  local condarc="${TARGET_HOME}/.condarc"
  cat > "$condarc" <<EOF
auto_activate_base: false
envs_dirs:
  - ${CONDA_ENVS_DIR}
pkgs_dirs:
  - ${CONDA_PKGS_DIR}
EOF
  chown "$TARGET_USER:$TARGET_USER" "$condarc"
  chmod 0644 "$condarc"

  log "Info" "Written ${condarc}"
}

install_uv() {
  if [[ -x "$UV_BIN" ]]; then
    log "Info" "uv already installed: ${UV_BIN}"
    return 0
  fi

  log "Info" "Installing uv for user ${TARGET_USER}..."
  # Official installer puts uv into ~/.local/bin
  sudo -u "$TARGET_USER" bash -lc 'curl -LsSf https://astral.sh/uv/install.sh | sh' >/dev/null

  if [[ ! -x "$UV_BIN" ]]; then
    die "uv installation did not produce ${UV_BIN}"
  fi

  log "Info" "uv installed: ${UV_BIN}"
}

configure_uv_env() {
  log "Info" "Configuring UV_CACHE_DIR in ${TARGET_USER}'s shell startup (idempotent block)..."
  local bashrc="${TARGET_HOME}/.bashrc"

  # Remove existing block if present (idempotent)
  if [[ -f "$bashrc" ]]; then
    sed -i '/# >>> aryan-setup env >>>/,/# <<< aryan-setup env <<</d' "$bashrc"
  fi

  cat >> "$bashrc" <<EOF

# >>> aryan-setup env >>>
# Keep uv cache out of random ~/.cache growth
export UV_CACHE_DIR="${UV_CACHE_DIR_PATH}"
# <<< aryan-setup env <<<
EOF

  chown "$TARGET_USER:$TARGET_USER" "$bashrc"
  chmod 0644 "$bashrc"

  log "Info" "UV_CACHE_DIR pinned to: ${UV_CACHE_DIR_PATH}"
  log "Info" "Open a new terminal (or 'source ~/.bashrc') to load UV_CACHE_DIR."
}

write_state() {
  cat > "$STATE_FILE" <<EOF
installed=true
miniconda_dir=${MINICONDA_DIR}
conda_envs_dir=${CONDA_ENVS_DIR}
conda_pkgs_dir=${CONDA_PKGS_DIR}
uv_cache_dir=${UV_CACHE_DIR_PATH}
timestamp="$(ts)"
EOF
  chmod 0644 "$STATE_FILE"
  log "Debug" "State updated: $STATE_FILE"
}

main() {
  ensure_root "$@"
  parse_args "$@"

  require_cmd curl
  require_cmd sed
  require_cmd sudo

  log "Info" "Starting ${ACTION_NAME} (target user: ${TARGET_USER})"
  ensure_dirs
  install_miniconda
  configure_conda
  install_uv
  configure_uv_env
  write_state
  log "Info" "Done: ${ACTION_NAME}"
  log "Info" "Next (per-project): conda create -n <name> python=3.11 && conda activate <name> && uv pip install -r requirements.txt"
}

main "$@"

