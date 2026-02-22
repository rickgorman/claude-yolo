#!/usr/bin/env bash
set -euo pipefail

# Source common test framework
source "$(dirname "$0")/lib/common.sh"

section "Rails strategy — DB_HOST and commands mount"

# Create a mock docker binary that logs args to a file
MOCK_BIN="$TMPDIR_BASE/mock-bin"
DOCKER_LOG="$TMPDIR_BASE/docker-run-args.log"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/docker" << 'MOCKEOF'
#!/usr/bin/env bash
case "$1" in
  info) exit 0 ;;
  ps) echo "" ;;
  image) shift; case "$1" in inspect) exit 0 ;; *) exit 1 ;; esac ;;
  inspect) echo "2099-01-01T00:00:00.000Z" ;;
  rm) exit 0 ;;
  run) echo "$*" > "$DOCKER_LOG"; exit 0 ;;
  *) exit 1 ;;
esac
MOCKEOF
chmod +x "$MOCK_BIN/docker"

# Create a mock curl that handles both GitHub API and CDP checks
cat > "$MOCK_BIN/curl" << 'MOCKEOF'
#!/usr/bin/env bash
case "$*" in
  *api.github.com*) echo "200"; exit 0 ;;
  *) exit 0 ;;
esac
MOCKEOF
chmod +x "$MOCK_BIN/curl"

# Create a mock lsof that always reports no ports in use
cat > "$MOCK_BIN/lsof" << 'MOCKEOF'
#!/usr/bin/env bash
exit 1
MOCKEOF
chmod +x "$MOCK_BIN/lsof"

# Create a mock ps for process name lookups in port conflict resolution
cat > "$MOCK_BIN/ps" << 'MOCKEOF'
#!/usr/bin/env bash
case "$*" in
  *-o*comm*) echo "mock-process" ;;
  *) command ps "$@" ;;
esac
MOCKEOF
chmod +x "$MOCK_BIN/ps"

# Create a mock tmux that always succeeds
cat > "$MOCK_BIN/tmux" << 'MOCKEOF'
#!/usr/bin/env bash
exit 0
MOCKEOF
chmod +x "$MOCK_BIN/tmux"

# Set up fake HOME with commands directory, settings files, and credentials
FAKE_HOME="$TMPDIR_BASE/fake-claude-home"
mkdir -p "$FAKE_HOME/.claude/commands"
echo "test" > "$FAKE_HOME/.claude/commands/test.md"
echo '{}' > "$FAKE_HOME/.claude/settings.json"
echo '{}' > "$FAKE_HOME/.claude/settings.local.json"
echo '{"claudeAiOauth":{"accessToken":"fake-test-token"}}' > "$FAKE_HOME/.claude/.credentials.json"

output=$(cd "$RAILS_DIR" && \
  HOME="$FAKE_HOME" \
  DOCKER_LOG="$DOCKER_LOG" \
  GH_TOKEN="test_token_for_ci" \
  PATH="$MOCK_BIN:$PATH" \
  bash "$CLI" --yolo --strategy rails 2>&1 || true)

docker_args=$(cat "$DOCKER_LOG" 2>/dev/null || echo "")

assert_contains "Rails sets DB_HOST to host.docker.internal" "$docker_args" "DB_HOST=host.docker.internal"
assert_not_contains "Rails does not use DB_HOST=localhost" "$docker_args" "DB_HOST=localhost"
assert_contains "Mounts commands directory read-only" "$docker_args" ".claude/commands:/home/claude/.claude/commands:ro"

########################################
# Tests: Session history persists to host
########################################


section "Session history persists to host"

# .claude should be bind-mounted from host, not a named Docker volume
assert_contains "Bind-mounts host .claude into container" "$docker_args" ".claude:/home/claude/.claude"
assert_not_contains "Does not use named volume for .claude" "$docker_args" "-home:/home/claude/.claude"
assert_contains "Mounts per-project session directory" "$docker_args" "/.claude/projects/"
assert_contains "Session dir targets -workspace" "$docker_args" ":/home/claude/.claude/projects/-workspace"

########################################
# Tests: Settings files mounted read-only
########################################


section "Settings files mounted read-only"

assert_contains "Mounts settings.json read-only" "$docker_args" "settings.json:/home/claude/.claude/settings.json:ro"
assert_contains "Mounts settings.local.json read-only" "$docker_args" "settings.local.json:/home/claude/.claude/settings.local.json:ro"

########################################
# Tests: Auto-updater disabled
########################################


section "Auto-updater disabled"

assert_contains "Docker args include DISABLE_AUTOUPDATER=1" "$docker_args" "DISABLE_AUTOUPDATER=1"

########################################
# Tests: Git worktree mount
########################################


section "Git worktree mount"

# Create a fake worktree: a directory whose .git is a file (not a directory)
WORKTREE_DIR="$TMPDIR_BASE/fake-worktree"
mkdir -p "$WORKTREE_DIR/config"
echo "gem 'rails'" > "$WORKTREE_DIR/Gemfile"
echo "# app" > "$WORKTREE_DIR/config/application.rb"
echo "3.3.0" > "$WORKTREE_DIR/.ruby-version"

# Simulate the .git file that git worktree creates
# Points at a fake parent repo .git/worktrees/<name> path
FAKE_PARENT_GIT="$TMPDIR_BASE/fake-parent-repo/.git"
mkdir -p "$FAKE_PARENT_GIT/worktrees/my-worktree"
echo "gitdir: ${FAKE_PARENT_GIT}/worktrees/my-worktree" > "$WORKTREE_DIR/.git"

WORKTREE_DOCKER_LOG="$TMPDIR_BASE/docker-run-worktree.log"
cat > "$MOCK_BIN/docker" << MOCKEOF
#!/usr/bin/env bash
case "\$1" in
  info) exit 0 ;;
  ps) echo "" ;;
  image) shift; case "\$1" in inspect) exit 0 ;; *) exit 1 ;; esac ;;
  inspect) echo "2099-01-01T00:00:00.000Z" ;;
  rm) exit 0 ;;
  run) echo "\$*" > "$WORKTREE_DOCKER_LOG"; exit 0 ;;
  *) exit 1 ;;
esac
MOCKEOF
chmod +x "$MOCK_BIN/docker"

output=$(cd "$WORKTREE_DIR" && \
  HOME="$FAKE_HOME" \
  GH_TOKEN="test_token_for_ci" \
  PATH="$MOCK_BIN:$PATH" \
  bash "$CLI" --yolo --strategy rails 2>&1 || true)

worktree_docker_args=$(cat "$WORKTREE_DOCKER_LOG" 2>/dev/null || echo "")

# pwd canonicalizes double slashes from $TMPDIR, so resolve the expected path
expected_parent_git=$(cd "$FAKE_PARENT_GIT" && pwd)
assert_contains "Worktree mounts parent .git directory" "$worktree_docker_args" "${expected_parent_git}:${expected_parent_git}"

# Verify a non-worktree project does NOT get the extra mount
NONWT_DOCKER_LOG="$TMPDIR_BASE/docker-run-nonwt.log"
cat > "$MOCK_BIN/docker" << MOCKEOF
#!/usr/bin/env bash
case "\$1" in
  info) exit 0 ;;
  ps) echo "" ;;
  image) shift; case "\$1" in inspect) exit 0 ;; *) exit 1 ;; esac ;;
  inspect) echo "2099-01-01T00:00:00.000Z" ;;
  rm) exit 0 ;;
  run) echo "\$*" > "$NONWT_DOCKER_LOG"; exit 0 ;;
  *) exit 1 ;;
esac
MOCKEOF
chmod +x "$MOCK_BIN/docker"

output=$(cd "$RAILS_DIR" && \
  HOME="$FAKE_HOME" \
  GH_TOKEN="test_token_for_ci" \
  PATH="$MOCK_BIN:$PATH" \
  bash "$CLI" --yolo --strategy rails 2>&1 || true)

nonwt_docker_args=$(cat "$NONWT_DOCKER_LOG" 2>/dev/null || echo "")

assert_not_contains "Non-worktree does not mount parent .git" "$nonwt_docker_args" "fake-parent-repo"


section "\$HOME/.claude.json mounted into container"

CLAUDEJSON_DIR="$TMPDIR_BASE/claudejson-project"
mkdir -p "$CLAUDEJSON_DIR"
touch "$CLAUDEJSON_DIR/Gemfile"

CLAUDEJSON_HOME="$TMPDIR_BASE/claudejson-home"
mkdir -p "$CLAUDEJSON_HOME/.claude"
echo '{"claudeAiOauth":{"accessToken":"cj-token"}}' > "$CLAUDEJSON_HOME/.claude/.credentials.json"
echo '{"hasCompletedOnboarding":true}' > "$CLAUDEJSON_HOME/.claude.json"

CLAUDEJSON_DOCKER_LOG="$TMPDIR_BASE/docker-claudejson.log"

cat > "$MOCK_BIN/docker" << MOCKEOF
#!/usr/bin/env bash
case "\$1" in
  info) exit 0 ;;
  ps) echo "" ;;
  image) shift; case "\$1" in inspect) exit 0 ;; *) exit 1 ;; esac ;;
  inspect) echo "2099-01-01T00:00:00.000Z" ;;
  rm) exit 0 ;;
  run) echo "\$*" > "$CLAUDEJSON_DOCKER_LOG"; exit 0 ;;
  *) exit 1 ;;
esac
MOCKEOF
chmod +x "$MOCK_BIN/docker"

cd "$CLAUDEJSON_DIR" && \
  HOME="$CLAUDEJSON_HOME" \
  GH_TOKEN="test_token_for_ci" \
  PATH="$MOCK_BIN:$PATH" \
  bash "$CLI" --yolo --strategy generic >/dev/null 2>&1 || true

claudejson_docker_args=$(cat "$CLAUDEJSON_DOCKER_LOG" 2>/dev/null || echo "")

assert_contains "Mounts claude.json copy into container" "$claudejson_docker_args" ":/home/claude/.claude.json"

########################################
# Tests: no ~/.claude.json mount when file missing
########################################


section "No ~/.claude.json mount when file missing"

# FAKE_HOME has no .claude.json, so docker_args should not mount it
assert_not_contains "No .claude.json mount without file" "$docker_args" ":/home/claude/.claude.json"

########################################
# Tests: check_port_in_use
########################################


print_summary "$(basename "$0" .sh)"