#!/usr/bin/env bash
set -euo pipefail

# Source common test framework
source "$(dirname "$0")/lib/common.sh"

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

########################################
# Tests: start-chrome.sh arithmetic safety
########################################


section "extract_git_user_config — no config found"

GIT_CONFIG_NONE="$TMPDIR_BASE/no-git-config"
mkdir -p "$GIT_CONFIG_NONE"
result=$(HOME="$GIT_CONFIG_NONE" extract_git_user_config 2>&1 || echo "")
assert_not_contains "No config: returns empty name" "$result" "user.name"
assert_not_contains "No config: returns empty email" "$result" "user.email"


section "extract_git_user_config — both found in .gitconfig"

GIT_CONFIG_BOTH="$TMPDIR_BASE/git-config-both"
mkdir -p "$GIT_CONFIG_BOTH"
cat > "$GIT_CONFIG_BOTH/.gitconfig" << 'EOF'
[user]
	name = Test User
	email = test@example.com
[core]
	editor = vim
EOF
result=$(HOME="$GIT_CONFIG_BOTH" extract_git_user_config)
assert_contains "Both found: has user.name" "$result" "user.name=Test User"
assert_contains "Both found: has user.email" "$result" "user.email=test@example.com"


section "extract_git_user_config — found in included file"

GIT_CONFIG_INCLUDE="$TMPDIR_BASE/git-config-include"
mkdir -p "$GIT_CONFIG_INCLUDE/.config"
cat > "$GIT_CONFIG_INCLUDE/.gitconfig" << 'EOF'
[include]
	path = ~/.config/git-user
[core]
	editor = vim
EOF
cat > "$GIT_CONFIG_INCLUDE/.config/git-user" << 'EOF'
[user]
	name = Included User
	email = included@example.com
EOF
result=$(HOME="$GIT_CONFIG_INCLUDE" extract_git_user_config)
assert_contains "Include: has user.name" "$result" "user.name=Included User"
assert_contains "Include: has user.email" "$result" "user.email=included@example.com"


section "extract_git_user_config — only name found"

GIT_CONFIG_NAME_ONLY="$TMPDIR_BASE/git-config-name-only"
mkdir -p "$GIT_CONFIG_NAME_ONLY"
cat > "$GIT_CONFIG_NAME_ONLY/.gitconfig" << 'EOF'
[user]
	name = Name Only User
EOF
result=$(HOME="$GIT_CONFIG_NAME_ONLY" extract_git_user_config 2>&1 || echo "")
assert_contains "Name only: has user.name" "$result" "user.name=Name Only User"
assert_not_contains "Name only: missing email" "$result" "user.email"


section "extract_git_user_config — only email found"

GIT_CONFIG_EMAIL_ONLY="$TMPDIR_BASE/git-config-email-only"
mkdir -p "$GIT_CONFIG_EMAIL_ONLY"
cat > "$GIT_CONFIG_EMAIL_ONLY/.gitconfig" << 'EOF'
[user]
	email = emailonly@example.com
EOF
result=$(HOME="$GIT_CONFIG_EMAIL_ONLY" extract_git_user_config 2>&1 || echo "")
assert_contains "Email only: has user.email" "$result" "user.email=emailonly@example.com"
assert_not_contains "Email only: missing name" "$result" "user.name"


print_summary "$(basename "$0" .sh)"