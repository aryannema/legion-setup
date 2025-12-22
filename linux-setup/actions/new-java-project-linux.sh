#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# new-java-project-linux.sh
#
# Prerequisites:
#   - Ubuntu 24.04.x
#   - Java installed (OpenJDK 21 recommended)
#
# Usage:
#   setup-aryan new-java-project-linux --name <project_name> [--dir <base_dir>]
#
# Output:
#   - README.md + Quick Start
#   - project_config.yaml
#   - src/Main.java
#   - scripts/run.sh, scripts/build.sh, scripts/clean.sh
#   - .gitignore
#
# Build strategy:
#   - Uses javac/java directly (no Maven/Gradle dependency)
#
# Logging:
#   - Logs to: /var/log/setup-aryan/new-java-project-linux.log
#   - State to: /var/log/setup-aryan/state-files/new-java-project-linux.state
# ==============================================================================

ACTION_NAME="new-java-project-linux"
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

NAME=""
BASE_DIR="${TARGET_HOME}/dev/projects"

usage() {
  cat <<EOF
${ACTION_NAME}

Usage:
  ${ACTION_NAME} --name <project_name> [--dir <base_dir>]
  ${ACTION_NAME} --help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) NAME="${2:-}"; shift 2 ;;
      --dir)  BASE_DIR="${2:-}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown argument: $1 (use --help)" ;;
    esac
  done

  [[ -n "$NAME" ]] || die "--name is required"
  [[ "$NAME" =~ ^[a-zA-Z0-9._-]+$ ]] || die "Invalid --name '$NAME' (use only letters, digits, dot, underscore, hyphen)"
}

write_if_missing() {
  local path="$1"
  local owner="$2"
  local group="$3"
  local mode="$4"
  local content="$5"

  if [[ -e "$path" ]]; then
    log "Debug" "Exists, not overwriting: $path"
    return 0
  fi

  install -d -m 0755 -o "$owner" -g "$group" "$(dirname "$path")"
  printf '%s' "$content" > "$path"
  chown "$owner:$group" "$path"
  chmod "$mode" "$path"
  log "Info" "Created: $path"
}

main() {
  ensure_root "$@"
  parse_args "$@"

  log "Info" "Starting ${ACTION_NAME} (user=${TARGET_USER}, name=${NAME}, base_dir=${BASE_DIR})"

  install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" "$BASE_DIR"

  local project_dir="${BASE_DIR}/${NAME}"
  local template_version="1.0.0"
  local created_at
  created_at="$(ts)"

  if [[ -e "$project_dir" ]] && [[ -n "$(ls -A "$project_dir" 2>/dev/null || true)" ]]; then
    log "Warning" "Project directory exists and is not empty: $project_dir"
    log "Warning" "Idempotent behavior: will only create missing files (no overwrites)."
  fi

  install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" \
    "$project_dir" \
    "$project_dir/src" \
    "$project_dir/scripts" \
    "$project_dir/build"

  write_if_missing "$project_dir/.gitignore" "$TARGET_USER" "$TARGET_USER" "0644" \
"build/
*.class
.DS_Store
"

  write_if_missing "$project_dir/src/Main.java" "$TARGET_USER" "$TARGET_USER" "0644" \
"public class Main {
    public static void main(String[] args) {
        System.out.println(\"Hello from ${NAME}!\");
    }
}
"

  write_if_missing "$project_dir/scripts/build.sh" "$TARGET_USER" "$TARGET_USER" "0755" \
"#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
scripts/build.sh

Usage:
  ./scripts/build.sh
EOF
}

if [[ \"\${1:-}\" == \"-h\" || \"\${1:-}\" == \"--help\" ]]; then
  usage
  exit 0
fi

mkdir -p build
javac -d build src/Main.java
echo \"Build complete: build/Main.class\"
"

  write_if_missing "$project_dir/scripts/run.sh" "$TARGET_USER" "$TARGET_USER" "0755" \
"#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
scripts/run.sh

Usage:
  ./scripts/run.sh

Builds first, then runs.
EOF
}

if [[ \"\${1:-}\" == \"-h\" || \"\${1:-}\" == \"--help\" ]]; then
  usage
  exit 0
fi

./scripts/build.sh
java -cp build Main
"

  write_if_missing "$project_dir/scripts/clean.sh" "$TARGET_USER" "$TARGET_USER" "0755" \
"#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
scripts/clean.sh

Usage:
  ./scripts/clean.sh
EOF
}

if [[ \"\${1:-}\" == \"-h\" || \"\${1:-}\" == \"--help\" ]]; then
  usage
  exit 0
fi

rm -rf build
echo \"Cleaned build/\"
"

  write_if_missing "$project_dir/project_config.yaml" "$TARGET_USER" "$TARGET_USER" "0644" \
"project:
  name: \"${NAME}\"
  type: \"java\"
  created_at: \"${created_at}\"
  template_version: \"${template_version}\"

java:
  toolchain: \"openjdk\"
  notes:
    - \"This template uses javac/java directly (no Maven/Gradle).\"
"

  write_if_missing "$project_dir/README.md" "$TARGET_USER" "$TARGET_USER" "0644" \
"# ${NAME}

This project was generated by **setup-aryan** on Linux.

## Quick Start (Linux)

\`\`\`bash
./scripts/run.sh
\`\`\`

## What got generated
- \`project_config.yaml\`: toolchain expectations
- \`src/Main.java\`: runnable entrypoint
- \`scripts/build.sh\`, \`scripts/run.sh\`, \`scripts/clean.sh\`

## Requirements
- Java (JDK) installed and \`javac\` available on PATH
"

  cat > "$STATE_FILE" <<EOF
installed=true
project_dir=${project_dir}
timestamp="$(ts)"
EOF
  chmod 0644 "$STATE_FILE"
  log "Info" "Done: ${ACTION_NAME}"
  log "Info" "Created/validated project at: ${project_dir}"
}

main "$@"
