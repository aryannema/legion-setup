#!/usr/bin/env bash
# install-python-toolchain-linux.sh
#
# Purpose:
#   Install & configure Python toolchain on Ubuntu (Miniconda + uv) in a way that:
#   - keeps everything under ~/dev (tools/envs/cache)
#   - avoids /home bloat
#   - is idempotent (safe to run many times)
#
# Installs:
#   - Miniconda (prefix: ~/dev/tools/miniconda3)
#   - uv (Astral)
#
# Configures:
#   - conda envs_dirs: ~/dev/envs/conda
#   - conda pkgs_dirs: ~/dev/cache/conda-pkgs
#   - auto_activate: false  (new canonical key; avoids MultipleKeysError)
#   - removes auto_activate_base from ~/.condarc if present (alias key)
#   - ~/.bashrc: sources conda.sh so `conda activate` works
#   - UV_CACHE_DIR: ~/dev/cache/uv
#
# Logs:
#   - /var/log/setup-aryan/install-python-toolchain-linux.log
# State:
#   - /var/log/setup-aryan/state-files/install-python-toolchain-linux.state

set -euo pipefail

SCRIPT_NAME="install-python-toolchain-linux"
LOG_DIR="/var/log/setup-aryan"
STATE_DIR="/var/log/setup-aryan/state-files"
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}.log"
STATE_FILE="${STATE_DIR}/${SCRIPT_NAME}.state"

# ---------- helpers ----------
IST_TS() {
  TZ="Asia/Kolkata" date '+%d-%m-%Y %H:%M:%S'
}

log() {
  # <timezome dd-mm-yyyy HH:MM:ss> <Error/Warning/Info/Debug> <logline>
  local level="$1"; shift
  local msg="$*"
  local line
  line="$(printf '%s %s %s\n' "$(IST_TS)" "$level" "$msg")"
  echo -e "$line"
  # best-effort append to log file
  if command -v sudo >/dev/null 2>&1; then
    sudo mkdir -p "$LOG_DIR" "$STATE_DIR" >/dev/null 2>&1 || true
    sudo touch "$LOG_FILE" >/dev/null 2>&1 || true
    echo -e "$line" | sudo tee -a "$LOG_FILE" >/dev/null 2>&1 || true
  fi
}

die() {
  log "Error" "$*"
  exit 1
}

usage() {
  cat <<'EOF'
install-python-toolchain-linux.sh

Prerequisites:
  - Ubuntu/Debian with apt available
  - Internet access
  - bash
  - sudo privileges (recommended) to write logs under /var/log/setup-aryan

Usage:
  ./install-python-toolchain-linux.sh [--force] [--help]

Options:
  --force     Re-download and re-run installers where safe (does NOT delete envs)
  -h, --help  Show help

What it does:
  - Creates ~/dev/{tools,envs,cache,repos,tmp}
  - Installs Miniconda to ~/dev/tools/miniconda3 if missing
  - Fixes ~/.condarc alias conflict (removes auto_activate_base if present)
  - Sets conda envs/pkgs dirs under ~/dev and disables auto activation
  - Ensures `conda activate` works by sourcing conda.sh via ~/.bashrc block
  - Installs uv and sets UV_CACHE_DIR under ~/dev/cache/uv via ~/.bashrc block

EOF
}

# Replace or insert a tagged block in a file (idempotent)
upsert_block() {
  local file="$1"
  local begin="$2"
  local end="$3"
  local content="$4"

  touch "$file"

  if grep -qF "$begin" "$file"; then
    awk -v b="$begin" -v e="$end" '
      $0==b {inblk=1; next}
      $0==e {inblk=0; next}
      !inblk {print}
    ' "$file" > "${file}.tmp"
    mv "${file}.tmp" "$file"
  fi

  {
    echo ""
    echo "$begin"
    echo "$content"
    echo "$end"
    echo ""
  } >> "$file"
}

detect_user() {
  if [ "${SUDO_USER:-}" != "" ] && [ "${SUDO_USER:-}" != "root" ]; then
    echo "$SUDO_USER"
    return
  fi
  echo "$(id -un)"
}

home_of_user() {
  local u="$1"
  getent passwd "$u" | cut -d: -f6
}

save_state() {
  local user="$1"
  local home_dir="$2"
  local conda_prefix="$3"
  local uv_cache="$4"
  local status="$5"

  local body
  body="$(cat <<EOF
status=${status}
at=$(IST_TS)
user=${user}
home=${home_dir}
conda_prefix=${conda_prefix}
uv_cache_dir=${uv_cache}
EOF
)"
  if command -v sudo >/dev/null 2>&1; then
    sudo mkdir -p "$STATE_DIR" >/dev/null 2>&1 || true
    echo "$body" | sudo tee "$STATE_FILE" >/dev/null 2>&1 || true
  fi
}

apt_install_if_missing() {
  local pkgs=("$@")
  log "Info" "Ensuring apt prerequisites are installed: ${pkgs[*]}"
  if ! command -v apt-get >/dev/null 2>&1; then
    die "apt-get not found. This script expects Ubuntu/Debian."
  fi
  if [ "$(id -u)" -ne 0 ]; then
    sudo apt-get update -y
    sudo apt-get install -y "${pkgs[@]}"
  else
    apt-get update -y
    apt-get install -y "${pkgs[@]}"
  fi
}

# Run a command as the target user, with strict error handling in the subshell.
run_as_user() {
  local cmd="$1"
  if [ "$(id -u)" -eq 0 ]; then
    sudo -u "$TARGET_USER" bash -lc "set -euo pipefail; ${cmd}"
  else
    bash -lc "set -euo pipefail; ${cmd}"
  fi
}

# ---------- args ----------
FORCE=0
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi
if [ "${1:-}" = "--force" ]; then
  FORCE=1
fi

# ---------- start ----------
log "Info" "=== START ${SCRIPT_NAME} ==="

TARGET_USER="$(detect_user)"
TARGET_HOME="$(home_of_user "$TARGET_USER")"
if [ -z "$TARGET_HOME" ]; then
  die "Could not determine home directory for user: ${TARGET_USER}"
fi

log "Info" "Target user: ${TARGET_USER}"
log "Info" "Target home: ${TARGET_HOME}"

DEV_ROOT="${TARGET_HOME}/dev"
TOOLS_DIR="${DEV_ROOT}/tools"
ENVS_DIR="${DEV_ROOT}/envs"
CACHE_DIR="${DEV_ROOT}/cache"
REPOS_DIR="${DEV_ROOT}/repos"
TMP_DIR="${DEV_ROOT}/tmp"

CONDA_PREFIX="${TOOLS_DIR}/miniconda3"
CONDA_BIN="${CONDA_PREFIX}/bin/conda"

# You want envs/pkgs outside default ~/.conda and conda base tree.
# (Keep them on the same partition as your home/dev for linking behavior.)
CONDA_ENVS_DIR="${ENVS_DIR}/conda"
CONDA_PKGS_DIR="${CACHE_DIR}/conda-pkgs"

UV_CACHE_DIR_PATH="${CACHE_DIR}/uv"

log "Info" "Ensuring ~/dev directory structure exists"
if [ "$(id -u)" -eq 0 ]; then
  sudo -u "$TARGET_USER" bash -lc "mkdir -p '$TOOLS_DIR' '$ENVS_DIR' '$CACHE_DIR' '$REPOS_DIR' '$TMP_DIR' '$CONDA_ENVS_DIR' '$CONDA_PKGS_DIR' '$UV_CACHE_DIR_PATH'"
else
  mkdir -p "$TOOLS_DIR" "$ENVS_DIR" "$CACHE_DIR" "$REPOS_DIR" "$TMP_DIR" "$CONDA_ENVS_DIR" "$CONDA_PKGS_DIR" "$UV_CACHE_DIR_PATH"
fi

apt_install_if_missing ca-certificates curl wget bzip2 xz-utils git grep

# ---------- Miniconda install ----------
if [ -x "$CONDA_BIN" ] && [ $FORCE -eq 0 ]; then
  log "Info" "Miniconda already present: ${CONDA_BIN}"
else
  log "Info" "Installing Miniconda into: ${CONDA_PREFIX}"

  INSTALLER_DIR="${CACHE_DIR}/miniconda-installer"
  INSTALLER_PATH="${INSTALLER_DIR}/Miniconda3-latest-Linux-x86_64.sh"

  if [ "$(id -u)" -eq 0 ]; then
    sudo -u "$TARGET_USER" bash -lc "mkdir -p '$INSTALLER_DIR'"
    sudo -u "$TARGET_USER" bash -lc "curl -fL --retry 3 --retry-delay 2 -o '$INSTALLER_PATH' 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh'"
    sudo -u "$TARGET_USER" bash -lc "bash '$INSTALLER_PATH' -b -p '$CONDA_PREFIX'"
  else
    mkdir -p "$INSTALLER_DIR"
    curl -fL --retry 3 --retry-delay 2 -o "$INSTALLER_PATH" "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
    bash "$INSTALLER_PATH" -b -p "$CONDA_PREFIX"
  fi

  if [ ! -x "$CONDA_BIN" ]; then
    die "Miniconda install completed but conda not found at: ${CONDA_BIN}"
  fi

  log "Info" "Miniconda installed OK: ${CONDA_BIN}"
fi

# ---------- Fix ~/.condarc alias conflict (auto_activate vs auto_activate_base) ----------
CONDARC_PATH="${TARGET_HOME}/.condarc"
log "Info" "Sanitizing ~/.condarc to avoid auto_activate alias conflicts"
if [ "$(id -u)" -eq 0 ]; then
  sudo -u "$TARGET_USER" bash -lc "touch '$CONDARC_PATH'"
  # Remove deprecated alias key if present
  sudo -u "$TARGET_USER" bash -lc "sed -i '/^auto_activate_base:/d' '$CONDARC_PATH' || true"
else
  touch "$CONDARC_PATH"
  sed -i '/^auto_activate_base:/d' "$CONDARC_PATH" || true
fi

# ---------- Conda config (envs/pkgs locations + disable auto activation) ----------
log "Info" "Configuring conda (envs_dirs/pkgs_dirs/auto_activate)"
# IMPORTANT: use double quotes so $PATH expands (grep must remain available)
run_as_user "export PATH=\"${CONDA_PREFIX}/bin:\$PATH\"; \"${CONDA_BIN}\" --version"

# Set canonical key (auto_activate), NOT the alias (auto_activate_base)
run_as_user "export PATH=\"${CONDA_PREFIX}/bin:\$PATH\"; \"${CONDA_BIN}\" config --set auto_activate false"

conda_add_unique() {
  local key="$1"
  local value="$2"

  # Do not use grep -q (can trigger BrokenPipe warnings). Let grep read fully.
  if run_as_user "export PATH=\"${CONDA_PREFIX}/bin:\$PATH\"; \"${CONDA_BIN}\" config --show \"${key}\" | grep -F -- \"${value}\" >/dev/null"; then
    log "Debug" "Conda config already contains ${key}: ${value}"
  else
    log "Info" "Adding conda config ${key}: ${value}"
    run_as_user "export PATH=\"${CONDA_PREFIX}/bin:\$PATH\"; \"${CONDA_BIN}\" config --add \"${key}\" \"${value}\""
  fi
}

conda_add_unique "envs_dirs" "${CONDA_ENVS_DIR}"
conda_add_unique "pkgs_dirs" "${CONDA_PKGS_DIR}"

# ---------- Shell integration (minimal, not full `conda init`) ----------
# Make conda + conda activate usable in interactive bash sessions.
BASHRC_PATH="${TARGET_HOME}/.bashrc"
BLOCK_BEGIN="# >>> aryan-setup conda (miniconda3) >>>"
BLOCK_END="# <<< aryan-setup conda (miniconda3) <<<"

BASHRC_BLOCK_CONTENT="$(cat <<EOF
# Miniconda prefix (installed by ${SCRIPT_NAME})
export ARYAN_CONDA_PREFIX="\$HOME/dev/tools/miniconda3"

# Ensure conda is discoverable for non-interactive commands
export PATH="\$ARYAN_CONDA_PREFIX/bin:\$PATH"

# Enable \`conda activate\` in interactive shells (without full conda init spam)
if [ -f "\$ARYAN_CONDA_PREFIX/etc/profile.d/conda.sh" ]; then
  . "\$ARYAN_CONDA_PREFIX/etc/profile.d/conda.sh"
fi
EOF
)"

log "Info" "Ensuring ~/.bashrc contains a minimal conda activation block"
if [ "$(id -u)" -eq 0 ]; then
  sudo -u "$TARGET_USER" bash -lc "touch '$BASHRC_PATH'"
  TMP_CONTENT="${TMP_DIR}/.conda_block_content.$$"
  sudo -u "$TARGET_USER" bash -lc "cat > '$TMP_CONTENT' <<'C'
${BASHRC_BLOCK_CONTENT}
C"
  TMP_HELPER="${TMP_DIR}/.upsert_block.$$"
  sudo -u "$TARGET_USER" bash -lc "cat > '$TMP_HELPER' <<'H'
set -euo pipefail
file=\"$1\"
begin=\"$2\"
end=\"$3\"
content_file=\"$4\"

touch \"\$file\"

if grep -qF \"\$begin\" \"\$file\"; then
  awk -v b=\"\$begin\" -v e=\"\$end\" '
    \$0==b {inblk=1; next}
    \$0==e {inblk=0; next}
    !inblk {print}
  ' \"\$file\" > \"\${file}.tmp\"
  mv \"\${file}.tmp\" \"\$file\"
fi

{
  echo \"\"
  echo \"\$begin\"
  cat \"\$content_file\"
  echo \"\$end\"
  echo \"\"
} >> \"\$file\"
H"
  sudo -u "$TARGET_USER" bash -lc "chmod +x '$TMP_HELPER'"
  sudo -u "$TARGET_USER" bash -lc "'$TMP_HELPER' '$BASHRC_PATH' '$BLOCK_BEGIN' '$BLOCK_END' '$TMP_CONTENT'"
  sudo -u "$TARGET_USER" bash -lc "rm -f '$TMP_HELPER' '$TMP_CONTENT'"
else
  upsert_block "$BASHRC_PATH" "$BLOCK_BEGIN" "$BLOCK_END" "$BASHRC_BLOCK_CONTENT"
fi

# ---------- uv install + UV_CACHE_DIR ----------
UV_BLOCK_BEGIN="# >>> aryan-setup uv >>>"
UV_BLOCK_END="# <<< aryan-setup uv <<<"
UV_BASHRC_BLOCK_CONTENT="$(cat <<EOF
# uv cache placement (installed/configured by ${SCRIPT_NAME})
export UV_CACHE_DIR="\$HOME/dev/cache/uv"
EOF
)"

install_uv_if_missing() {
  if run_as_user "command -v uv >/dev/null 2>&1" && [ $FORCE -eq 0 ]; then
    log "Info" "uv already present in PATH"
    return
  fi

  log "Info" "Installing uv (Astral) for user ${TARGET_USER}"
  run_as_user "curl -LsSf https://astral.sh/uv/install.sh | sh"

  if ! run_as_user "command -v uv >/dev/null 2>&1"; then
    die "uv installation ran but uv is still not on PATH. Ensure ~/.local/bin is in PATH."
  fi
  log "Info" "uv installed OK: $(run_as_user "uv --version" || true)"
}

install_uv_if_missing

log "Info" "Ensuring ~/.bashrc contains UV_CACHE_DIR"
if [ "$(id -u)" -eq 0 ]; then
  sudo -u "$TARGET_USER" bash -lc "touch '$BASHRC_PATH'"
  TMP_CONTENT2="${TMP_DIR}/.uv_block_content.$$"
  sudo -u "$TARGET_USER" bash -lc "cat > '$TMP_CONTENT2' <<'C'
${UV_BASHRC_BLOCK_CONTENT}
C"
  TMP_HELPER2="${TMP_DIR}/.upsert_block2.$$"
  sudo -u "$TARGET_USER" bash -lc "cat > '$TMP_HELPER2' <<'H'
set -euo pipefail
file=\"$1\"
begin=\"$2\"
end=\"$3\"
content_file=\"$4\"

touch \"\$file\"

if grep -qF \"\$begin\" \"\$file\"; then
  awk -v b=\"\$begin\" -v e=\"\$end\" '
    \$0==b {inblk=1; next}
    \$0==e {inblk=0; next}
    !inblk {print}
  ' \"\$file\" > \"\${file}.tmp\"
  mv \"\${file}.tmp\" \"\$file\"
fi

{
  echo \"\"
  echo \"\$begin\"
  cat \"\$content_file\"
  echo \"\$end\"
  echo \"\"
} >> \"\$file\"
H"
  sudo -u "$TARGET_USER" bash -lc "chmod +x '$TMP_HELPER2'"
  sudo -u "$TARGET_USER" bash -lc "'$TMP_HELPER2' '$BASHRC_PATH' '$UV_BLOCK_BEGIN' '$UV_BLOCK_END' '$TMP_CONTENT2'"
  sudo -u "$TARGET_USER" bash -lc "rm -f '$TMP_HELPER2' '$TMP_CONTENT2'"
else
  upsert_block "$BASHRC_PATH" "$UV_BLOCK_BEGIN" "$UV_BLOCK_END" "$UV_BASHRC_BLOCK_CONTENT"
fi

# ---------- ownership sanity ----------
log "Info" "Ensuring ownership of ${DEV_ROOT} is ${TARGET_USER}:${TARGET_USER}"
if [ "$(id -u)" -eq 0 ]; then
  chown -R "${TARGET_USER}:${TARGET_USER}" "${DEV_ROOT}" || true
fi

# ---------- verification (fail if conda config still broken) ----------
log "Info" "Verification checks"
run_as_user "export PATH=\"${CONDA_PREFIX}/bin:\$PATH\"; conda --version"
run_as_user "bash -lc 'source ~/.bashrc >/dev/null 2>&1; conda --version'"
run_as_user "bash -lc 'source ~/.bashrc >/dev/null 2>&1; uv --version'"

save_state "$TARGET_USER" "$TARGET_HOME" "$CONDA_PREFIX" "$UV_CACHE_DIR_PATH" "ok"

log "Info" "=== DONE ${SCRIPT_NAME} ==="
log "Info" "Next:"
log "Info" "  1) Run: source ~/.bashrc"
log "Info" "  2) Verify:"
log "Info" "       conda --version"
log "Info" "       conda config --show auto_activate"
log "Info" "       conda info | sed -n '1,120p'"
log "Info" "       uv --version"
exit 0
