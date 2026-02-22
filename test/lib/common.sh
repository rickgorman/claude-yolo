#!/usr/bin/env bash
#
# Common test framework for claude-yolo tests
# Source this file at the beginning of each test file
#

set -euo pipefail

# Test directory paths
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(dirname "$TEST_DIR")"
CLI="$REPO_DIR/bin/claude-yolo"
STRATEGIES_DIR="$REPO_DIR/strategies"

# Create a temporary directory for test fixtures (if not already created)
if [[ -z "${TMPDIR_BASE:-}" ]]; then
  TMPDIR_BASE=$(mktemp -d "${TMPDIR:-/tmp}/claude-yolo.XXXXXX")
  trap 'rm -rf "$TMPDIR_BASE"' EXIT
fi

# Create mock bin directory for test fixtures
MOCK_BIN="$TMPDIR_BASE/mock-bin"
mkdir -p "$MOCK_BIN"

# Create fake home directory for test fixtures
FAKE_HOME="$TMPDIR_BASE/fake-home"
mkdir -p "$FAKE_HOME"

# Create CLI home for test fixtures
CLI_HOME="$TMPDIR_BASE/cli-home"
mkdir -p "$CLI_HOME/.claude"
echo '{"claudeAiOauth":{"accessToken":"fake-test-token"}}' > "$CLI_HOME/.claude/.credentials.json"

########################################
# Common test fixtures
########################################

# Full Rails project
RAILS_DIR="$TMPDIR_BASE/rails-project"
mkdir -p "$RAILS_DIR/config" "$RAILS_DIR/bin"
echo "gem 'rails'" > "$RAILS_DIR/Gemfile"
echo "# app" > "$RAILS_DIR/config/application.rb"
echo "3.3.0" > "$RAILS_DIR/.ruby-version"
echo "#!/bin/bash" > "$RAILS_DIR/bin/rails"

# Weak Rails signal
WEAK_RAILS="$TMPDIR_BASE/weak-rails"
mkdir -p "$WEAK_RAILS"
echo "gem 'sinatra'" > "$WEAK_RAILS/Gemfile"

# Full Android project
ANDROID_DIR="$TMPDIR_BASE/android-project"
mkdir -p "$ANDROID_DIR/app/src/main"
echo "plugins { id 'com.android.application' }" > "$ANDROID_DIR/build.gradle"
echo "include ':app'" > "$ANDROID_DIR/settings.gradle"
echo "android { compileSdkVersion 34 }" > "$ANDROID_DIR/app/build.gradle"
echo "<manifest />" > "$ANDROID_DIR/app/src/main/AndroidManifest.xml"
echo "#!/bin/bash" > "$ANDROID_DIR/gradlew"

# React Native with android subdir
RN_DIR="$TMPDIR_BASE/rn-project"
mkdir -p "$RN_DIR/android/app/src/main"
echo '{"name": "myapp"}' > "$RN_DIR/package.json"
echo "plugins { id 'com.android.application' }" > "$RN_DIR/android/build.gradle"
echo "android {}" > "$RN_DIR/android/app/build.gradle"
echo "<manifest />" > "$RN_DIR/android/app/src/main/AndroidManifest.xml"

# Full Python project
PYTHON_DIR="$TMPDIR_BASE/python-project"
mkdir -p "$PYTHON_DIR"
cat > "$PYTHON_DIR/pyproject.toml" << 'EOF'
[project]
name = "myproject"
requires-python = ">=3.11"
EOF
echo "requests>=2.28" > "$PYTHON_DIR/requirements.txt"
echo "3.12.0" > "$PYTHON_DIR/.python-version"

# Weak Python signal
WEAK_PYTHON="$TMPDIR_BASE/weak-python"
mkdir -p "$WEAK_PYTHON"
echo "requests>=2.28" > "$WEAK_PYTHON/requirements.txt"

# Full Node.js project
NODE_DIR="$TMPDIR_BASE/node-project"
mkdir -p "$NODE_DIR"
echo '{"name": "myapp", "version": "1.0.0"}' > "$NODE_DIR/package.json"
echo '{}' > "$NODE_DIR/package-lock.json"
echo '{"compilerOptions": {"target": "es2020"}}' > "$NODE_DIR/tsconfig.json"
echo "20" > "$NODE_DIR/.nvmrc"

# Weak Node.js signal
WEAK_NODE="$TMPDIR_BASE/weak-node"
mkdir -p "$WEAK_NODE"
echo '{"name": "myapp"}' > "$WEAK_NODE/package.json"

# Rails project with package.json
RAILS_WITH_NODE="$TMPDIR_BASE/rails-with-node"
mkdir -p "$RAILS_WITH_NODE/config"
echo "gem 'rails'" > "$RAILS_WITH_NODE/Gemfile"
echo "# app" > "$RAILS_WITH_NODE/config/application.rb"
echo '{"name": "rails-frontend"}' > "$RAILS_WITH_NODE/package.json"

# Full Go project
GO_DIR="$TMPDIR_BASE/go-project"
mkdir -p "$GO_DIR/cmd/server"
cat > "$GO_DIR/go.mod" << 'EOF'
module github.com/example/myproject

go 1.23
EOF
echo "package main" > "$GO_DIR/go.sum"
echo 'package main; func main() {}' > "$GO_DIR/main.go"
echo 'package main; func main() {}' > "$GO_DIR/cmd/server/main.go"

# Weak Go signal
WEAK_GO="$TMPDIR_BASE/weak-go"
mkdir -p "$WEAK_GO"
cat > "$WEAK_GO/go.mod" << 'EOF'
module github.com/example/small

go 1.23
EOF

# Empty project
EMPTY_DIR="$TMPDIR_BASE/empty-project"
mkdir -p "$EMPTY_DIR"

########################################
# Source CLI functions, then override
########################################

# Source the CLI (with main disabled) to get its functions
_tmp_script="$TMPDIR_BASE/claude-yolo-functions.sh"
sed 's/^main "\$@"$/# main "$@"/' "$CLI" > "$_tmp_script"
source "$_tmp_script"

# Restore paths that sourcing overwrote (BASH_SOURCE[0] pointed to temp file)
REPO_DIR="$(dirname "$TEST_DIR")"
STRATEGIES_DIR="$REPO_DIR/strategies"

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

assert_not_contains() {
  local description="$1" haystack="$2" needle="$3"
  if ! echo "$haystack" | grep -qF -- "$needle"; then
    pass "$description"
  else
    fail "$description (expected NOT to contain '$needle')"
  fi
}

assert_match() {
  local description="$1" haystack="$2" pattern="$3"
  if echo "$haystack" | grep -qE -- "$pattern"; then
    pass "$description"
  else
    fail "$description (expected to match '$pattern')"
  fi
}

section() {
  echo ""
  echo "━━━ $1 ━━━"
}

# Summary output (call at end of each test file)
print_summary() {
  local test_name="${1:-Tests}"
  echo ""
  echo "━━━ $test_name Results ━━━"
  echo ""
  echo "  Passed: $_PASS"
  echo "  Failed: $_FAIL"
  echo ""

  if [[ $_FAIL -gt 0 ]]; then
    echo "  Failed tests:"
    for err in "${_ERRORS[@]}"; do
      echo "    ✘ $err"
    done
    echo ""
    return 1
  fi

  echo "  All tests passed!"
  return 0
}
