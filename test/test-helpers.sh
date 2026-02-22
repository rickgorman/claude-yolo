#!/usr/bin/env bash
set -euo pipefail

# Source common test framework
source "$(dirname "$0")/lib/common.sh"

section "start-chrome.sh arithmetic under set -e"

output=$(bash -c '
  set -euo pipefail
  attempts=0
  attempts=$((attempts + 1))
  echo "survived: $attempts"
' 2>&1)

assert_eq "Arithmetic increment survives set -e" "survived: 1" "$output"

# Verify the script uses safe arithmetic (not ((attempts++)))
chrome_script=$(cat "$REPO_DIR/scripts/start-chrome.sh")
assert_not_contains "start-chrome.sh avoids ((attempts++))" "$chrome_script" '((attempts++))'
assert_contains "start-chrome.sh uses safe arithmetic" "$chrome_script" 'attempts=$((attempts + 1))'

########################################
# Tests: Color suppression when piped
########################################


section "parse_env_file"

ENV_FILE_DIR="$TMPDIR_BASE/env-file-tests"
mkdir -p "$ENV_FILE_DIR"

# GH_TOKEN in .env
echo "GH_TOKEN=ghp_test_from_env_file" > "$ENV_FILE_DIR/.env-gh"
result=$(parse_env_file "$ENV_FILE_DIR/.env-gh") || true
assert_eq "parse_env_file reads GH_TOKEN" "ghp_test_from_env_file" "$result"

# GITHUB_TOKEN in .env
echo "GITHUB_TOKEN=ghp_github_token_value" > "$ENV_FILE_DIR/.env-github"
result=$(parse_env_file "$ENV_FILE_DIR/.env-github") || true
assert_eq "parse_env_file reads GITHUB_TOKEN" "ghp_github_token_value" "$result"

# GH_TOKEN takes priority over GITHUB_TOKEN
cat > "$ENV_FILE_DIR/.env-both" << 'EOF'
GH_TOKEN=ghp_first_wins
GITHUB_TOKEN=ghp_second_loses
EOF
result=$(parse_env_file "$ENV_FILE_DIR/.env-both") || true
assert_eq "parse_env_file prefers GH_TOKEN over GITHUB_TOKEN" "ghp_first_wins" "$result"

# Handles export prefix
echo "export GH_TOKEN=ghp_exported_value" > "$ENV_FILE_DIR/.env-export"
result=$(parse_env_file "$ENV_FILE_DIR/.env-export") || true
assert_eq "parse_env_file handles export prefix" "ghp_exported_value" "$result"

# Handles double-quoted values
echo 'GH_TOKEN="ghp_double_quoted"' > "$ENV_FILE_DIR/.env-dquote"
result=$(parse_env_file "$ENV_FILE_DIR/.env-dquote") || true
assert_eq "parse_env_file strips double quotes" "ghp_double_quoted" "$result"

# Handles single-quoted values
echo "GH_TOKEN='ghp_single_quoted'" > "$ENV_FILE_DIR/.env-squote"
result=$(parse_env_file "$ENV_FILE_DIR/.env-squote") || true
assert_eq "parse_env_file strips single quotes" "ghp_single_quoted" "$result"

# Returns failure for file with no token
echo "OTHER_VAR=something" > "$ENV_FILE_DIR/.env-notoken"
result=$(parse_env_file "$ENV_FILE_DIR/.env-notoken" 2>/dev/null) && status=0 || status=1
assert_eq "parse_env_file fails when no token found" "1" "$status"

# Returns failure for missing file
result=$(parse_env_file "$ENV_FILE_DIR/.env-nonexistent" 2>/dev/null) && status=0 || status=1
assert_eq "parse_env_file fails for missing file" "1" "$status"

########################################
# Tests: find_github_token
########################################


section "find_stopped_container"

# Mock docker to return a stopped container
docker() {
  case "$1" in
    ps) echo "claude-yolo-abcd1234-rails" ;;
    *) return 0 ;;
  esac
}
result=$(find_stopped_container "abcd1234")
assert_eq "find_stopped_container finds matching exited container" "claude-yolo-abcd1234-rails" "$result"

# Mock docker to return nothing
docker() {
  case "$1" in
    ps) echo "" ;;
    *) return 0 ;;
  esac
}
result=$(find_stopped_container "abcd1234" || true)
assert_eq "find_stopped_container returns empty when no match" "" "$result"
unset -f docker

########################################
# Tests: .yolo/strategy override
########################################


section "check_port_in_use"

# Mock lsof to simulate port 3000 in use
lsof() {
  case "$*" in
    *:3000*) return 0 ;;
    *) return 1 ;;
  esac
}

check_port_in_use 3000 && result="in_use" || result="free"
assert_eq "check_port_in_use detects occupied port" "in_use" "$result"

check_port_in_use 4000 && result="in_use" || result="free"
assert_eq "check_port_in_use reports free port" "free" "$result"

unset -f lsof

########################################
# Tests: find_free_port
########################################


section "find_free_port"

# Mock: port 3000 and 4000 in use — should skip +1000, find 3001
lsof() {
  case "$*" in
    *:3000*|*:4000*) return 0 ;;
    *) return 1 ;;
  esac
}

suggested=$(find_free_port 3000)
assert_eq "find_free_port skips +1000 when occupied, finds +1" "3001" "$suggested"

unset -f lsof

# Mock: only base port in use — should prefer +1000
lsof() {
  case "$*" in
    *:3000*) return 0 ;;
    *) return 1 ;;
  esac
}

suggested=$(find_free_port 3000)
assert_eq "find_free_port prefers +1000 when free" "4000" "$suggested"

unset -f lsof

########################################
# Tests: resolve_port_conflicts — no conflicts
########################################


print_summary "$(basename "$0" .sh)"