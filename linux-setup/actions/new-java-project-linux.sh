#!/usr/bin/env bash
# new-java-project-linux.sh
#
# Prerequisites:
# - java + javac available (recommended: setup-aryan install-java-linux)
#
# Usage:
#   setup-aryan new-java-project-linux --name myjava [--projects-root ~/dev/projects] [--force] [--help]

set -euo pipefail

ACTION="new-java-project-linux"
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
new-java-project-linux.sh

Prerequisites:
- java + javac available (recommended: setup-aryan install-java-linux)

Usage:
  setup-aryan new-java-project-linux --name <project> [--projects-root <dir>] [--force]
  setup-aryan new-java-project-linux --help

Creates:
- src/Main.java
- scripts/build.sh
- scripts/run.sh
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
  command -v java >/dev/null 2>&1 || { echo "ERROR: java not found" >&2; exit 1; }
  command -v javac >/dev/null 2>&1 || { echo "ERROR: javac not found" >&2; exit 1; }
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

  log_line "Info" "Creating Java project: ${project_dir} FORCE=${FORCE}"

  mkdir -p "${project_dir}/src" "${project_dir}/scripts" "${project_dir}/out"

  if [[ -d "${project_dir}" && "$(ls -A "${project_dir}" 2>/dev/null | wc -l)" -gt 0 && "${FORCE}" != "true" ]]; then
    log_line "Error" "Project directory exists and is not empty: ${project_dir}. Re-run with --force."
    rc=1
    status="failed"
    finished_at="$(date --iso-8601=seconds)"
    write_state_kv "${status}" "${rc}" "${started_at}" "${finished_at}" "${user}" "${host}" "${LOG_PATH}" "${VERSION}" "${project_dir}"
    exit "${rc}"
  fi

  cat > "${project_dir}/src/Main.java" <<EOF
public class Main {
    public static void main(String[] args) {
        System.out.println("Hello from ${NAME}!");
        System.out.println("Java: " + System.getProperty("java.version"));
    }
}
EOF

  cat > "${project_dir}/scripts/build.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p out
echo "Compiling..."
javac -d out src/Main.java
echo "Build output -> out/"
EOF
  chmod +x "${project_dir}/scripts/build.sh"

  cat > "${project_dir}/scripts/run.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f out/Main.class ]]; then
  echo "No build found, running build..."
  ./scripts/build.sh
fi

echo "Running..."
java -cp out Main
EOF
  chmod +x "${project_dir}/scripts/run.sh"

  cat > "${project_dir}/README.md" <<EOF
# ${NAME}

Minimal Java scaffold created by \`${ACTION}\`.

## Requirements
- JDK on PATH (java/javac) — recommended: \`setup-aryan install-java-linux\`

## Quick start
Build:
\`\`\`bash
./scripts/build.sh
\`\`\`

Run:
\`\`\`bash
./scripts/run.sh
\`\`\`
EOF

  log_line "Info" "Created: ${project_dir}"
  finished_at="$(date --iso-8601=seconds)"
  write_state_kv "${status}" "${rc}" "${started_at}" "${finished_at}" "${user}" "${host}" "${LOG_PATH}" "${VERSION}" "${project_dir}"
}

main "$@"
