#!/usr/bin/env bash
# new-node-project-linux.sh
#
# Prerequisites:
# - node + pnpm available
#   (Recommended: setup-aryan install-node-toolchain-linux)
#
# Usage:
#   setup-aryan new-node-project-linux --name myapp [--projects-root ~/dev/projects] [--force] [--help]
#
# Notes:
# - This action NEVER "skips" based on the action state file (you can create many projects).
# - It still writes a state file recording the last project created.

set -euo pipefail

ACTION="new-node-project-linux"
VERSION="1.1.0"

LOG_ROOT="/var/log/setup-aryan"
STATE_ROOT="/var/log/setup-aryan/state-files"
LOG_PATH="${LOG_ROOT}/${ACTION}.log"
STATE_PATH="${STATE_ROOT}/${ACTION}.state"

NAME=""
PROJECTS_ROOT="${HOME}/dev/projects"
FORCE="false"

usage() {
  cat <<'USAGE'
new-node-project-linux.sh

Prerequisites:
- node + pnpm available (recommended: setup-aryan install-node-toolchain-linux)

Usage:
  setup-aryan new-node-project-linux --name <project> [--projects-root <dir>] [--force]
  setup-aryan new-node-project-linux --help

Creates:
- src/index.js
- scripts/dev.sh
- scripts/run.sh
- package.json
- README.md
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
  local status="$1" rc="$2" started_at="$3" finished_at="$4" user="$5" host="$6" log_path="$7" version="$8" project_dir="$9"
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
EOF
  sudo mv -f "${tmp}" "${STATE_PATH}"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) NAME="${2:-}"; shift 2 ;;
      --projects-root) PROJECTS_ROOT="${2:-}"; shift 2 ;;
      --force) FORCE="true"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; usage; exit 1 ;;
    esac
  done
  [[ -n "${NAME}" ]] || { echo "ERROR: --name is required" >&2; usage; exit 1; }
}

assert_toolchain() {
  command -v node >/dev/null 2>&1 || { echo "ERROR: node not found" >&2; exit 1; }
  command -v pnpm >/dev/null 2>&1 || { echo "ERROR: pnpm not found" >&2; exit 1; }
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

  mkdir -p "${PROJECTS_ROOT}"
  local project_dir="${PROJECTS_ROOT}/${NAME}"

  log_line "Info" "Creating Node project: ${project_dir} FORCE=${FORCE}"

  mkdir -p "${project_dir}/src" "${project_dir}/scripts"

  if [[ -d "${project_dir}" && "$(ls -A "${project_dir}" 2>/dev/null | wc -l)" -gt 0 && "${FORCE}" != "true" ]]; then
    log_line "Error" "Project directory exists and is not empty: ${project_dir}. Re-run with --force to overwrite scaffold files."
    rc=1
    status="failed"
    finished_at="$(date --iso-8601=seconds)"
    write_state_kv "${status}" "${rc}" "${started_at}" "${finished_at}" "${user}" "${host}" "${LOG_PATH}" "${VERSION}" "${project_dir}"
    exit "${rc}"
  fi

  cat > "${project_dir}/package.json" <<EOF
{
  "name": "${NAME}",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "start": "node src/index.js",
    "dev": "node --watch src/index.js",
    "lint": "echo \\"(add eslint later if needed)\\"",
    "test": "echo \\"(add tests later)\\""
  }
}
EOF

  cat > "${project_dir}/src/index.js" <<EOF
console.log("Hello from ${NAME}!");
console.log("Node:", process.version);
EOF

  cat > "${project_dir}/scripts/dev.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v pnpm >/dev/null 2>&1; then
  echo "ERROR: pnpm not found" >&2
  exit 1
fi

if [[ ! -d node_modules ]]; then
  echo "Installing deps..."
  pnpm install
fi

echo "Starting dev (node --watch)..."
pnpm dev
EOF
  chmod +x "${project_dir}/scripts/dev.sh"

  cat > "${project_dir}/scripts/run.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v pnpm >/dev/null 2>&1; then
  echo "ERROR: pnpm not found" >&2
  exit 1
fi

pnpm start
EOF
  chmod +x "${project_dir}/scripts/run.sh"

  cat > "${project_dir}/README.md" <<EOF
# ${NAME}

Minimal Node.js scaffold created by \`${ACTION}\`.

## Requirements
- Node.js (LTS)
- pnpm (via corepack) — recommended: \`setup-aryan install-node-toolchain-linux\`

## Quick start
Dev:
\`\`\`bash
./scripts/dev.sh
\`\`\`

Run:
\`\`\`bash
./scripts/run.sh
\`\`\`
EOF

  # Best-effort install to create lockfile
  (cd "${project_dir}" && pnpm install >/dev/null 2>&1) || true

  log_line "Info" "Created: ${project_dir}"
  finished_at="$(date --iso-8601=seconds)"
  write_state_kv "${status}" "${rc}" "${started_at}" "${finished_at}" "${user}" "${host}" "${LOG_PATH}" "${VERSION}" "${project_dir}"
}

main "$@"
