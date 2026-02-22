#!/usr/bin/env bash
set -euo pipefail

# Source common test framework
source "$(dirname "$0")/lib/common.sh"

section "find_github_token — env vars"

# GH_TOKEN env var
_GITHUB_TOKEN="" _GITHUB_TOKEN_SOURCE=""
GH_TOKEN="ghp_from_gh_env" GITHUB_TOKEN="" find_github_token "$EMPTY_DIR"
assert_eq "find_github_token picks up GH_TOKEN env var" "ghp_from_gh_env" "$_GITHUB_TOKEN"
assert_eq "find_github_token reports GH_TOKEN source" "GH_TOKEN env var" "$_GITHUB_TOKEN_SOURCE"

# GITHUB_TOKEN env var
_GITHUB_TOKEN="" _GITHUB_TOKEN_SOURCE=""
GH_TOKEN="" GITHUB_TOKEN="ghp_from_github_env" find_github_token "$EMPTY_DIR"
assert_eq "find_github_token picks up GITHUB_TOKEN env var" "ghp_from_github_env" "$_GITHUB_TOKEN"
assert_eq "find_github_token reports GITHUB_TOKEN source" "GITHUB_TOKEN env var" "$_GITHUB_TOKEN_SOURCE"

# GH_TOKEN takes priority over GITHUB_TOKEN
_GITHUB_TOKEN="" _GITHUB_TOKEN_SOURCE=""
GH_TOKEN="ghp_gh_wins" GITHUB_TOKEN="ghp_github_loses" find_github_token "$EMPTY_DIR"
assert_eq "find_github_token prefers GH_TOKEN over GITHUB_TOKEN" "ghp_gh_wins" "$_GITHUB_TOKEN"


section "find_github_token — .env files"

# Project .env file
TOKEN_PROJECT_DIR="$TMPDIR_BASE/token-project"
mkdir -p "$TOKEN_PROJECT_DIR"
echo "GH_TOKEN=ghp_from_project_env" > "$TOKEN_PROJECT_DIR/.env"
_GITHUB_TOKEN="" _GITHUB_TOKEN_SOURCE=""
GH_TOKEN="" GITHUB_TOKEN="" find_github_token "$TOKEN_PROJECT_DIR"
assert_eq "find_github_token reads project .env" "ghp_from_project_env" "$_GITHUB_TOKEN"
assert_contains "find_github_token reports project .env source" "$_GITHUB_TOKEN_SOURCE" ".env"

# Home .env file (when project .env absent)
TOKEN_HOME_DIR="$TMPDIR_BASE/token-home-test"
TOKEN_PROJECT_NOENV="$TMPDIR_BASE/token-noenv-project"
mkdir -p "$TOKEN_HOME_DIR" "$TOKEN_PROJECT_NOENV"
echo "GITHUB_TOKEN=ghp_from_home_env" > "$TOKEN_HOME_DIR/.env"
_GITHUB_TOKEN="" _GITHUB_TOKEN_SOURCE=""
GH_TOKEN="" GITHUB_TOKEN="" HOME="$TOKEN_HOME_DIR" find_github_token "$TOKEN_PROJECT_NOENV"
assert_eq "find_github_token reads ~/.env" "ghp_from_home_env" "$_GITHUB_TOKEN"
assert_contains "find_github_token reports ~/.env source" "$_GITHUB_TOKEN_SOURCE" ".env"

# Env var takes priority over .env file
_GITHUB_TOKEN="" _GITHUB_TOKEN_SOURCE=""
GH_TOKEN="ghp_env_wins" GITHUB_TOKEN="" find_github_token "$TOKEN_PROJECT_DIR"
assert_eq "find_github_token prefers env var over .env file" "ghp_env_wins" "$_GITHUB_TOKEN"
assert_eq "find_github_token reports env var source over .env" "GH_TOKEN env var" "$_GITHUB_TOKEN_SOURCE"


section "find_github_token — gh CLI config"

GH_CONFIG_HOME="$TMPDIR_BASE/gh-config-home"
mkdir -p "$GH_CONFIG_HOME/.config/gh"
cat > "$GH_CONFIG_HOME/.config/gh/hosts.yml" << 'EOF'
github.com:
    user: testuser
    oauth_token: gho_from_gh_config
    git_protocol: https
EOF
_GITHUB_TOKEN="" _GITHUB_TOKEN_SOURCE=""
GH_TOKEN="" GITHUB_TOKEN="" XDG_CONFIG_HOME="" HOME="$GH_CONFIG_HOME" find_github_token "$EMPTY_DIR" || true
assert_eq "find_github_token reads gh CLI config" "gho_from_gh_config" "$_GITHUB_TOKEN"
assert_contains "find_github_token reports gh config source" "$_GITHUB_TOKEN_SOURCE" "hosts.yml"


section "find_github_token — not found"

EMPTY_HOME="$TMPDIR_BASE/empty-home-for-token"
mkdir -p "$EMPTY_HOME/.claude"
echo '{"claudeAiOauth":{"accessToken":"fake-test-token"}}' > "$EMPTY_HOME/.claude/.credentials.json"
_GITHUB_TOKEN="" _GITHUB_TOKEN_SOURCE=""
GH_TOKEN="" GITHUB_TOKEN="" XDG_CONFIG_HOME="" HOME="$EMPTY_HOME" find_github_token "$EMPTY_DIR" && status=0 || status=1
assert_eq "find_github_token returns failure when nothing found" "1" "$status"
assert_eq "find_github_token leaves _GITHUB_TOKEN empty" "" "$_GITHUB_TOKEN"

########################################
# Tests: validate_github_token
########################################


section "validate_github_token"

# Mock curl for validation tests
_orig_curl_path=$(command -v curl 2>/dev/null || true)

# Valid token (200)
curl() {
  echo "200"
  return 0
}
validate_github_token "ghp_valid_token" && status=0 || status=1
assert_eq "validate_github_token succeeds with 200 response" "0" "$status"

# Invalid token (401)
curl() {
  echo "401"
  return 0
}
validate_github_token "ghp_invalid_token" && status=0 || status=1
assert_eq "validate_github_token fails with 401 response" "1" "$status"

# curl failure (network error)
curl() {
  return 1
}
validate_github_token "ghp_network_error" && status=0 || status=1
assert_eq "validate_github_token fails on curl error" "1" "$status"

# Restore real curl
if [[ -n "$_orig_curl_path" ]]; then
  curl() { command curl "$@"; }
fi

########################################
# Tests: GitHub token in docker run args
########################################


section "GitHub token in docker run args"

assert_contains "Docker args include GH_TOKEN" "$docker_args" "GH_TOKEN=test_token_for_ci"
assert_contains "Docker args include GITHUB_TOKEN" "$docker_args" "GITHUB_TOKEN=test_token_for_ci"

########################################
# Tests: GitHub token — missing halts execution
########################################


section "GitHub token — missing halts execution"

output_no_token=$(bash -c '
  export GH_TOKEN="" GITHUB_TOKEN=""
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
  HOME="'"$EMPTY_HOME"'"
  cd "'"$RAILS_DIR"'"
  bash "'"$CLI"'" --yolo --strategy rails 2>&1
' 2>&1 || true)

assert_contains "Missing token shows error" "$output_no_token" "GitHub token not found"
assert_contains "Missing token lists searched locations" "$output_no_token" "GH_TOKEN environment variable"
assert_contains "Missing token suggests fix" "$output_no_token" "export GH_TOKEN="
assert_contains "Missing token shows skip hint" "$output_no_token" "CLAUDE_YOLO_NO_GITHUB"
assert_not_contains "Missing token does not reach docker run" "$output_no_token" "Launching Claude Code"

########################################
# Tests: GitHub token — invalid halts execution
########################################


section "GitHub token — invalid halts execution"

output_bad_token=$(bash -c '
  export HOME="'"$CLI_HOME"'"
  export GH_TOKEN=ghp_definitely_invalid
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
  curl() {
    case "$*" in
      *api.github.com*) echo "401"; return 0 ;;
      *) return 0 ;;
    esac
  }
  export -f curl
  cd "'"$RAILS_DIR"'"
  bash "'"$CLI"'" --yolo --strategy rails 2>&1
' 2>&1 || true)

assert_contains "Invalid token shows error" "$output_bad_token" "GitHub token invalid"
assert_contains "Invalid token shows source" "$output_bad_token" "GH_TOKEN env var"
assert_not_contains "Invalid token does not reach docker run" "$output_bad_token" "Launching Claude Code"

########################################
# Tests: GitHub token output display
########################################


section "GitHub token output display"

assert_contains "Output shows GitHub token success" "$output_no_chrome" "GitHub token"

########################################
# Tests: CLAUDE_YOLO_NO_GITHUB override
########################################


section "CLAUDE_YOLO_NO_GITHUB — skips token check"

output_no_github=$(bash -c '
  export GH_TOKEN="" GITHUB_TOKEN="" CLAUDE_YOLO_NO_GITHUB=1
  docker() {
    case "$1" in
      info) return 0 ;;
      ps) echo "" ;;
      run) echo "DOCKER_RUN: $*" ;;
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
  HOME="'"$EMPTY_HOME"'"
  cd "'"$RAILS_DIR"'"
  bash "'"$CLI"'" --yolo --strategy rails 2>&1
' 2>&1 || true)

assert_contains "Skipped message shown" "$output_no_github" "GitHub token check skipped"
assert_contains "Skipped message mentions env var" "$output_no_github" "CLAUDE_YOLO_NO_GITHUB"
assert_not_contains "No token-not-found error" "$output_no_github" "GitHub token not found"
assert_not_contains "No token-invalid error" "$output_no_github" "GitHub token invalid"


section "CLAUDE_YOLO_NO_GITHUB — no GH_TOKEN in docker args"

assert_not_contains "Docker args omit GH_TOKEN when skipped" "$output_no_github" "GH_TOKEN="


section "CLAUDE_YOLO_NO_GITHUB — unit test on ensure_github_token"

_GITHUB_TOKEN="" _GITHUB_TOKEN_SOURCE=""
skip_output=$(CLAUDE_YOLO_NO_GITHUB=1 GH_TOKEN="" GITHUB_TOKEN="" ensure_github_token "$EMPTY_DIR" 2>&1)
assert_eq "ensure_github_token returns 0 when skipped" "0" "$?"
assert_contains "ensure_github_token prints skip message" "$skip_output" "skipped"
assert_eq "_GITHUB_TOKEN stays empty when skipped" "" "$_GITHUB_TOKEN"

########################################
# Tests: --env flag
########################################


section "check_github_token_scopes — safe token"

_GITHUB_TOKEN_SCOPES="" _BROAD_SCOPES=""
# Mock curl to return safe scopes
curl() {
  echo "HTTP/2 200"
  echo "x-oauth-scopes: repo, read:org"
  echo ""
  return 0
}
check_github_token_scopes "ghp_safe_token" && scope_status=0 || scope_status=1
assert_eq "Safe scopes return success" "0" "$scope_status"
assert_eq "No broad scopes detected" "" "$_BROAD_SCOPES"
unset -f curl


section "check_github_token_scopes — broad token"

_GITHUB_TOKEN_SCOPES="" _BROAD_SCOPES=""
curl() {
  echo "HTTP/2 200"
  echo "x-oauth-scopes: repo, delete_repo, admin:org"
  echo ""
  return 0
}
check_github_token_scopes "ghp_broad_token" && scope_status=0 || scope_status=1
assert_eq "Broad scopes return failure" "1" "$scope_status"
assert_contains "Detects delete_repo" "$_BROAD_SCOPES" "delete_repo"
assert_contains "Detects admin:org" "$_BROAD_SCOPES" "admin:org"
unset -f curl


section "check_github_token_scopes — fine-grained token (no header)"

_GITHUB_TOKEN_SCOPES="" _BROAD_SCOPES=""
curl() {
  echo "HTTP/2 200"
  echo ""
  return 0
}
check_github_token_scopes "github_pat_fine_grained" && scope_status=0 || scope_status=1
assert_eq "Fine-grained token (no X-OAuth-Scopes) returns success" "0" "$scope_status"
unset -f curl


section "check_github_token_scopes — curl failure"

_GITHUB_TOKEN_SCOPES="" _BROAD_SCOPES=""
curl() { return 1; }
check_github_token_scopes "ghp_network_error" && scope_status=0 || scope_status=1
assert_eq "Curl failure returns success (fail-open)" "0" "$scope_status"
unset -f curl


section "GitHub token scope — broad token blocks execution"

output_broad=$(bash -c '
  export HOME="'"$CLI_HOME"'"
  export GH_TOKEN=test_token_for_ci
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
  curl() {
    case "$*" in
      *-o\ /dev/null*) echo "200"; return 0 ;;
      *-I*|*-sI*) echo "HTTP/2 200"; echo "x-oauth-scopes: repo, delete_repo, admin:org"; echo ""; return 0 ;;
      *api.github.com*) echo "200"; return 0 ;;
      *) return 0 ;;
    esac
  }
  export -f curl
  cd "'"$RAILS_DIR"'"
  bash "'"$CLI"'" --yolo --strategy rails 2>&1
' 2>&1 || true)

assert_contains "Broad scope shows warning" "$output_broad" "broad scopes"
assert_contains "Broad scope shows delete_repo" "$output_broad" "delete_repo"
assert_contains "Broad scope blocks execution" "$output_broad" "Refusing to proceed"
assert_contains "Broad scope suggests --trust-github-token" "$output_broad" "--trust-github-token"
assert_not_contains "Broad scope does not reach docker run" "$output_broad" "Launching Claude Code"


section "GitHub token scope — --trust-github-token overrides"

output_trust=$(bash -c '
  export HOME="'"$CLI_HOME"'"
  export GH_TOKEN=test_token_for_ci
  docker() {
    case "$1" in
      info) return 0 ;;
      ps) echo "" ;;
      image) shift; case "$1" in inspect) return 0 ;; *) return 1 ;; esac ;;
      inspect) echo "2099-01-01T00:00:00.000Z" ;;
      rm) return 0 ;;
      run) echo "DOCKER_RUN: $*"; exit 0 ;;
      *) return 1 ;;
    esac
  }
  export -f docker
  lsof() { return 1; }
  export -f lsof
  curl() {
    case "$*" in
      *-o\ /dev/null*) echo "200"; return 0 ;;
      *-I*|*-sI*) echo "HTTP/2 200"; echo "x-oauth-scopes: repo, delete_repo, admin:org"; echo ""; return 0 ;;
      *api.github.com*) echo "200"; return 0 ;;
      *) return 0 ;;
    esac
  }
  export -f curl
  cd "'"$RAILS_DIR"'"
  bash "'"$CLI"'" --yolo --strategy rails --trust-github-token 2>&1
' 2>&1 || true)

assert_contains "Trust flag shows proceeding message" "$output_trust" "Proceeding"
assert_contains "Trust flag reaches launch" "$output_trust" "Launching Claude Code"
assert_not_contains "Trust flag does not block" "$output_trust" "Refusing to proceed"


section "GitHub token scope — safe token passes without flag"

output_safe=$(bash -c '
  export HOME="'"$CLI_HOME"'"
  export GH_TOKEN=test_token_for_ci
  docker() {
    case "$1" in
      info) return 0 ;;
      ps) echo "" ;;
      image) shift; case "$1" in inspect) return 0 ;; *) return 1 ;; esac ;;
      inspect) echo "2099-01-01T00:00:00.000Z" ;;
      rm) return 0 ;;
      run) echo "DOCKER_RUN: $*"; exit 0 ;;
      *) return 1 ;;
    esac
  }
  export -f docker
  lsof() { return 1; }
  export -f lsof
  curl() {
    case "$*" in
      *-o\ /dev/null*) echo "200"; return 0 ;;
      *-I*|*-sI*) echo "HTTP/2 200"; echo "x-oauth-scopes: repo, read:org"; echo ""; return 0 ;;
      *api.github.com*) echo "200"; return 0 ;;
      *) return 0 ;;
    esac
  }
  export -f curl
  cd "'"$RAILS_DIR"'"
  bash "'"$CLI"'" --yolo --strategy rails 2>&1
' 2>&1 || true)

assert_contains "Safe token reaches launch" "$output_safe" "Launching Claude Code"
assert_not_contains "Safe token shows no scope warning" "$output_safe" "broad scopes"

########################################
# Tests: find_stopped_container
########################################


print_summary "$(basename "$0" .sh)"