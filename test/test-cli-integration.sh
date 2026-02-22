#!/usr/bin/env bash
set -euo pipefail

# Source common test framework
source "$(dirname "$0")/lib/common.sh"

section "CLI integration — docker not installed"

# Override 'command' so that 'command -v docker' fails, simulating docker not installed
output=$(bash -c '
  command() {
    if [[ "$1" == "-v" && "$2" == "docker" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command
  bash "'"$CLI"'" --yolo 2>&1
' 2>&1 || true)

assert_contains "Shows error when docker missing" "$output" "Missing required dependencies"
assert_contains "Error uses styled glyph" "$output" "✘"


section "CLI integration — docker not running"

output=$(bash -c '
  docker() {
    case "$1" in
      info) return 1 ;;
      *) return 0 ;;
    esac
  }
  export -f docker
  lsof() { return 1; }
  export -f lsof
  bash "'"$CLI"'" --yolo 2>&1
' 2>&1 || true)

assert_contains "Shows error when docker not running" "$output" "Docker is not running"


section "CLI integration — --strategy with bad name"

output=$(bash -c '
  export HOME="'"$CLI_HOME"'"
  docker() {
    case "$1" in
      info) return 0 ;;
      ps) echo "" ;;
      *) return 1 ;;
    esac
  }
  export -f docker
  lsof() { return 1; }
  export -f lsof
  bash "'"$CLI"'" --yolo --strategy nonexistent 2>&1
' 2>&1 || true)

assert_contains "Bad strategy shows error" "$output" "Unknown strategy: nonexistent"


section "CLI integration — output formatting (no detection)"

output=$(bash -c '
  export HOME="'"$CLI_HOME"'"
  docker() {
    case "$1" in
      info) return 0 ;;
      ps) echo "" ;;
      image) return 1 ;;
      *) return 1 ;;
    esac
  }
  export -f docker
  lsof() { return 1; }
  export -f lsof
  cd "'"$EMPTY_DIR"'"
  echo "99" | bash "'"$CLI"'" --yolo 2>&1
' 2>&1 || true)

assert_contains "Output includes header" "$output" "claude·yolo"
assert_contains "Output includes no-detect warning" "$output" "No environment auto-detected"
assert_contains "Output includes strategy list" "$output" "Select an environment"
assert_contains "Output shows strategy descriptions" "$output" "Ruby (rbenv)"
assert_contains "Output shows android description" "$output" "JDK 17"
assert_contains "Output shows python description" "$output" "Python (pyenv)"
assert_contains "Output shows node description" "$output" "Node.js (nvm)"
assert_contains "Output shows go description" "$output" "Go"


section "CLI integration — invalid menu selection"

output=$(bash -c '
  export HOME="'"$CLI_HOME"'"
  docker() {
    case "$1" in
      info) return 0 ;;
      ps) echo "" ;;
      image) return 1 ;;
      *) return 1 ;;
    esac
  }
  export -f docker
  lsof() { return 1; }
  export -f lsof
  cd "'"$EMPTY_DIR"'"
  echo "abc" | bash "'"$CLI"'" --yolo 2>&1
' 2>&1 || true)

assert_contains "Non-numeric input shows error" "$output" "Invalid selection"


section "CLI integration — out-of-range menu selection"

output=$(bash -c '
  export HOME="'"$CLI_HOME"'"
  docker() {
    case "$1" in
      info) return 0 ;;
      ps) echo "" ;;
      image) return 1 ;;
      *) return 1 ;;
    esac
  }
  export -f docker
  lsof() { return 1; }
  export -f lsof
  cd "'"$EMPTY_DIR"'"
  echo "99" | bash "'"$CLI"'" --yolo 2>&1
' 2>&1 || true)

assert_contains "Out-of-range selection shows error" "$output" "Invalid selection"


section "CLI integration — auto-detect high confidence"

output=$(bash -c '
  export HOME="'"$CLI_HOME"'"
  export GH_TOKEN=test_token_for_ci
  docker() {
    case "$1" in
      info) return 0 ;;
      ps) echo "" ;;
      image)
        shift
        case "$1" in
          inspect) return 0 ;;
          *) return 1 ;;
        esac
        ;;
      inspect) echo "2099-01-01T00:00:00.000Z" ;;
      rm) return 0 ;;
      run) echo "DOCKER_RUN: $*" ; exit 0 ;;
      *) return 1 ;;
    esac
  }
  export -f docker
  lsof() { return 1; }
  export -f lsof
  curl() {
    case "$*" in
      *api.github.com*) echo "200"; return 0 ;;
      *) return 0 ;;
    esac
  }
  export -f curl
  cd "'"$RAILS_DIR"'"
  bash "'"$CLI"'" --yolo --strategy rails 2>&1
' 2>&1 || true)

assert_contains "Shows worktree path" "$output" "Worktree"
assert_contains "Shows escape hatch" "$output" "Ctrl+C to exit"
assert_contains "Shows Launching message" "$output" "Launching Claude Code"
assert_contains "Shows footer" "$output" "└"

########################################
# Tests: CLI integration — --strategy generic
########################################


section "CLI integration — --strategy generic"

output_generic=$(bash -c '
  export HOME="'"$CLI_HOME"'"
  export GH_TOKEN=test_token_for_ci
  docker() {
    case "$1" in
      info) return 0 ;;
      ps) echo "" ;;
      image)
        shift
        case "$1" in
          inspect) return 0 ;;
          *) return 1 ;;
        esac
        ;;
      inspect) echo "2099-01-01T00:00:00.000Z" ;;
      rm) return 0 ;;
      run) echo "DOCKER_RUN: $*" ; exit 0 ;;
      *) return 1 ;;
    esac
  }
  export -f docker
  lsof() { return 1; }
  export -f lsof
  curl() {
    case "$*" in
      *api.github.com*) echo "200"; return 0 ;;
      *) return 0 ;;
    esac
  }
  export -f curl
  cd "'"$EMPTY_DIR"'"
  bash "'"$CLI"'" --yolo --strategy generic 2>&1
' 2>&1 || true)

assert_contains "Generic shows worktree path" "$output_generic" "Worktree"
assert_contains "Generic shows no language runtime" "$output_generic" "Generic"
assert_contains "Generic shows Launching message" "$output_generic" "Launching Claude Code"

########################################
# Tests: Rails strategy — DB_HOST
########################################


print_summary "$(basename "$0" .sh)"