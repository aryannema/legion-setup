#!/usr/bin/env bash
# new-python-project-linux.sh
#
# Prerequisites:
# - conda available (recommended: setup-aryan install-python-toolchain-linux)
# - uv available (~/.local/bin/uv) (installed by python toolchain action)
#
# Usage:
#   setup-aryan new-python-project-linux --name myproj [--projects-root ~/dev/projects] [--dev-root ~/dev] [--ai] [--tensorflow] [--force]
#   setup-aryan new-python-project-linux --help
#
# Flags:
# - --ai          adds common ML packages
# - --tensorflow  adds tensorflow + creates validate_tf script
# These can co-exist.

set -euo pipefail

ACTION="new-python-project-linux"
VERSION="1.1.0"

LOG_ROOT="/var/log/setup-aryan"
STATE_ROOT="/var/log/setup-aryan/state-files"
LOG_PATH="${LOG_ROOT}/${ACTION}.log"
STATE_PATH="${STATE_ROOT}/${ACTION}.state"

NAME=""
PROJECTS_ROOT="${HOME}/dev/projects"
DEV_ROOT="${HOME}/dev"
FORCE="false"
FLAG_AI="false"
FLAG_TF="false"

usage() {
  cat <<'USAGE'
new-python-project-linux.sh

Prerequisites:
- conda available (recommended: setup-aryan install-python-toolchain-linux)
- uv available (~/.local/bin/uv)

Usage:
  setup-aryan new-python-project-linux --name <project> [--projects-root <dir>] [--dev-root <dir>] [--ai] [--tensorflow] [--force]
  setup-aryan new-python-project-linux --help

Creates:
- src/main.py
- requirements.txt
- project_config.yaml
- .vscode/settings.json
- scripts/dev.sh, scripts/run.sh
- scripts/validate_tf.sh + src/validate_tf.py (if --tensorflow)
USAGE
}

ist_stamp() { TZ="Asia/Kolkata" date '+IST %d-%m-%Y %H:%M:%S'; }

log_line() {
  local level="$1"; shift
  local msg="$*"
  sudo mkdir -p "${LOG_ROOT}" "${STATE_ROOT}" >/dev/null 2>&1 || true
  printf '%s %s %s\n' "$(ist_stamp)" "${level}" "${msg}" | sudo tee -a "${LOG_PATH}" >/dev/null
}

write_state_kv() {
  local status="$1" rc="$2" started_at="$3" finished_at="$4" user="$5" host="$6" log_path="$7" version="$8" project_dir="$9" env_dir="${10}"
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
project=${NAME}
project_dir=${project_dir}
env_dir=${env_dir}
flag_ai_ml=${FLAG_AI}
flag_tensorflow=${FLAG_TF}
EOF
  sudo mv -f "${tmp}" "${STATE_PATH}"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) NAME="${2:-}"; shift 2 ;;
      --projects-root) PROJECTS_ROOT="${2:-}"; shift 2 ;;
      --dev-root) DEV_ROOT="${2:-}"; shift 2 ;;
      --ai) FLAG_AI="true"; shift ;;
      --tensorflow) FLAG_TF="true"; shift ;;
      --force) FORCE="true"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; usage; exit 1 ;;
    esac
  done
  [[ -n "${NAME}" ]] || { echo "ERROR: --name is required" >&2; usage; exit 1; }
}

assert_toolchain() {
  command -v conda >/dev/null 2>&1 || { echo "ERROR: conda not found" >&2; exit 1; }
  if [[ -x "${HOME}/.local/bin/uv" ]]; then
    :
  elif command -v uv >/dev/null 2>&1; then
    :
  else
    echo "ERROR: uv not found (~/.local/bin/uv). Run: setup-aryan install-python-toolchain-linux" >&2
    exit 1
  fi
}

main() {
  parse_args "$@"
  assert_toolchain

  local started_at finished_at user host rc status
  started_at="$(date --iso-8601=seconds)"
  user="$(id -un)"
  host="$(hostname)"
  rc=0
  status="success"

  mkdir -p "${PROJECTS_ROOT}" "${DEV_ROOT}/envs/conda"
  local project_dir="${PROJECTS_ROOT}/${NAME}"
  local env_dir="${DEV_ROOT}/envs/conda/${NAME}"

  log_line "Info" "Creating Python project: ${project_dir} env=${env_dir} AI=${FLAG_AI} TF=${FLAG_TF} FORCE=${FORCE}"

  mkdir -p "${project_dir}/src" "${project_dir}/scripts" "${project_dir}/.vscode"

  if [[ -d "${project_dir}" && "$(ls -A "${project_dir}" 2>/dev/null | wc -l)" -gt 0 && "${FORCE}" != "true" ]]; then
    log_line "Error" "Project directory exists and is not empty: ${project_dir}. Re-run with --force."
    rc=1
    status="failed"
    finished_at="$(date --iso-8601=seconds)"
    write_state_kv "${status}" "${rc}" "${started_at}" "${finished_at}" "${user}" "${host}" "${LOG_PATH}" "${VERSION}" "${project_dir}" "${env_dir}"
    exit "${rc}"
  fi

  # requirements.txt
  {
    echo "pytest"
    echo "ruff"
    if [[ "${FLAG_AI}" == "true" ]]; then
      echo "numpy"
      echo "pandas"
      echo "scikit-learn"
      echo "matplotlib"
    fi
    if [[ "${FLAG_TF}" == "true" ]]; then
      echo "tensorflow"
    fi
  } | awk '!seen[$0]++' > "${project_dir}/requirements.txt"

  cat > "${project_dir}/project_config.yaml" <<EOF
name: ${NAME}
language: python
paths:
  project_root: ${project_dir}
  conda_env_prefix: ${env_dir}
flags:
  ai_ml: ${FLAG_AI}
  tensorflow: ${FLAG_TF}
toolchain:
  conda: true
  uv: true
EOF

  cat > "${project_dir}/.vscode/settings.json" <<EOF
{
  "python.defaultInterpreterPath": "${env_dir}/bin/python",
  "python.terminal.activateEnvironment": true,
  "python.analysis.typeCheckingMode": "basic",
  "python.analysis.diagnosticSeverityOverrides": {
    "reportMissingImports": "warning"
  }
}
EOF

  cat > "${project_dir}/src/main.py" <<EOF
def main() -> None:
    print("Hello from ${NAME}!")

if __name__ == "__main__":
    main()
EOF

  cat > "${project_dir}/scripts/dev.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "\$(dirname "\$0")/.."

# conda must be available in PATH for this shell
if ! command -v conda >/dev/null 2>&1; then
  echo "ERROR: conda not found in PATH" >&2
  exit 1
fi

ENV_DIR="${env_dir}"
if [[ ! -d "\${ENV_DIR}" ]]; then
  echo "Creating conda env at: \${ENV_DIR}"
  conda create -y -p "\${ENV_DIR}" python=3.11
fi

# Activate by sourcing conda hook
CONDA_BASE="\$(conda info --base)"
# shellcheck disable=SC1090
source "\${CONDA_BASE}/etc/profile.d/conda.sh"
conda activate "\${ENV_DIR}"

# Use uv to install deps
if command -v uv >/dev/null 2>&1; then
  uv pip install -r requirements.txt
else
  "\${HOME}/.local/bin/uv" pip install -r requirements.txt
fi

echo ""
echo "Ready."
echo "Run: ./scripts/run.sh"
EOF
  chmod +x "${project_dir}/scripts/dev.sh"

  cat > "${project_dir}/scripts/run.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "\$(dirname "\$0")/.."

CONDA_BASE="\$(conda info --base)"
# shellcheck disable=SC1090
source "\${CONDA_BASE}/etc/profile.d/conda.sh"
conda activate "${env_dir}"

python src/main.py
EOF
  chmod +x "${project_dir}/scripts/run.sh"

  if [[ "${FLAG_TF}" == "true" ]]; then
    cat > "${project_dir}/src/validate_tf.py" <<'EOF'
import os
import time

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "1")

import tensorflow as tf  # noqa: E402


def main() -> None:
    print("TensorFlow:", tf.__version__)
    gpus = tf.config.list_physical_devices("GPU")
    print("GPUs:", gpus)

    # Prevent greedy VRAM allocation (best-effort)
    for g in gpus:
        try:
            tf.config.experimental.set_memory_growth(g, True)
        except Exception as e:
            print("Could not set memory growth:", e)

    a = tf.random.uniform((2048, 2048))
    b = tf.random.uniform((2048, 2048))

    t0 = time.time()
    c = tf.linalg.matmul(a, b)
    _ = c.numpy()
    t1 = time.time()

    print("Matmul OK. Seconds:", round(t1 - t0, 3))
    print("First run can be slower due to CUDA/PTX/XLA warmup.")


if __name__ == "__main__":
    main()
EOF

    cat > "${project_dir}/scripts/validate_tf.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "\$(dirname "\$0")/.."

CONDA_BASE="\$(conda info --base)"
# shellcheck disable=SC1090
source "\${CONDA_BASE}/etc/profile.d/conda.sh"
conda activate "${env_dir}"

python src/validate_tf.py
EOF
    chmod +x "${project_dir}/scripts/validate_tf.sh"
  fi

  cat > "${project_dir}/README.md" <<EOF
# ${NAME}

Scaffold created by \`${ACTION}\` (toolchain: conda + uv).

## Flags
- AI/ML: $( [[ "${FLAG_AI}" == "true" ]] && echo enabled || echo disabled )
- TensorFlow: $( [[ "${FLAG_TF}" == "true" ]] && echo enabled || echo disabled )

## Quick start
Create env + install deps:
\`\`\`bash
./scripts/dev.sh
\`\`\`

Run:
\`\`\`bash
./scripts/run.sh
\`\`\`

## TensorFlow notes (only if enabled)
- First GPU run can be slower due to CUDA/PTX/XLA compilation and cache warm-up.
- If notebooks appear to hang or VRAM spikes, restart the kernel and run validation once.

Validation:
\`\`\`bash
./scripts/validate_tf.sh
\`\`\`
EOF

  log_line "Info" "Created: ${project_dir}"
  finished_at="$(date --iso-8601=seconds)"
  write_state_kv "${status}" "${rc}" "${started_at}" "${finished_at}" "${user}" "${host}" "${LOG_PATH}" "${VERSION}" "${project_dir}" "${env_dir}"
}

main "$@"
