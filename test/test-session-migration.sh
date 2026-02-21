#!/usr/bin/env bash
#
# Tests for migrate_yolo_sessions in claude-yolo
#
# Usage:
#   ./test/test-session-migration.sh
#
# Tests cover: basic no-op, metadata-file path, active-container skip,
# mixed active/inactive, docker inspect fallback, unknown-path warning,
# multiple base dirs, empty-dir cleanup, target conflict, metadata not moved.

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$TEST_DIR")"
CLI="$REPO_DIR/bin/claude-yolo"

TMPDIR_BASE=$(mktemp -d "${TMPDIR:-/tmp}/claude-yolo-migration.XXXXXX")
trap 'rm -rf "$TMPDIR_BASE"' EXIT

########################################
# Source CLI functions (main disabled)
########################################

_tmp_script="$TMPDIR_BASE/claude-yolo-functions.sh"
sed 's/^main "\$@"$/# main "$@"/' "$CLI" > "$_tmp_script"
source "$_tmp_script"

REPO_DIR="$(dirname "$TEST_DIR")"

########################################
# Test framework (overrides CLI's fail/info/etc.)
########################################

_PASS=0
_FAIL=0
_ERRORS=()

pass() {
  _PASS=$((_PASS + 1))
  echo "  ✔ $1"
}

fail() {
  _FAIL=$((_FAIL + 1))
  _ERRORS+=("$1")
  echo "  ✘ $1"
}

assert_eq() {
  local description="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$description"
  else
    fail "$description (expected '$expected', got '$actual')"
  fi
}

assert_contains() {
  local description="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    pass "$description"
  else
    fail "$description (expected to contain '$needle')"
  fi
}

assert_file_exists() {
  local description="$1" path="$2"
  if [[ -f "$path" ]]; then
    pass "$description"
  else
    fail "$description (file not found: $path)"
  fi
}

assert_file_missing() {
  local description="$1" path="$2"
  if [[ ! -f "$path" ]]; then
    pass "$description"
  else
    fail "$description (file should not exist: $path)"
  fi
}

assert_dir_missing() {
  local description="$1" path="$2"
  if [[ ! -d "$path" ]]; then
    pass "$description"
  else
    fail "$description (directory should not exist: $path)"
  fi
}

section() {
  echo ""
  echo "━━━ $1 ━━━"
}

########################################
# Fixture helpers
########################################

make_fake_home() {
  local name="$1"
  local home_dir="$TMPDIR_BASE/home-${name}"
  mkdir -p "$home_dir/.claude/yolo-sessions"
  mkdir -p "$home_dir/.claude/projects"
  echo "$home_dir"
}

make_session_dir() {
  local home_dir="$1" hash="$2" worktree_path="$3"
  local session_dir="${home_dir}/.claude/yolo-sessions/${hash}"
  mkdir -p "$session_dir"
  echo "$worktree_path" > "${session_dir}/.worktree-path"
  echo "$session_dir"
}

add_session_files() {
  local session_dir="$1"
  echo '{"type":"summary"}' > "${session_dir}/aabbccdd-1111-2222-3333-444455556666.jsonl"
  echo '{}' > "${session_dir}/aabbccdd-1111-2222-3333-444455556666-agent.json"
}

########################################
# Test 1: No session dirs — no-op
########################################

section "No session dirs — no-op"

HOME=$(make_fake_home "t1")
export HOME
rmdir "${HOME}/.claude/yolo-sessions"

docker() { return 0; }

migrate_yolo_sessions
pass "migrate_yolo_sessions completes without error when no yolo-sessions dir exists"

########################################
# Test 2: Session with .worktree-path, no running container — migrated
########################################

section "Session with .worktree-path, no running container — migrated"

HOME=$(make_fake_home "t2")
export HOME
T2_HASH=$(path_hash "/Users/testuser/work/myproject")
T2_SESSION=$(make_session_dir "$HOME" "$T2_HASH" "/Users/testuser/work/myproject")
add_session_files "$T2_SESSION"
T2_TARGET="${HOME}/.claude/projects/-Users-testuser-work-myproject"

docker() { return 0; }

migrate_yolo_sessions

assert_file_exists "Session .jsonl moved to target dir" \
  "${T2_TARGET}/aabbccdd-1111-2222-3333-444455556666.jsonl"
assert_file_exists ".json agent file moved to target dir" \
  "${T2_TARGET}/aabbccdd-1111-2222-3333-444455556666-agent.json"
assert_file_missing ".worktree-path is not moved to target dir" \
  "${T2_TARGET}/.worktree-path"
assert_dir_missing "Session dir removed after migration" "$T2_SESSION"

########################################
# Test 3: Running container (docker ps stub returns hit) — session skipped
########################################

section "Running container — docker ps stub returns hit, session skipped"

HOME=$(make_fake_home "t3")
export HOME
T3_HASH=$(path_hash "/Users/testuser/work/active-project")
T3_SESSION=$(make_session_dir "$HOME" "$T3_HASH" "/Users/testuser/work/active-project")
add_session_files "$T3_SESSION"
T3_TARGET="${HOME}/.claude/projects/-Users-testuser-work-active-project"

docker() {
  if [[ "$1" == "ps" && "${2:-}" == "--filter" && "${3:-}" == "name=claude-yolo-${T3_HASH}" ]]; then
    echo "claude-yolo-${T3_HASH}-rails"
    return 0
  fi
  return 0
}

migrate_yolo_sessions

assert_file_missing "Session file NOT moved when container is running" \
  "${T3_TARGET}/aabbccdd-1111-2222-3333-444455556666.jsonl"
assert_file_exists "Session file stays in yolo-sessions dir when container is running" \
  "${T3_SESSION}/aabbccdd-1111-2222-3333-444455556666.jsonl"

########################################
# Test 4: Two sessions — one active (stubbed), one inactive — only inactive migrated
########################################

section "Two session dirs — active skipped, inactive migrated"

HOME=$(make_fake_home "t4")
export HOME
T4_ACTIVE_HASH=$(path_hash "/Users/testuser/work/active")
T4_INACTIVE_HASH=$(path_hash "/Users/testuser/work/inactive")
T4_ACTIVE_SESSION=$(make_session_dir "$HOME" "$T4_ACTIVE_HASH" "/Users/testuser/work/active")
T4_INACTIVE_SESSION=$(make_session_dir "$HOME" "$T4_INACTIVE_HASH" "/Users/testuser/work/inactive")
echo '{"type":"summary"}' > "${T4_ACTIVE_SESSION}/active-session.jsonl"
echo '{"type":"summary"}' > "${T4_INACTIVE_SESSION}/inactive-session.jsonl"

docker() {
  if [[ "$1" == "ps" && "${2:-}" == "--filter" && "${3:-}" == "name=claude-yolo-${T4_ACTIVE_HASH}" ]]; then
    echo "claude-yolo-${T4_ACTIVE_HASH}-rails"
    return 0
  fi
  return 0
}

migrate_yolo_sessions

assert_file_missing "Active session NOT migrated" \
  "${HOME}/.claude/projects/-Users-testuser-work-active/active-session.jsonl"
assert_file_exists "Active session stays in yolo-sessions" \
  "${T4_ACTIVE_SESSION}/active-session.jsonl"
assert_file_exists "Inactive session migrated to projects dir" \
  "${HOME}/.claude/projects/-Users-testuser-work-inactive/inactive-session.jsonl"
assert_dir_missing "Inactive session dir removed" "$T4_INACTIVE_SESSION"

########################################
# Test 5: No .worktree-path — docker inspect fallback succeeds
########################################

section "No .worktree-path — docker inspect fallback succeeds"

HOME=$(make_fake_home "t5")
export HOME
T5_HASH=$(path_hash "/Users/testuser/work/legacy")
T5_SESSION="${HOME}/.claude/yolo-sessions/${T5_HASH}"
mkdir -p "$T5_SESSION"
echo '{"type":"summary"}' > "${T5_SESSION}/legacy-session.jsonl"

docker() {
  case "$1" in
    ps)
      if [[ "${2:-}" == "-a" ]]; then
        echo "claude-yolo-${T5_HASH}-rails"
      fi
      ;;
    inspect)
      echo "/Users/testuser/work/legacy"
      ;;
  esac
  return 0
}

migrate_yolo_sessions

assert_file_exists "Legacy session migrated via docker inspect fallback" \
  "${HOME}/.claude/projects/-Users-testuser-work-legacy/legacy-session.jsonl"

########################################
# Test 6: No .worktree-path, docker inspect returns nothing — warning, session skipped
########################################

section "No .worktree-path, docker inspect empty — warning logged, session skipped"

HOME=$(make_fake_home "t6")
export HOME
T6_HASH=$(path_hash "/Users/testuser/work/orphan")
T6_SESSION="${HOME}/.claude/yolo-sessions/${T6_HASH}"
mkdir -p "$T6_SESSION"
echo '{"type":"summary"}' > "${T6_SESSION}/orphan-session.jsonl"

docker() {
  echo ""
  return 0
}

T6_OUTPUT=$(migrate_yolo_sessions 2>&1)

assert_contains "Warning logged for unknown worktree path" "$T6_OUTPUT" "worktree path unknown"
assert_file_exists "Session file stays when path is unknown" \
  "${T6_SESSION}/orphan-session.jsonl"

########################################
# Test 7: Multiple base dirs — all yolo-sessions globbed
########################################

section "Multiple base dirs — all yolo-sessions dirs are scanned"

HOME=$(make_fake_home "t7")
export HOME
T7_HASH_A=$(path_hash "/Users/testuser/work/proj-a")
T7_HASH_B=$(path_hash "/Users/testuser/work/proj-b")

T7_SESSION_A="${HOME}/.claude/yolo-sessions/${T7_HASH_A}"
mkdir -p "$T7_SESSION_A"
echo "/Users/testuser/work/proj-a" > "${T7_SESSION_A}/.worktree-path"
echo '{"type":"summary"}' > "${T7_SESSION_A}/session-a.jsonl"

T7_SESSION_B="${HOME}/.other/yolo-sessions/${T7_HASH_B}"
mkdir -p "$T7_SESSION_B"
echo "/Users/testuser/work/proj-b" > "${T7_SESSION_B}/.worktree-path"
echo '{"type":"summary"}' > "${T7_SESSION_B}/session-b.jsonl"

docker() { return 0; }

migrate_yolo_sessions

assert_file_exists "Session from ~/.claude migrated" \
  "${HOME}/.claude/projects/-Users-testuser-work-proj-a/session-a.jsonl"
assert_file_exists "Session from ~/.other migrated" \
  "${HOME}/.claude/projects/-Users-testuser-work-proj-b/session-b.jsonl"

########################################
# Test 8: Session dir removed after all files migrated
########################################

section "Session dir removed after migration"

HOME=$(make_fake_home "t8")
export HOME
T8_HASH=$(path_hash "/Users/testuser/work/cleanup")
T8_SESSION=$(make_session_dir "$HOME" "$T8_HASH" "/Users/testuser/work/cleanup")
add_session_files "$T8_SESSION"

docker() { return 0; }

migrate_yolo_sessions

assert_dir_missing "Session dir removed after migration" "$T8_SESSION"

########################################
# Test 9: Existing file in target — overwritten without error
########################################

section "Existing file in target dir — overwritten without error"

HOME=$(make_fake_home "t9")
export HOME
T9_HASH=$(path_hash "/Users/testuser/work/conflict")
T9_SESSION=$(make_session_dir "$HOME" "$T9_HASH" "/Users/testuser/work/conflict")
echo '{"new":"data"}' > "${T9_SESSION}/conflict-session.jsonl"

T9_TARGET="${HOME}/.claude/projects/-Users-testuser-work-conflict"
mkdir -p "$T9_TARGET"
echo '{"stale":"existing"}' > "${T9_TARGET}/conflict-session.jsonl"

docker() { return 0; }

migrate_yolo_sessions

T9_CONTENT=$(cat "${T9_TARGET}/conflict-session.jsonl")
assert_eq "New session content overwrites existing target file" '{"new":"data"}' "$T9_CONTENT"

########################################
# Test 10: .worktree-path not moved to target dir
########################################

section ".worktree-path metadata file not moved to target dir"

HOME=$(make_fake_home "t10")
export HOME
T10_HASH=$(path_hash "/Users/testuser/work/meta-check")
T10_SESSION=$(make_session_dir "$HOME" "$T10_HASH" "/Users/testuser/work/meta-check")
add_session_files "$T10_SESSION"

docker() { return 0; }

migrate_yolo_sessions

T10_TARGET="${HOME}/.claude/projects/-Users-testuser-work-meta-check"

assert_file_missing ".worktree-path not copied to target dir" \
  "${T10_TARGET}/.worktree-path"
assert_file_exists "Session .jsonl was migrated" \
  "${T10_TARGET}/aabbccdd-1111-2222-3333-444455556666.jsonl"

########################################
# Summary
########################################

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Passed: ${_PASS}  Failed: ${_FAIL}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ ${#_ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failures:"
  for err in "${_ERRORS[@]}"; do
    echo "  • $err"
  done
  echo ""
fi

[[ $_FAIL -eq 0 ]]
