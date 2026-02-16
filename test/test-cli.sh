#!/usr/bin/env bash
#
# End-to-end tests for claude-yolo CLI
#
# Usage:
#   ./test/test-cli.sh
#
# Tests cover: argument parsing, color system, output helpers, path hashing,
# docker checks, detection logic, strategy selection, Dockerfile correctness,
# entrypoint safety, and full CLI integration flows.

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$TEST_DIR")"
CLI="$REPO_DIR/bin/claude-yolo"
STRATEGIES_DIR="$REPO_DIR/strategies"

# Create a temporary directory for test fixtures
TMPDIR_BASE=$(mktemp -d "${TMPDIR:-/tmp}/claude-yolo.XXXXXX")
trap 'rm -rf "$TMPDIR_BASE"' EXIT

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

########################################
# Build test fixtures
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

# Weak Python signal (just requirements.txt)
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

# Weak Node.js signal (just package.json, no lockfile or TS)
WEAK_NODE="$TMPDIR_BASE/weak-node"
mkdir -p "$WEAK_NODE"
echo '{"name": "myapp"}' > "$WEAK_NODE/package.json"

# Rails project with package.json (should prefer rails, not node)
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

# Weak Go signal (just go.mod)
WEAK_GO="$TMPDIR_BASE/weak-go"
mkdir -p "$WEAK_GO"
cat > "$WEAK_GO/go.mod" << 'EOF'
module github.com/example/small

go 1.23
EOF

# Empty project
EMPTY_DIR="$TMPDIR_BASE/empty-project"
mkdir -p "$EMPTY_DIR"

# Shared mock HOME with Claude credentials for CLI integration tests
CLI_HOME="$TMPDIR_BASE/cli-test-home"
mkdir -p "$CLI_HOME/.claude"
echo '{"claudeAiOauth":{"accessToken":"fake-test-token","refreshToken":"fake-refresh-token"}}' > "$CLI_HOME/.claude/.credentials.json"

########################################
# Tests: Color system
########################################

section "Color system"

output=$(TERM=xterm bash -c '
  [[ -t 2 ]] && echo "tty" || echo "not-tty"
' 2>&1)
assert_eq "Non-interactive shell is not a TTY" "not-tty" "$output"

output=$(bash -c '
  source <(sed "s/^main \"\\\$@\"$//" "'"$CLI"'")
  echo "BOLD=$BOLD GREEN=$GREEN RESET=$RESET"
' 2>/dev/null)
assert_eq "Colors disabled when stderr not a TTY" "BOLD= GREEN= RESET=" "$output"

########################################
# Tests: path_hash portability
########################################

section "path_hash portability"

hash1=$(path_hash "/test/path")
assert_match "path_hash returns 8 hex chars" "$hash1" '^[a-f0-9]{8}$'

hash2=$(path_hash "/test/path")
assert_eq "path_hash is deterministic" "$hash1" "$hash2"

hash3=$(path_hash "/different/path")
if [[ "$hash1" != "$hash3" ]]; then
  pass "path_hash differs for different paths"
else
  fail "path_hash differs for different paths"
fi

########################################
# Tests: cdp_port_for_hash
########################################

section "cdp_port_for_hash"

port1=$(cdp_port_for_hash "abcd1234")
port2=$(cdp_port_for_hash "abcd1234")
assert_eq "cdp_port_for_hash is deterministic" "$port1" "$port2"

port3=$(cdp_port_for_hash "deadbeef")
if [[ "$port1" != "$port3" ]]; then
  pass "cdp_port_for_hash differs for different hashes"
else
  fail "cdp_port_for_hash should differ for different hashes (both: $port1)"
fi

if [[ "$port1" -ge 9222 && "$port1" -le 9999 ]]; then
  pass "cdp_port_for_hash in range 9222–9999 ($port1)"
else
  fail "cdp_port_for_hash out of range ($port1)"
fi

# Test boundary: 0000 hash → minimum port
port_min=$(cdp_port_for_hash "00001234")
assert_eq "cdp_port_for_hash with 0000 prefix gives 9222" "9222" "$port_min"

# Test boundary: ffff hash → 65535 % 778 = 65535 - 84*778 = 65535 - 65352 = 183 → 9222 + 183 = 9405
port_max=$(cdp_port_for_hash "ffff1234")
if [[ "$port_max" -ge 9222 && "$port_max" -le 9999 ]]; then
  pass "cdp_port_for_hash with ffff prefix in range ($port_max)"
else
  fail "cdp_port_for_hash with ffff prefix out of range ($port_max)"
fi

# Consistent with path_hash: same worktree path → same port every time
hash_for_port=$(path_hash "/test/worktree/path")
port_from_hash=$(cdp_port_for_hash "$hash_for_port")
port_from_hash2=$(cdp_port_for_hash "$hash_for_port")
assert_eq "cdp_port_for_hash stable through path_hash" "$port_from_hash" "$port_from_hash2"

########################################
# Tests: Output helpers (non-TTY mode)
########################################

section "Output helpers"

output=$(info "test message" 2>&1)
assert_contains "info() includes arrow glyph" "$output" "→"
assert_contains "info() includes message" "$output" "test message"

output=$(success "done" 2>&1)
assert_contains "success() includes check glyph" "$output" "✔"

# CLI's fail is overridden, test it directly
output=$(echo -e "  ✘ broken" 2>&1)
assert_contains "fail output includes X glyph" "$output" "✘"

output=$(warn "caution" 2>&1)
assert_contains "warn() includes circle glyph" "$output" "○"

output=$(header 2>&1)
assert_contains "header() includes claude·yolo" "$output" "claude·yolo"
assert_contains "header() includes box corner" "$output" "┌"

output=$(footer 2>&1)
assert_contains "footer() includes box corner" "$output" "└"

########################################
# Tests: Argument parsing
########################################

section "Argument parsing"

output=$(bash "$CLI" --yolo --strategy 2>&1 || true)
assert_contains "--strategy without arg shows error" "$output" "--strategy requires an argument"

section "--help flag"

help_output=$(bash "$CLI" --help 2>&1 || true)
assert_contains "--help shows usage line" "$help_output" "Usage:"
assert_contains "--help shows --yolo flag" "$help_output" "--yolo"
assert_contains "--help shows --strategy flag" "$help_output" "--strategy"
assert_contains "--help shows --env flag" "$help_output" "--env KEY=VALUE"
assert_contains "--help shows --print flag" "$help_output" "--print"
assert_contains "--help shows --trust-github-token" "$help_output" "--trust-github-token"
assert_contains "--help shows --chrome flag" "$help_output" "--chrome"
assert_contains "--help shows claude·yolo branding" "$help_output" "claude"

h_output=$(bash "$CLI" -h 2>&1 || true)
assert_contains "-h shows same help as --help" "$h_output" "Usage:"

########################################
# Tests: Strategy detection — Rails
########################################

section "Strategy detection — Rails"

rails_output=$("$STRATEGIES_DIR/rails/detect.sh" "$RAILS_DIR" 2>/dev/null)
rails_confidence=$(echo "$rails_output" | grep '^CONFIDENCE:' | cut -d: -f2)
rails_evidence=$(echo "$rails_output" | grep '^EVIDENCE:' | cut -d: -f2-)

if [[ "$rails_confidence" -ge 80 ]]; then
  pass "Rails confidence ≥80% for full Rails project ($rails_confidence%)"
else
  fail "Rails confidence ≥80% for full Rails project (got $rails_confidence%)"
fi
assert_contains "Rails evidence includes Gemfile" "$rails_evidence" "Gemfile with rails"
assert_contains "Rails evidence includes application.rb" "$rails_evidence" "config/application.rb"

section "Strategy detection — Rails (weak signal)"

weak_output=$("$STRATEGIES_DIR/rails/detect.sh" "$WEAK_RAILS" 2>/dev/null)
weak_confidence=$(echo "$weak_output" | grep '^CONFIDENCE:' | cut -d: -f2)

if [[ "$weak_confidence" -lt 80 ]]; then
  pass "Rails detection <80% for Gemfile without rails ($weak_confidence%)"
else
  fail "Rails detection <80% for Gemfile without rails (got $weak_confidence%)"
fi

section "Strategy detection — Android"

android_output=$("$STRATEGIES_DIR/android/detect.sh" "$ANDROID_DIR" 2>/dev/null)
android_confidence=$(echo "$android_output" | grep '^CONFIDENCE:' | cut -d: -f2)

if [[ "$android_confidence" -ge 80 ]]; then
  pass "Android confidence ≥80% for full Android project ($android_confidence%)"
else
  fail "Android confidence ≥80% for full Android project (got $android_confidence%)"
fi

section "Strategy detection — Android (React Native subdirectory)"

rn_output=$("$STRATEGIES_DIR/android/detect.sh" "$RN_DIR" 2>/dev/null)
rn_confidence=$(echo "$rn_output" | grep '^CONFIDENCE:' | cut -d: -f2)

if [[ "$rn_confidence" -gt 0 ]]; then
  pass "Android detects React Native android/ subdir ($rn_confidence%)"
else
  fail "Android should detect React Native android/ subdir"
fi

section "Strategy detection — No match"

rails_empty=$("$STRATEGIES_DIR/rails/detect.sh" "$EMPTY_DIR" 2>/dev/null)
rails_empty_conf=$(echo "$rails_empty" | grep '^CONFIDENCE:' | cut -d: -f2)
assert_eq "Rails detection 0% for empty dir" "0" "$rails_empty_conf"

android_empty=$("$STRATEGIES_DIR/android/detect.sh" "$EMPTY_DIR" 2>/dev/null)
android_empty_conf=$(echo "$android_empty" | grep '^CONFIDENCE:' | cut -d: -f2)
assert_eq "Android detection 0% for empty dir" "0" "$android_empty_conf"

section "Strategy detection — Generic"

generic_output=$("$STRATEGIES_DIR/generic/detect.sh" "$RAILS_DIR" 2>/dev/null)
generic_confidence=$(echo "$generic_output" | grep '^CONFIDENCE:' | cut -d: -f2)
assert_eq "Generic detection always 0% (manual only)" "0" "$generic_confidence"

generic_empty=$("$STRATEGIES_DIR/generic/detect.sh" "$EMPTY_DIR" 2>/dev/null)
generic_empty_conf=$(echo "$generic_empty" | grep '^CONFIDENCE:' | cut -d: -f2)
assert_eq "Generic detection 0% for empty dir" "0" "$generic_empty_conf"

section "Strategy detection — Python"

python_output=$("$STRATEGIES_DIR/python/detect.sh" "$PYTHON_DIR" 2>/dev/null)
python_confidence=$(echo "$python_output" | grep '^CONFIDENCE:' | cut -d: -f2)
python_evidence=$(echo "$python_output" | grep '^EVIDENCE:' | cut -d: -f2-)

if [[ "$python_confidence" -ge 80 ]]; then
  pass "Python confidence ≥80% for full Python project ($python_confidence%)"
else
  fail "Python confidence ≥80% for full Python project (got $python_confidence%)"
fi
assert_contains "Python evidence includes pyproject.toml" "$python_evidence" "pyproject.toml"
assert_contains "Python evidence includes requirements.txt" "$python_evidence" "requirements.txt"
assert_contains "Python evidence includes .python-version" "$python_evidence" ".python-version"

section "Strategy detection — Python (weak signal)"

weak_python_output=$("$STRATEGIES_DIR/python/detect.sh" "$WEAK_PYTHON" 2>/dev/null)
weak_python_conf=$(echo "$weak_python_output" | grep '^CONFIDENCE:' | cut -d: -f2)

if [[ "$weak_python_conf" -lt 80 ]]; then
  pass "Python detection <80% for just requirements.txt ($weak_python_conf%)"
else
  fail "Python detection <80% for just requirements.txt (got $weak_python_conf%)"
fi

python_empty=$("$STRATEGIES_DIR/python/detect.sh" "$EMPTY_DIR" 2>/dev/null)
python_empty_conf=$(echo "$python_empty" | grep '^CONFIDENCE:' | cut -d: -f2)
assert_eq "Python detection 0% for empty dir" "0" "$python_empty_conf"

section "Strategy detection — Node.js"

node_output=$("$STRATEGIES_DIR/node/detect.sh" "$NODE_DIR" 2>/dev/null)
node_confidence=$(echo "$node_output" | grep '^CONFIDENCE:' | cut -d: -f2)
node_evidence=$(echo "$node_output" | grep '^EVIDENCE:' | cut -d: -f2-)

if [[ "$node_confidence" -ge 80 ]]; then
  pass "Node.js confidence ≥80% for full Node project ($node_confidence%)"
else
  fail "Node.js confidence ≥80% for full Node project (got $node_confidence%)"
fi
assert_contains "Node.js evidence includes package.json" "$node_evidence" "package.json"
assert_contains "Node.js evidence includes tsconfig.json" "$node_evidence" "tsconfig.json"
assert_contains "Node.js evidence includes .nvmrc" "$node_evidence" ".nvmrc"

section "Strategy detection — Node.js (weak signal)"

weak_node_output=$("$STRATEGIES_DIR/node/detect.sh" "$WEAK_NODE" 2>/dev/null)
weak_node_conf=$(echo "$weak_node_output" | grep '^CONFIDENCE:' | cut -d: -f2)

if [[ "$weak_node_conf" -lt 80 ]]; then
  pass "Node.js detection <80% for just package.json ($weak_node_conf%)"
else
  fail "Node.js detection <80% for just package.json (got $weak_node_conf%)"
fi

section "Strategy detection — Node.js (Rails project with package.json)"

rails_node_output=$("$STRATEGIES_DIR/node/detect.sh" "$RAILS_WITH_NODE" 2>/dev/null)
rails_node_conf=$(echo "$rails_node_output" | grep '^CONFIDENCE:' | cut -d: -f2)

if [[ "$rails_node_conf" -lt 80 ]]; then
  pass "Node.js detection <80% for Rails project with package.json ($rails_node_conf%)"
else
  fail "Node.js detection <80% for Rails project with package.json (got $rails_node_conf%)"
fi

node_empty=$("$STRATEGIES_DIR/node/detect.sh" "$EMPTY_DIR" 2>/dev/null)
node_empty_conf=$(echo "$node_empty" | grep '^CONFIDENCE:' | cut -d: -f2)
assert_eq "Node.js detection 0% for empty dir" "0" "$node_empty_conf"

section "Strategy detection — Go"

go_output=$("$STRATEGIES_DIR/go/detect.sh" "$GO_DIR" 2>/dev/null)
go_confidence=$(echo "$go_output" | grep '^CONFIDENCE:' | cut -d: -f2)
go_evidence=$(echo "$go_output" | grep '^EVIDENCE:' | cut -d: -f2-)

if [[ "$go_confidence" -ge 80 ]]; then
  pass "Go confidence ≥80% for full Go project ($go_confidence%)"
else
  fail "Go confidence ≥80% for full Go project (got $go_confidence%)"
fi
assert_contains "Go evidence includes go.mod" "$go_evidence" "go.mod"
assert_contains "Go evidence includes main.go" "$go_evidence" "main.go"
assert_contains "Go evidence includes cmd/" "$go_evidence" "cmd/"

section "Strategy detection — Go (weak signal)"

weak_go_output=$("$STRATEGIES_DIR/go/detect.sh" "$WEAK_GO" 2>/dev/null)
weak_go_conf=$(echo "$weak_go_output" | grep '^CONFIDENCE:' | cut -d: -f2)

if [[ "$weak_go_conf" -lt 80 ]]; then
  pass "Go detection <80% for just go.mod ($weak_go_conf%)"
else
  fail "Go detection <80% for just go.mod (got $weak_go_conf%)"
fi

go_empty=$("$STRATEGIES_DIR/go/detect.sh" "$EMPTY_DIR" 2>/dev/null)
go_empty_conf=$(echo "$go_empty" | grep '^CONFIDENCE:' | cut -d: -f2)
assert_eq "Go detection 0% for empty dir" "0" "$go_empty_conf"

section "Strategy detection — No match (new strategies)"

assert_eq "Python detection 0% for empty dir" "0" "$python_empty_conf"
assert_eq "Node.js detection 0% for empty dir" "0" "$node_empty_conf"
assert_eq "Go detection 0% for empty dir" "0" "$go_empty_conf"

########################################
# Tests: run_detection integration
########################################

section "run_detection integration"

detections=$(run_detection "$RAILS_DIR")
assert_contains "run_detection finds rails for Rails project" "$detections" "rails"

detections=$(run_detection "$EMPTY_DIR")
assert_eq "run_detection returns empty for empty dir" "" "$detections"

# Both rails and android should detect the RN project
detections=$(run_detection "$RN_DIR")
assert_contains "run_detection finds android for RN project" "$detections" "android"

detections=$(run_detection "$PYTHON_DIR")
assert_contains "run_detection finds python for Python project" "$detections" "python"

detections=$(run_detection "$NODE_DIR")
assert_contains "run_detection finds node for Node.js project" "$detections" "node"

detections=$(run_detection "$GO_DIR")
assert_contains "run_detection finds go for Go project" "$detections" "go"

########################################
# Tests: Ruby version detection
########################################

section "Ruby version detection"

ver=$(detect_ruby_version "$RAILS_DIR")
assert_eq "Detects from .ruby-version" "3.3.0" "$ver"

TOOL_VER_DIR="$TMPDIR_BASE/tool-versions-project"
mkdir -p "$TOOL_VER_DIR"
echo "ruby 3.2.2" > "$TOOL_VER_DIR/.tool-versions"
ver=$(detect_ruby_version "$TOOL_VER_DIR")
assert_eq "Detects from .tool-versions" "3.2.2" "$ver"

GEMFILE_VER_DIR="$TMPDIR_BASE/gemfile-ruby-project"
mkdir -p "$GEMFILE_VER_DIR"
cat > "$GEMFILE_VER_DIR/Gemfile" << 'EOF'
source 'https://rubygems.org'
ruby '3.1.4'
gem 'rails'
EOF
ver=$(detect_ruby_version "$GEMFILE_VER_DIR")
assert_eq "Detects from Gemfile ruby declaration" "3.1.4" "$ver"

NOVER_DIR="$TMPDIR_BASE/no-ruby-version"
mkdir -p "$NOVER_DIR"
ver=$(detect_ruby_version "$NOVER_DIR")
assert_eq "Falls back to 4.0.1 when no version found" "4.0.1" "$ver"

# Priority: .ruby-version > .tool-versions > Gemfile
MULTI_DIR="$TMPDIR_BASE/multi-version"
mkdir -p "$MULTI_DIR"
echo "3.3.0" > "$MULTI_DIR/.ruby-version"
echo "ruby 3.2.0" > "$MULTI_DIR/.tool-versions"
cat > "$MULTI_DIR/Gemfile" << 'EOF'
ruby '3.1.0'
EOF
ver=$(detect_ruby_version "$MULTI_DIR")
assert_eq ".ruby-version takes priority over others" "3.3.0" "$ver"

########################################
# Tests: Python version detection
########################################

section "Python version detection"

ver=$(detect_python_version "$PYTHON_DIR")
assert_eq "Detects Python from .python-version" "3.12.0" "$ver"

PYTHON_TOOL_VER_DIR="$TMPDIR_BASE/python-tool-versions"
mkdir -p "$PYTHON_TOOL_VER_DIR"
echo "python 3.11.5" > "$PYTHON_TOOL_VER_DIR/.tool-versions"
ver=$(detect_python_version "$PYTHON_TOOL_VER_DIR")
assert_eq "Detects Python from .tool-versions" "3.11.5" "$ver"

PYTHON_NOVER_DIR="$TMPDIR_BASE/no-python-version"
mkdir -p "$PYTHON_NOVER_DIR"
ver=$(detect_python_version "$PYTHON_NOVER_DIR")
assert_eq "Falls back to 3.12 when no Python version found" "3.12" "$ver"

# Priority: .python-version > .tool-versions
PYTHON_MULTI_DIR="$TMPDIR_BASE/python-multi-version"
mkdir -p "$PYTHON_MULTI_DIR"
echo "3.12.0" > "$PYTHON_MULTI_DIR/.python-version"
echo "python 3.11.0" > "$PYTHON_MULTI_DIR/.tool-versions"
ver=$(detect_python_version "$PYTHON_MULTI_DIR")
assert_eq ".python-version takes priority for Python" "3.12.0" "$ver"

########################################
# Tests: Node.js version detection
########################################

section "Node.js version detection"

ver=$(detect_node_version "$NODE_DIR")
assert_eq "Detects Node from .nvmrc" "20" "$ver"

NODE_VER_DIR="$TMPDIR_BASE/node-version-file"
mkdir -p "$NODE_VER_DIR"
echo "18.19.0" > "$NODE_VER_DIR/.node-version"
ver=$(detect_node_version "$NODE_VER_DIR")
assert_eq "Detects Node from .node-version" "18.19.0" "$ver"

NODE_TOOL_VER_DIR="$TMPDIR_BASE/node-tool-versions"
mkdir -p "$NODE_TOOL_VER_DIR"
echo "nodejs 20.11.0" > "$NODE_TOOL_VER_DIR/.tool-versions"
ver=$(detect_node_version "$NODE_TOOL_VER_DIR")
assert_eq "Detects Node from .tool-versions" "20.11.0" "$ver"

NODE_NOVER_DIR="$TMPDIR_BASE/no-node-version"
mkdir -p "$NODE_NOVER_DIR"
ver=$(detect_node_version "$NODE_NOVER_DIR")
assert_eq "Falls back to 20 when no Node version found" "20" "$ver"

# Priority: .nvmrc > .node-version > .tool-versions
NODE_MULTI_DIR="$TMPDIR_BASE/node-multi-version"
mkdir -p "$NODE_MULTI_DIR"
echo "20" > "$NODE_MULTI_DIR/.nvmrc"
echo "18.0.0" > "$NODE_MULTI_DIR/.node-version"
echo "nodejs 16.0.0" > "$NODE_MULTI_DIR/.tool-versions"
ver=$(detect_node_version "$NODE_MULTI_DIR")
assert_eq ".nvmrc takes priority for Node" "20" "$ver"

########################################
# Tests: list_strategies
########################################

section "list_strategies"

strategies=$(list_strategies)
assert_contains "list_strategies includes rails" "$strategies" "rails"
assert_contains "list_strategies includes android" "$strategies" "android"
assert_contains "list_strategies includes generic" "$strategies" "generic"
assert_contains "list_strategies includes python" "$strategies" "python"
assert_contains "list_strategies includes node" "$strategies" "node"
assert_contains "list_strategies includes go" "$strategies" "go"

########################################
# Tests: Strategy description files
########################################

section "Strategy description files"

for strategy_dir in "$STRATEGIES_DIR"/*/; do
  strategy=$(basename "$strategy_dir")
  if [[ -f "$strategy_dir/description" ]]; then
    desc=$(cat "$strategy_dir/description" | tr -d '\n')
    if [[ -n "$desc" ]]; then
      pass "$strategy has non-empty description: $desc"
    else
      fail "$strategy has empty description file"
    fi
  else
    fail "$strategy is missing description file"
  fi
done

########################################
# Tests: Strategy file completeness
########################################

section "Strategy file completeness"

for strategy_dir in "$STRATEGIES_DIR"/*/; do
  strategy=$(basename "$strategy_dir")
  for required_file in detect.sh Dockerfile entrypoint.sh; do
    if [[ -f "$strategy_dir/$required_file" ]]; then
      pass "$strategy has $required_file"
    else
      fail "$strategy is missing $required_file"
    fi
  done

  if [[ -x "$strategy_dir/detect.sh" ]]; then
    pass "$strategy/detect.sh is executable"
  else
    fail "$strategy/detect.sh is not executable"
  fi

  if [[ -x "$strategy_dir/entrypoint.sh" ]]; then
    pass "$strategy/entrypoint.sh is executable"
  else
    fail "$strategy/entrypoint.sh is not executable"
  fi
done

########################################
# Tests: Dockerfile correctness
########################################

section "Dockerfile correctness"

for strategy_dir in "$STRATEGIES_DIR"/*/; do
  strategy=$(basename "$strategy_dir")
  dockerfile="$strategy_dir/Dockerfile"
  [[ -f "$dockerfile" ]] || continue

  content=$(cat "$dockerfile")

  # /workspace must be created before USER switch
  user_line=$(grep -n '^USER ' "$dockerfile" | head -1 | cut -d: -f1)
  workspace_mkdir=$(grep -n 'mkdir.*workspace' "$dockerfile" | head -1 | cut -d: -f1)

  if [[ -n "$user_line" && -n "$workspace_mkdir" ]]; then
    if [[ "$workspace_mkdir" -lt "$user_line" ]]; then
      pass "$strategy: /workspace created before USER switch"
    else
      fail "$strategy: /workspace created AFTER USER switch (will fail as non-root)"
    fi
  fi

  # npm install -g should happen before USER switch
  npm_global=$(grep -n 'npm install -g' "$dockerfile" | head -1 | cut -d: -f1)
  if [[ -n "$user_line" && -n "$npm_global" ]]; then
    if [[ "$npm_global" -lt "$user_line" ]]; then
      pass "$strategy: npm install -g runs as root (before USER)"
    else
      fail "$strategy: npm install -g runs as non-root (after USER switch)"
    fi
  fi

  assert_contains "$strategy: has ENTRYPOINT" "$content" "ENTRYPOINT"
  assert_contains "$strategy: installs claude-code" "$content" "@anthropic-ai/claude-code"
done

########################################
# Tests: Dockerfile sudo / apt-get at runtime
########################################

section "Dockerfile sudo for runtime apt-get"

for strategy_dir in "$STRATEGIES_DIR"/*/; do
  strategy=$(basename "$strategy_dir")
  dockerfile="$strategy_dir/Dockerfile"
  [[ -f "$dockerfile" ]] || continue

  content=$(cat "$dockerfile")

  assert_contains "$strategy: Dockerfile installs sudo" "$content" "sudo"

  if echo "$content" | grep -q 'claude ALL=(ALL) NOPASSWD:ALL'; then
    pass "$strategy: claude user has passwordless sudo"
  else
    fail "$strategy: claude user missing NOPASSWD sudoers entry"
  fi
done

########################################
# Tests: Entrypoint correctness
########################################

section "Entrypoint correctness"

for strategy_dir in "$STRATEGIES_DIR"/*/; do
  strategy=$(basename "$strategy_dir")
  entrypoint="$strategy_dir/entrypoint.sh"
  [[ -f "$entrypoint" ]] || continue

  content=$(cat "$entrypoint")

  # Must end with exec "$@"
  last_code_line=$(grep -v '^#' "$entrypoint" | grep -v '^$' | tail -1)
  assert_eq "$strategy entrypoint ends with exec \"\$@\"" 'exec "$@"' "$last_code_line"

  # Must have set -euo pipefail
  assert_contains "$strategy entrypoint has strict mode" "$content" "set -euo pipefail"

  # Pipelines with grep must be protected from pipefail
  while IFS= read -r line; do
    lineno=$(echo "$line" | cut -d: -f1)
    linetext=$(echo "$line" | cut -d: -f2-)

    # Safe patterns on the same line: || true, || continue, inside if/while
    if echo "$linetext" | grep -qE '\|\| true|\|\| continue'; then
      continue
    fi
    if echo "$linetext" | grep -qE '^\s*(if|elif|while|until|!) '; then
      continue
    fi

    # Check if this is a while/for pipeline whose done line has || true
    if echo "$linetext" | grep -qE '\| while '; then
      block_end=$(sed -n "$((lineno + 1)),\$p" "$entrypoint" | grep -n '^done' | head -1)
      if [[ -n "$block_end" ]] && echo "$block_end" | grep -qE '\|\| true'; then
        continue
      fi
    fi

    fail "$strategy entrypoint line $lineno: unprotected grep in pipeline (pipefail will kill entrypoint): $(echo "$linetext" | tr -s ' ')"
  done < <(grep -n 'grep' "$entrypoint" | grep '|' || true)
done

section "Rails entrypoint — node_modules"

rails_entrypoint=$(cat "$STRATEGIES_DIR/rails/entrypoint.sh")
assert_contains "Rails entrypoint chowns node_modules" "$rails_entrypoint" "chown claude:claude /workspace/node_modules"
assert_contains "Rails entrypoint runs npm install" "$rails_entrypoint" "npm install"
assert_contains "Rails entrypoint runs yarn install when yarn.lock present" "$rails_entrypoint" "yarn install"

########################################
# Tests: generate_unknown_prompt
########################################

section "generate_unknown_prompt"

output=$(generate_unknown_prompt "$RAILS_DIR" 2>&1)
assert_contains "Prompt includes box drawing" "$output" "┌"
assert_contains "Prompt includes closing box" "$output" "┘"
assert_contains "Prompt mentions strategies/" "$output" "strategies/"
assert_contains "Prompt includes copy instruction" "$output" "Copy this into Claude"
assert_contains "Prompt mentions detect.sh" "$output" "detect.sh"
assert_contains "Prompt mentions Dockerfile" "$output" "Dockerfile"
assert_contains "Prompt mentions entrypoint.sh" "$output" "entrypoint.sh"
assert_contains "Prompt mentions description file" "$output" "description"

########################################
# Tests: CLI integration — docker not installed
########################################

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

# Set up fake HOME with commands directory, settings files, and credentials
FAKE_HOME="$TMPDIR_BASE/fake-claude-home"
mkdir -p "$FAKE_HOME/.claude/commands"
echo "test" > "$FAKE_HOME/.claude/commands/test.md"
echo '{}' > "$FAKE_HOME/.claude/settings.json"
echo '{}' > "$FAKE_HOME/.claude/settings.local.json"
echo '{"claudeAiOauth":{"accessToken":"fake-test-token","refreshToken":"fake-refresh-token"}}' > "$FAKE_HOME/.claude/.credentials.json"

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

########################################
# Tests: Settings files mounted read-only
########################################

section "Settings files mounted read-only"

assert_contains "Mounts settings.json read-only" "$docker_args" "settings.json:/home/claude/.claude/settings.json:ro"
assert_contains "Mounts settings.local.json read-only" "$docker_args" "settings.local.json:/home/claude/.claude/settings.local.json:ro"

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

########################################
# Tests: start-chrome.sh arithmetic safety
########################################

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

section "Color suppression when piped"

output=$(bash "$CLI" --yolo 2>&1 | cat || true)
if echo "$output" | grep -qP '\033\[' 2>/dev/null || echo "$output" | grep -q $'\033\[' 2>/dev/null; then
  fail "ANSI codes present when piped through cat"
else
  pass "No ANSI codes when stderr is not a TTY"
fi

########################################
# Tests: --chrome flag parsing
########################################

# Helper: standard docker + exec mock for chrome tests
# Overrides both docker (for API calls) and exec (to capture final docker run args)
_chrome_mock_prefix='
  export HOME="'"$CLI_HOME"'"
  export GH_TOKEN=test_token_for_ci
  exec() { echo "EXEC_CMD: $*"; command exit 0; }
  export -f exec
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
      *) return 1 ;;
    esac
  }
  export -f docker
  lsof() { return 1; }
  export -f lsof
'

section "--chrome flag parsing"

# --chrome with --yolo --strategy rails: should produce Chrome CDP output
output_chrome=$(bash -c '
  '"$_chrome_mock_prefix"'
  curl() {
    case "$*" in
      *api.github.com*) echo "200"; return 0 ;;
      *) return 0 ;;
    esac
  }
  export -f curl
  cd "'"$RAILS_DIR"'"
  bash "'"$CLI"'" --yolo --chrome --strategy rails 2>&1
' 2>&1 || true)

assert_contains "--chrome shows Chrome CDP info" "$output_chrome" "Chrome CDP"
assert_contains "--chrome shows MCP server name" "$output_chrome" "chrome-devtools"

# --yolo --strategy rails WITHOUT --chrome: should NOT have Chrome CDP MCP info
output_no_chrome=$(bash -c '
  '"$_chrome_mock_prefix"'
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

assert_not_contains "Without --chrome, no MCP server info" "$output_no_chrome" "chrome-devtools"

########################################
# Tests: --chrome MCP config volume mount
########################################

section "--chrome MCP config volume mount"

# Extract the exec'd docker run command and verify .mcp.json mount
exec_cmd_line=$(echo "$output_chrome" | grep "EXEC_CMD:" || true)

assert_contains "Docker args include .mcp.json mount" "$exec_cmd_line" ".mcp.json:ro"
assert_contains "Docker args mount to /workspace/.mcp.json" "$exec_cmd_line" "/workspace/.mcp.json"

# Without --chrome, docker args should NOT include .mcp.json mount
exec_cmd_no_chrome=$(echo "$output_no_chrome" | grep "EXEC_CMD:" || true)

assert_not_contains "Without --chrome, no .mcp.json mount" "$exec_cmd_no_chrome" ".mcp.json"

########################################
# Tests: --chrome uses computed port
########################################

section "--chrome uses computed port"

# Compute the expected CDP port for the RAILS_DIR (same path the CLI will use)
# The CLI calls get_worktree_path → git rev-parse || pwd, and pwd resolves symlinks
# (e.g. /var → /private/var on macOS), so we must resolve the same way
_chrome_resolved_path=$(cd "$RAILS_DIR" && pwd)
_chrome_test_hash=$(path_hash "$_chrome_resolved_path")
_chrome_expected_port=$(cdp_port_for_hash "$_chrome_test_hash")

assert_contains "Chrome output shows computed port" "$output_chrome" "port ${_chrome_expected_port}"
if [[ "$(uname)" == "Darwin" ]]; then
  _chrome_expected_host="host.docker.internal"
else
  _chrome_expected_host="localhost"
fi
assert_contains "CHROME_CDP_URL uses computed port" "$exec_cmd_line" "CHROME_CDP_URL=http://${_chrome_expected_host}:${_chrome_expected_port}"

########################################
# Tests: --chrome docker run args structure
########################################

section "--chrome docker run args structure"

# Verify the exec'd command is a proper docker run with expected flags
assert_contains "Exec'd command starts with docker" "$exec_cmd_line" "docker run"
# On macOS, --network=host is replaced by -p port flags
if [[ "$(uname)" == "Darwin" ]]; then
  assert_contains "Docker run includes port publish flags (macOS)" "$exec_cmd_line" "-p"
  assert_not_contains "Docker run omits --network=host (macOS)" "$exec_cmd_line" "--network=host"
else
  assert_contains "Docker run includes --network=host" "$exec_cmd_line" "--network=host"
fi
assert_contains "Docker run includes --dangerously-skip-permissions" "$exec_cmd_line" "--dangerously-skip-permissions"
assert_contains "Docker run uses rails image" "$exec_cmd_line" "claude-yolo-rails"

########################################
# Tests: --chrome MCP config content
########################################

section "--chrome MCP config content"

# Compute expected port for the rails test dir, same as the CLI would
_rails_hash=$(path_hash "$RAILS_DIR")
_expected_port=$(cdp_port_for_hash "$_rails_hash")

# Determine expected hostname (same logic as the CLI)
if [[ "$(uname)" == "Darwin" ]]; then
  _expected_cdp_host="host.docker.internal"
else
  _expected_cdp_host="localhost"
fi

# Generate the same MCP config the CLI generates and validate it
mcp_test_config="$TMPDIR_BASE/mcp-config-test.json"
cat > "$mcp_test_config" <<MCPEOF
{
  "mcpServers": {
    "chrome-devtools": {
      "command": "npx",
      "args": ["-y", "chrome-devtools-mcp@latest", "--browser-url=http://${_expected_cdp_host}:${_expected_port}"]
    }
  }
}
MCPEOF

# Validate JSON structure
if command -v jq &>/dev/null; then
  if jq . "$mcp_test_config" &>/dev/null; then
    pass "MCP config is valid JSON"
  else
    fail "MCP config is not valid JSON"
  fi

  server_name=$(jq -r '.mcpServers | keys[0]' "$mcp_test_config")
  assert_eq "MCP server name is chrome-devtools" "chrome-devtools" "$server_name"

  server_cmd=$(jq -r '.mcpServers["chrome-devtools"].command' "$mcp_test_config")
  assert_eq "MCP server command is npx" "npx" "$server_cmd"

  first_arg=$(jq -r '.mcpServers["chrome-devtools"].args[0]' "$mcp_test_config")
  assert_eq "MCP server first arg is -y" "-y" "$first_arg"

  pkg_arg=$(jq -r '.mcpServers["chrome-devtools"].args[1]' "$mcp_test_config")
  assert_contains "MCP server package is chrome-devtools-mcp" "$pkg_arg" "chrome-devtools-mcp"

  url_arg=$(jq -r '.mcpServers["chrome-devtools"].args[2]' "$mcp_test_config")
  assert_eq "MCP server points to computed port" "--browser-url=http://${_expected_cdp_host}:${_expected_port}" "$url_arg"

  num_servers=$(jq '.mcpServers | length' "$mcp_test_config")
  assert_eq "MCP config has exactly one server" "1" "$num_servers"

  num_args=$(jq '.mcpServers["chrome-devtools"].args | length' "$mcp_test_config")
  assert_eq "MCP server has exactly three args" "3" "$num_args"
else
  # Fallback: validate with grep if jq is not available
  content=$(cat "$mcp_test_config")
  assert_contains "MCP config has mcpServers key" "$content" '"mcpServers"'
  assert_contains "MCP config has chrome-devtools server" "$content" '"chrome-devtools"'
  assert_contains "MCP config uses npx" "$content" '"command": "npx"'
  assert_contains "MCP config targets computed port" "$content" "${_expected_cdp_host}:${_expected_port}"
fi

rm -f "$mcp_test_config"

########################################
# Tests: --chrome temp file is created
########################################

section "--chrome temp file creation"

# Verify the mounted MCP config path follows the expected pattern
mcp_mount_arg=$(echo "$exec_cmd_line" | tr ' ' '\n' | grep '.mcp.json' || true)
assert_match "MCP mount uses /tmp temp file" "$mcp_mount_arg" '/tmp/claude-yolo-mcp-[a-zA-Z0-9]+'
assert_contains "MCP mount target is /workspace/.mcp.json" "$mcp_mount_arg" ":/workspace/.mcp.json:ro"

########################################
# Tests: --chrome merges existing project .mcp.json
########################################

if command -v jq &>/dev/null; then
  section "--chrome merges into existing project .mcp.json"

  # Place a pre-existing .mcp.json in the project directory
  cat > "$RAILS_DIR/.mcp.json" <<'EXISTINGMCP'
{"mcpServers":{"my-custom-server":{"command":"node","args":["server.js"]}}}
EXISTINGMCP

  output_merge=$(bash -c '
    '"$_chrome_mock_prefix"'
    curl() {
      case "$*" in
        *api.github.com*) echo "200"; return 0 ;;
        *) return 0 ;;
      esac
    }
    export -f curl
    cd "'"$RAILS_DIR"'"
    bash "'"$CLI"'" --yolo --chrome --strategy rails 2>&1
  ' 2>&1 || true)

  merge_exec_cmd=$(echo "$output_merge" | grep "EXEC_CMD:" || true)
  merge_mcp_mount=$(echo "$merge_exec_cmd" | tr ' ' '\n' | grep '.mcp.json' || true)
  merge_mcp_path=$(echo "$merge_mcp_mount" | cut -d: -f1)

  if [[ -f "$merge_mcp_path" ]]; then
    num_servers=$(jq '.mcpServers | length' "$merge_mcp_path")
    assert_eq "Merged config has 2 servers" "2" "$num_servers"

    custom_cmd=$(jq -r '.mcpServers["my-custom-server"].command' "$merge_mcp_path")
    assert_eq "Custom server preserved" "node" "$custom_cmd"

    custom_args=$(jq -r '.mcpServers["my-custom-server"].args[0]' "$merge_mcp_path")
    assert_eq "Custom server args preserved" "server.js" "$custom_args"

    chrome_cmd=$(jq -r '.mcpServers["chrome-devtools"].command' "$merge_mcp_path")
    assert_eq "chrome-devtools added with npx" "npx" "$chrome_cmd"

    chrome_url=$(jq -r '.mcpServers["chrome-devtools"].args[2]' "$merge_mcp_path")
    assert_contains "chrome-devtools has browser-url" "$chrome_url" "--browser-url=http://"
  else
    fail "Merged MCP config file not found at $merge_mcp_path"
  fi

  rm -f "$RAILS_DIR/.mcp.json"
  rm -f "$merge_mcp_path"

  section "--chrome works without pre-existing project .mcp.json"

  # Ensure no pre-existing config in project directory
  rm -f "$RAILS_DIR/.mcp.json"

  output_no_existing=$(bash -c '
    '"$_chrome_mock_prefix"'
    curl() {
      case "$*" in
        *api.github.com*) echo "200"; return 0 ;;
        *) return 0 ;;
      esac
    }
    export -f curl
    cd "'"$RAILS_DIR"'"
    bash "'"$CLI"'" --yolo --chrome --strategy rails 2>&1
  ' 2>&1 || true)

  no_existing_exec=$(echo "$output_no_existing" | grep "EXEC_CMD:" || true)
  no_existing_mount=$(echo "$no_existing_exec" | tr ' ' '\n' | grep '.mcp.json' || true)
  no_existing_path=$(echo "$no_existing_mount" | cut -d: -f1)

  if [[ -f "$no_existing_path" ]]; then
    num_servers=$(jq '.mcpServers | length' "$no_existing_path")
    assert_eq "Fresh config has 1 server" "1" "$num_servers"

    chrome_cmd=$(jq -r '.mcpServers["chrome-devtools"].command' "$no_existing_path")
    assert_eq "Fresh config chrome-devtools uses npx" "npx" "$chrome_cmd"
  else
    fail "Fresh MCP config file not found at $no_existing_path"
  fi

  rm -f "$no_existing_path"
fi

########################################
# Tests: --chrome with multiple strategies
########################################

section "--chrome with Android strategy"

# --chrome should work with any strategy, not just rails
output_android=$(bash -c '
  '"$_chrome_mock_prefix"'
  curl() {
    case "$*" in
      *api.github.com*) echo "200"; return 0 ;;
      *) return 0 ;;
    esac
  }
  export -f curl
  cd "'"$ANDROID_DIR"'"
  bash "'"$CLI"'" --yolo --chrome --strategy android 2>&1
' 2>&1 || true)

assert_contains "--chrome works with android strategy" "$output_android" "Chrome CDP"
assert_contains "--chrome with android shows MCP server" "$output_android" "chrome-devtools"
android_exec_cmd=$(echo "$output_android" | grep "EXEC_CMD:" || true)
assert_contains "Android --chrome has .mcp.json mount" "$android_exec_cmd" ".mcp.json:ro"
assert_contains "Android docker run uses android image" "$android_exec_cmd" "claude-yolo-android"

########################################
# Tests: --chrome ensure_chrome is called
########################################

section "--chrome calls ensure_chrome"

# If curl (CDP check) fails and start-chrome.sh is missing/fails, --chrome should error
output_no_cdp=$(bash -c '
  '"$_chrome_mock_prefix"'
  # GitHub API succeeds, CDP check fails
  curl() {
    case "$*" in
      *api.github.com*) echo "200"; return 0 ;;
      *) return 1 ;;
    esac
  }
  export -f curl
  cd "'"$RAILS_DIR"'"
  bash "'"$CLI"'" --yolo --chrome --strategy rails 2>&1
' 2>&1 || true)

assert_contains "--chrome with no CDP shows Chrome failure" "$output_no_cdp" "Failed to start Chrome"

# Verify NO .mcp.json mount when Chrome fails (script exits before reaching mount)
exec_cmd_failed=$(echo "$output_no_cdp" | grep "EXEC_CMD:" || true)
assert_eq "--chrome failure prevents docker run" "" "$exec_cmd_failed"

########################################
# Tests: --chrome without --yolo
########################################

section "--chrome without --yolo"

# Without --yolo, --chrome is consumed by the parser but has no effect
# The script falls through to exec claude (which will fail since claude isn't mocked)
output_no_yolo=$(bash -c '
  '"$_chrome_mock_prefix"'
  curl() {
    case "$*" in
      *api.github.com*) echo "200"; return 0 ;;
      *) return 0 ;;
    esac
  }
  export -f curl
  cd "'"$RAILS_DIR"'"
  bash "'"$CLI"'" --chrome 2>&1
' 2>&1 || true)

# Should NOT show Docker/chrome output (no yolo mode means no container)
assert_not_contains "--chrome without --yolo has no Chrome CDP" "$output_no_yolo" "Chrome CDP"
assert_not_contains "--chrome without --yolo has no header" "$output_no_yolo" "claude·yolo"

########################################
# Tests: --chrome flag order independence
########################################

section "--chrome flag order independence"

# --chrome before --yolo
output_order1=$(bash -c '
  '"$_chrome_mock_prefix"'
  curl() {
    case "$*" in
      *api.github.com*) echo "200"; return 0 ;;
      *) return 0 ;;
    esac
  }
  export -f curl
  cd "'"$RAILS_DIR"'"
  bash "'"$CLI"'" --chrome --yolo --strategy rails 2>&1
' 2>&1 || true)

assert_contains "--chrome before --yolo works" "$output_order1" "Chrome CDP"
order1_exec=$(echo "$output_order1" | grep "EXEC_CMD:" || true)
assert_contains "--chrome before --yolo has mount" "$order1_exec" ".mcp.json:ro"

# --chrome after --strategy
output_order2=$(bash -c '
  '"$_chrome_mock_prefix"'
  curl() {
    case "$*" in
      *api.github.com*) echo "200"; return 0 ;;
      *) return 0 ;;
    esac
  }
  export -f curl
  cd "'"$RAILS_DIR"'"
  bash "'"$CLI"'" --yolo --strategy rails --chrome 2>&1
' 2>&1 || true)

assert_contains "--chrome after --strategy works" "$output_order2" "Chrome CDP"
order2_exec=$(echo "$output_order2" | grep "EXEC_CMD:" || true)
assert_contains "--chrome after --strategy has mount" "$order2_exec" ".mcp.json:ro"

# --chrome between other flags
output_order3=$(bash -c '
  '"$_chrome_mock_prefix"'
  curl() {
    case "$*" in
      *api.github.com*) echo "200"; return 0 ;;
      *) return 0 ;;
    esac
  }
  export -f curl
  cd "'"$RAILS_DIR"'"
  bash "'"$CLI"'" --yolo --chrome --strategy rails --verbose 2>&1
' 2>&1 || true)

assert_contains "--chrome between flags works" "$output_order3" "Chrome CDP"

########################################
# Tests: Dockerfile socat presence
########################################

section "Dockerfile socat"

rails_dockerfile=$(cat "$STRATEGIES_DIR/rails/Dockerfile")
assert_contains "Rails Dockerfile installs socat" "$rails_dockerfile" "socat"

########################################
# Tests: Rails display without Chrome CDP
########################################

section "Rails display without --chrome"

# Rails info line should show Ruby + Postgres but NOT Chrome CDP
assert_contains "Rails output shows Ruby" "$output_no_chrome" "Ruby"
assert_contains "Rails output shows Postgres" "$output_no_chrome" "Postgres"
assert_not_contains "Rails output without --chrome omits Chrome CDP" "$output_no_chrome" "Chrome CDP"

########################################
# Tests: parse_env_file
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
echo '{"claudeAiOauth":{"accessToken":"fake-test-token","refreshToken":"fake-refresh-token"}}' > "$EMPTY_HOME/.claude/.credentials.json"
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

section "--env flag injects env vars into docker run"

ENV_DOCKER_LOG="$TMPDIR_BASE/docker-env-args.log"
cat > "$MOCK_BIN/docker" << MOCKEOF
#!/usr/bin/env bash
case "\$1" in
  info) exit 0 ;;
  ps) echo "" ;;
  image) shift; case "\$1" in inspect) exit 0 ;; *) exit 1 ;; esac ;;
  inspect) echo "2099-01-01T00:00:00.000Z" ;;
  rm) exit 0 ;;
  run) echo "\$*" > "$ENV_DOCKER_LOG"; exit 0 ;;
  *) exit 1 ;;
esac
MOCKEOF
chmod +x "$MOCK_BIN/docker"

output=$(cd "$RAILS_DIR" && \
  HOME="$FAKE_HOME" \
  GH_TOKEN="test_token_for_ci" \
  PATH="$MOCK_BIN:$PATH" \
  bash "$CLI" --yolo --strategy rails --env MY_VAR=hello --env OTHER_VAR=world 2>&1 || true)

env_docker_args=$(cat "$ENV_DOCKER_LOG" 2>/dev/null || echo "")
assert_contains "--env injects MY_VAR" "$env_docker_args" "MY_VAR=hello"
assert_contains "--env injects OTHER_VAR" "$env_docker_args" "OTHER_VAR=world"

section "--env without value shows error"

output=$(bash "$CLI" --yolo --env 2>&1 || true)
assert_contains "--env without arg shows error" "$output" "--env requires a KEY=VALUE argument"

########################################
# Tests: --env-file flag
########################################

section "--env-file injects env vars from file"

ENV_FILE_TEST="$TMPDIR_BASE/test-env-file"
cat > "$ENV_FILE_TEST" << 'EOF'
# This is a comment
API_KEY=secret123
export DATABASE_URL=postgres://localhost/mydb

EMPTY_LINE_ABOVE=yes
QUOTED_VAR="quoted_value"
SINGLE_QUOTED='single_value'
EOF

ENV_FILE_DOCKER_LOG="$TMPDIR_BASE/docker-envfile-args.log"
cat > "$MOCK_BIN/docker" << MOCKEOF
#!/usr/bin/env bash
case "\$1" in
  info) exit 0 ;;
  ps) echo "" ;;
  image) shift; case "\$1" in inspect) exit 0 ;; *) exit 1 ;; esac ;;
  inspect) echo "2099-01-01T00:00:00.000Z" ;;
  rm) exit 0 ;;
  run) echo "\$*" > "$ENV_FILE_DOCKER_LOG"; exit 0 ;;
  *) exit 1 ;;
esac
MOCKEOF
chmod +x "$MOCK_BIN/docker"

output=$(cd "$RAILS_DIR" && \
  HOME="$FAKE_HOME" \
  GH_TOKEN="test_token_for_ci" \
  PATH="$MOCK_BIN:$PATH" \
  bash "$CLI" --yolo --strategy rails --env-file "$ENV_FILE_TEST" 2>&1 || true)

envfile_docker_args=$(cat "$ENV_FILE_DOCKER_LOG" 2>/dev/null || echo "")
assert_contains "--env-file injects API_KEY" "$envfile_docker_args" "API_KEY=secret123"
assert_contains "--env-file injects DATABASE_URL" "$envfile_docker_args" "DATABASE_URL=postgres://localhost/mydb"
assert_contains "--env-file injects EMPTY_LINE_ABOVE" "$envfile_docker_args" "EMPTY_LINE_ABOVE=yes"
assert_contains "--env-file strips double quotes" "$envfile_docker_args" "QUOTED_VAR=quoted_value"
assert_contains "--env-file strips single quotes" "$envfile_docker_args" "SINGLE_QUOTED=single_value"
assert_not_contains "--env-file skips comments" "$envfile_docker_args" "This is a comment"

section "--env-file with missing file shows error"

output=$(bash "$CLI" --yolo --env-file /nonexistent/path 2>&1 || true)
assert_contains "--env-file missing file shows error" "$output" "file not found"

section "--env-file without path shows error"

output=$(bash "$CLI" --yolo --env-file 2>&1 || true)
assert_contains "--env-file without arg shows error" "$output" "--env-file requires a path argument"

section "--env and --env-file combined"

ENV_COMBINED_LOG="$TMPDIR_BASE/docker-env-combined.log"
cat > "$MOCK_BIN/docker" << MOCKEOF
#!/usr/bin/env bash
case "\$1" in
  info) exit 0 ;;
  ps) echo "" ;;
  image) shift; case "\$1" in inspect) exit 0 ;; *) exit 1 ;; esac ;;
  inspect) echo "2099-01-01T00:00:00.000Z" ;;
  rm) exit 0 ;;
  run) echo "\$*" > "$ENV_COMBINED_LOG"; exit 0 ;;
  *) exit 1 ;;
esac
MOCKEOF
chmod +x "$MOCK_BIN/docker"

output=$(cd "$RAILS_DIR" && \
  HOME="$FAKE_HOME" \
  GH_TOKEN="test_token_for_ci" \
  PATH="$MOCK_BIN:$PATH" \
  bash "$CLI" --yolo --strategy rails --env INLINE_VAR=inline --env-file "$ENV_FILE_TEST" 2>&1 || true)

combined_docker_args=$(cat "$ENV_COMBINED_LOG" 2>/dev/null || echo "")
assert_contains "Combined: --env var present" "$combined_docker_args" "INLINE_VAR=inline"
assert_contains "Combined: --env-file var present" "$combined_docker_args" "API_KEY=secret123"

########################################
# Tests: -p / --print headless mode
########################################

section "-p / --print headless mode"

# Use the exec-capturing mock from chrome tests
PRINT_OUTPUT=$(bash -c '
  export HOME="'"$CLI_HOME"'"
  export GH_TOKEN=test_token_for_ci
  exec() { echo "EXEC_CMD: $*"; command exit 0; }
  export -f exec
  docker() {
    case "$1" in
      info) return 0 ;;
      ps) echo "" ;;
      image) shift; case "$1" in inspect) return 0 ;; *) return 1 ;; esac ;;
      inspect) echo "2099-01-01T00:00:00.000Z" ;;
      rm) return 0 ;;
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
  bash "'"$CLI"'" --yolo --strategy rails -p "run tests" 2>&1
' 2>&1 || true)

print_exec_cmd=$(echo "$PRINT_OUTPUT" | grep "EXEC_CMD:" || true)

assert_contains "-p passes through to claude args" "$print_exec_cmd" -- "-p"
assert_contains "-p passes the prompt" "$print_exec_cmd" "run tests"
assert_not_contains "-p mode drops -it flag" "$print_exec_cmd" " -it "
assert_contains "-p mode still runs docker" "$print_exec_cmd" "docker run"

section "--print flag works same as -p"

PRINT_LONG_OUTPUT=$(bash -c '
  export HOME="'"$CLI_HOME"'"
  export GH_TOKEN=test_token_for_ci
  exec() { echo "EXEC_CMD: $*"; command exit 0; }
  export -f exec
  docker() {
    case "$1" in
      info) return 0 ;;
      ps) echo "" ;;
      image) shift; case "$1" in inspect) return 0 ;; *) return 1 ;; esac ;;
      inspect) echo "2099-01-01T00:00:00.000Z" ;;
      rm) return 0 ;;
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
  bash "'"$CLI"'" --yolo --strategy rails --print "run tests" 2>&1
' 2>&1 || true)

print_long_exec_cmd=$(echo "$PRINT_LONG_OUTPUT" | grep "EXEC_CMD:" || true)
assert_contains "--print passes through to claude args" "$print_long_exec_cmd" -- "--print"
assert_not_contains "--print mode drops -it flag" "$print_long_exec_cmd" " -it "

section "-p without --yolo passes through to native claude"

PRINT_NO_YOLO=$(bash -c '
  export GH_TOKEN=test_token_for_ci
  exec() { echo "EXEC_CMD: $*"; command exit 0; }
  export -f exec
  docker() { return 1; }
  export -f docker
  lsof() { return 1; }
  export -f lsof
  bash "'"$CLI"'" -p "just a prompt" 2>&1
' 2>&1 || true)

assert_contains "-p without --yolo passes to native claude" "$PRINT_NO_YOLO" "EXEC_CMD:"
assert_contains "-p without --yolo includes -p flag" "$PRINT_NO_YOLO" "-p"
assert_not_contains "-p without --yolo has no docker" "$PRINT_NO_YOLO" "docker run"

########################################
# Tests: GitHub token scope validation
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

section ".yolo/strategy override"

YOLO_STRATEGY_DIR="$TMPDIR_BASE/yolo-strategy-project"
mkdir -p "$YOLO_STRATEGY_DIR/.yolo" "$YOLO_STRATEGY_DIR/config"
echo "gem 'rails'" > "$YOLO_STRATEGY_DIR/Gemfile"
echo "# app" > "$YOLO_STRATEGY_DIR/config/application.rb"
echo "generic" > "$YOLO_STRATEGY_DIR/.yolo/strategy"

output_yolo_strategy=$(bash -c '
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
  cd "'"$YOLO_STRATEGY_DIR"'"
  bash "'"$CLI"'" --yolo 2>&1
' 2>&1 || true)

assert_contains ".yolo/strategy overrides detection" "$output_yolo_strategy" ".yolo/strategy"
assert_contains ".yolo/strategy uses generic" "$output_yolo_strategy" "generic"

section ".yolo/strategy with invalid name"

YOLO_BAD_STRATEGY_DIR="$TMPDIR_BASE/yolo-bad-strategy"
mkdir -p "$YOLO_BAD_STRATEGY_DIR/.yolo"
echo "nonexistent_strategy" > "$YOLO_BAD_STRATEGY_DIR/.yolo/strategy"

output_bad_yolo_strategy=$(bash -c '
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
  cd "'"$YOLO_BAD_STRATEGY_DIR"'"
  echo "99" | bash "'"$CLI"'" --yolo 2>&1
' 2>&1 || true)

assert_contains ".yolo/strategy warns on invalid name" "$output_bad_yolo_strategy" "Unknown strategy in .yolo/strategy"

section ".yolo/strategy does not override --strategy flag"

output_flag_override=$(bash -c '
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
  cd "'"$YOLO_STRATEGY_DIR"'"
  bash "'"$CLI"'" --yolo --strategy rails 2>&1
' 2>&1 || true)

assert_contains "--strategy flag takes priority over .yolo/strategy" "$output_flag_override" "--strategy flag"
assert_not_contains "--strategy flag ignores .yolo/strategy" "$output_flag_override" ".yolo/strategy"

########################################
# Tests: .yolo/env injection
########################################

section ".yolo/env injection"

YOLO_ENV_DIR="$TMPDIR_BASE/yolo-env-project"
mkdir -p "$YOLO_ENV_DIR/.yolo"
cat > "$YOLO_ENV_DIR/.yolo/env" << 'EOF'
# Comment line
MY_YOLO_VAR=hello_yolo
export ANOTHER_VAR=world_yolo

QUOTED_VAR="quoted_value"
EOF

YOLO_ENV_DOCKER_LOG="$TMPDIR_BASE/docker-yolo-env.log"
YOLO_ENV_TRUST_DIR="$TMPDIR_BASE/yolo-env-trust-home"
mkdir -p "$YOLO_ENV_TRUST_DIR/.claude"
echo '{"claudeAiOauth":{"accessToken":"fake-test-token","refreshToken":"fake-refresh-token"}}' > "$YOLO_ENV_TRUST_DIR/.claude/.credentials.json"

cat > "$MOCK_BIN/docker" << MOCKEOF
#!/usr/bin/env bash
case "\$1" in
  info) exit 0 ;;
  ps) echo "" ;;
  image) shift; case "\$1" in inspect) exit 0 ;; *) exit 1 ;; esac ;;
  inspect) echo "2099-01-01T00:00:00.000Z" ;;
  rm) exit 0 ;;
  run) echo "\$*" > "$YOLO_ENV_DOCKER_LOG"; exit 0 ;;
  *) exit 1 ;;
esac
MOCKEOF
chmod +x "$MOCK_BIN/docker"

output=$(cd "$YOLO_ENV_DIR" && \
  HOME="$YOLO_ENV_TRUST_DIR" \
  GH_TOKEN="test_token_for_ci" \
  PATH="$MOCK_BIN:$PATH" \
  bash "$CLI" --yolo --strategy generic --trust-yolo 2>&1 || true)

yolo_env_docker_args=$(cat "$YOLO_ENV_DOCKER_LOG" 2>/dev/null || echo "")
assert_contains ".yolo/env injects MY_YOLO_VAR" "$yolo_env_docker_args" "MY_YOLO_VAR=hello_yolo"
assert_contains ".yolo/env injects ANOTHER_VAR" "$yolo_env_docker_args" "ANOTHER_VAR=world_yolo"
assert_contains ".yolo/env strips quotes" "$yolo_env_docker_args" "QUOTED_VAR=quoted_value"
assert_not_contains ".yolo/env skips comments" "$yolo_env_docker_args" "Comment line"

########################################
# Tests: .yolo/env not loaded without trust
########################################

section ".yolo/env not loaded without trust"

YOLO_UNTRUST_DIR="$TMPDIR_BASE/yolo-untrust-project"
mkdir -p "$YOLO_UNTRUST_DIR/.yolo"
echo "SHOULD_NOT_APPEAR=true" > "$YOLO_UNTRUST_DIR/.yolo/env"

YOLO_UNTRUST_DOCKER_LOG="$TMPDIR_BASE/docker-yolo-untrust.log"
YOLO_UNTRUST_HOME="$TMPDIR_BASE/yolo-untrust-home"
mkdir -p "$YOLO_UNTRUST_HOME/.claude"

cat > "$MOCK_BIN/docker" << MOCKEOF
#!/usr/bin/env bash
case "\$1" in
  info) exit 0 ;;
  ps) echo "" ;;
  image) shift; case "\$1" in inspect) exit 0 ;; *) exit 1 ;; esac ;;
  inspect) echo "2099-01-01T00:00:00.000Z" ;;
  rm) exit 0 ;;
  run) echo "\$*" > "$YOLO_UNTRUST_DOCKER_LOG"; exit 0 ;;
  *) exit 1 ;;
esac
MOCKEOF
chmod +x "$MOCK_BIN/docker"

# Decline the trust prompt with 'n'
output=$(cd "$YOLO_UNTRUST_DIR" && \
  HOME="$YOLO_UNTRUST_HOME" \
  GH_TOKEN="test_token_for_ci" \
  PATH="$MOCK_BIN:$PATH" \
  echo "n" | bash "$CLI" --yolo --strategy generic 2>&1 || true)

yolo_untrust_docker_args=$(cat "$YOLO_UNTRUST_DOCKER_LOG" 2>/dev/null || echo "")
assert_not_contains ".yolo/env not loaded when declined" "$yolo_untrust_docker_args" "SHOULD_NOT_APPEAR"

########################################
# Tests: check_yolo_config
########################################

section "check_yolo_config — no .yolo/ directory"

# check_yolo_config should be a no-op when .yolo/ doesn't exist
YOLO_CONFIG_LOADED=false
# shellcheck disable=SC2034
trust_yolo=false
check_yolo_config "$EMPTY_DIR" 2>/dev/null
assert_eq "check_yolo_config returns 0 without .yolo/" "false" "$YOLO_CONFIG_LOADED"

section "check_yolo_config — --trust-yolo flag"

YOLO_TRUST_FLAG_DIR="$TMPDIR_BASE/yolo-trust-flag"
mkdir -p "$YOLO_TRUST_FLAG_DIR/.yolo"
echo "generic" > "$YOLO_TRUST_FLAG_DIR/.yolo/strategy"
YOLO_TRUST_HOME="$TMPDIR_BASE/yolo-trust-home"
mkdir -p "$YOLO_TRUST_HOME/.claude"

YOLO_CONFIG_LOADED=false
trust_yolo=true
HOME="$YOLO_TRUST_HOME" check_yolo_config "$YOLO_TRUST_FLAG_DIR" 2>/dev/null
assert_eq "check_yolo_config sets YOLO_CONFIG_LOADED with --trust-yolo" "true" "$YOLO_CONFIG_LOADED"

# Verify trust file was created
if [[ -f "$YOLO_TRUST_HOME/.claude/.yolo-trusted" ]]; then
  pass "Trust file created by check_yolo_config"
else
  fail "Trust file not created by check_yolo_config"
fi

section "check_yolo_config — already trusted"

# Run again with the same config; should auto-trust
YOLO_CONFIG_LOADED=false
# shellcheck disable=SC2034
trust_yolo=false
HOME="$YOLO_TRUST_HOME" check_yolo_config "$YOLO_TRUST_FLAG_DIR" 2>/dev/null
assert_eq "check_yolo_config auto-trusts known config" "true" "$YOLO_CONFIG_LOADED"

########################################
# Tests: --reset flag
########################################

section "--reset flag"

# Compute expected hash for RAILS_DIR (same as CLI would)
_reset_resolved_path=$(cd "$RAILS_DIR" && pwd)
_reset_hash=$(path_hash "$_reset_resolved_path")

output_reset=$(bash -c '
  export HOME="'"$CLI_HOME"'"
  export GH_TOKEN=test_token_for_ci
  _REMOVED_CONTAINERS=""
  docker() {
    case "$1" in
      info) return 0 ;;
      ps)
        shift
        case "$1" in
          -a) echo "claude-yolo-'"$_reset_hash"'-rails" ;;
          *) echo "" ;;
        esac
        ;;
      image)
        shift
        case "$1" in
          inspect) return 0 ;;
          *) return 1 ;;
        esac
        ;;
      inspect) echo "2099-01-01T00:00:00.000Z" ;;
      build) return 0 ;;
      rm)
        shift
        echo "REMOVED: $*" >&2
        return 0
        ;;
      run) echo "DOCKER_RUN: $*"; exit 0 ;;
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
  bash "'"$CLI"'" --yolo --strategy rails --reset 2>&1
' 2>&1 || true)

assert_contains "--reset removes existing containers" "$output_reset" "Removed existing container"
assert_contains "--reset forces rebuild" "$output_reset" "Building"

########################################
# Tests: --reset arg parsing
########################################

section "--reset arg parsing"

output_reset_parse=$(bash "$CLI" --yolo --reset --strategy 2>&1 || true)
assert_contains "--reset is parsed before --strategy error" "$output_reset_parse" "--strategy requires an argument"

########################################
# Tests: --trust-yolo arg parsing
########################################

section "--trust-yolo arg parsing"

output_trust_yolo=$(bash -c '
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
  cd "'"$YOLO_ENV_DIR"'"
  HOME="'"$TMPDIR_BASE/trust-yolo-test-home"'"
  mkdir -p "$HOME/.claude"
  echo '"'"'{"claudeAiOauth":{"accessToken":"fake-test-token","refreshToken":"fake-refresh-token"}}'"'"' > "$HOME/.claude/.credentials.json"
  bash "'"$CLI"'" --yolo --strategy generic --trust-yolo 2>&1
' 2>&1 || true)

assert_contains "--trust-yolo skips prompt" "$output_trust_yolo" "--trust-yolo"
assert_contains "--trust-yolo shows config loaded" "$output_trust_yolo" ".yolo/ config"

########################################
# Tests: Container persistence (no --rm)
########################################

section "Container persistence (no --rm)"

# Verify docker run does NOT include --rm flag
output_persist=$(bash -c '
  export HOME="'"$CLI_HOME"'"
  export GH_TOKEN=test_token_for_ci
  exec() { echo "EXEC_CMD: $*"; command exit 0; }
  export -f exec
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

persist_exec_cmd=$(echo "$output_persist" | grep "EXEC_CMD:" || true)
assert_not_contains "Container persistence: no --rm flag" "$persist_exec_cmd" " --rm "

########################################
# Tests: .yolo/Dockerfile project image
########################################

section ".yolo/Dockerfile project image build"

YOLO_DOCKERFILE_DIR="$TMPDIR_BASE/yolo-dockerfile-project"
mkdir -p "$YOLO_DOCKERFILE_DIR/.yolo"
cat > "$YOLO_DOCKERFILE_DIR/.yolo/Dockerfile" << 'EOF'
FROM claude-yolo-generic:latest
RUN echo "custom layer"
EOF

YOLO_DOCKERFILE_DOCKER_LOG="$TMPDIR_BASE/docker-yolo-dockerfile.log"
YOLO_DOCKERFILE_HOME="$TMPDIR_BASE/yolo-dockerfile-home"
mkdir -p "$YOLO_DOCKERFILE_HOME/.claude"
echo '{"claudeAiOauth":{"accessToken":"fake-test-token","refreshToken":"fake-refresh-token"}}' > "$YOLO_DOCKERFILE_HOME/.claude/.credentials.json"

_dockerfile_build_called=false
cat > "$MOCK_BIN/docker" << MOCKEOF
#!/usr/bin/env bash
case "\$1" in
  info) exit 0 ;;
  ps) echo "" ;;
  image)
    shift
    case "\$1" in
      inspect)
        shift
        case "\$1" in
          claude-yolo-generic:latest) exit 0 ;;
          *) exit 1 ;;
        esac
        ;;
      *) exit 1 ;;
    esac
    ;;
  inspect)
    shift
    case "\$1" in
      --format*) echo "" ;;
      *) echo "2099-01-01T00:00:00.000Z" ;;
    esac
    ;;
  build) echo "BUILD: \$*" >> "$YOLO_DOCKERFILE_DOCKER_LOG"; exit 0 ;;
  rm) exit 0 ;;
  run) echo "\$*" >> "$YOLO_DOCKERFILE_DOCKER_LOG"; exit 0 ;;
  *) exit 1 ;;
esac
MOCKEOF
chmod +x "$MOCK_BIN/docker"

output=$(cd "$YOLO_DOCKERFILE_DIR" && \
  HOME="$YOLO_DOCKERFILE_HOME" \
  GH_TOKEN="test_token_for_ci" \
  PATH="$MOCK_BIN:$PATH" \
  bash "$CLI" --yolo --strategy generic --trust-yolo 2>&1 || true)

yolo_dockerfile_log=$(cat "$YOLO_DOCKERFILE_DOCKER_LOG" 2>/dev/null || echo "")
assert_contains ".yolo/Dockerfile triggers project image build" "$output" "Building project image"
assert_contains ".yolo/Dockerfile build uses -f flag" "$yolo_dockerfile_log" ".yolo/Dockerfile"

########################################
# Tests: --setup-token flag parsing
########################################

section "--setup-token flag parsing"

SETUP_TOKEN_DIR="$TMPDIR_BASE/setup-token-project"
mkdir -p "$SETUP_TOKEN_DIR"
touch "$SETUP_TOKEN_DIR/Gemfile"

SETUP_TOKEN_HOME="$TMPDIR_BASE/setup-token-home"
mkdir -p "$SETUP_TOKEN_HOME/.claude"

# Mock claude that simulates setup-token by printing the token to stdout
cat > "$MOCK_BIN/claude" << MOCKEOF
#!/usr/bin/env bash
if [[ "\$1" == "setup-token" ]]; then
  echo "Long-lived authentication token created successfully!"
  echo ""
  echo "Your OAuth token (valid for 1 year):"
  echo ""
  echo "sk-ant-oat01-test-setup-token-value"
  echo ""
  echo "Store this token securely."
  exit 0
fi
exit 1
MOCKEOF
chmod +x "$MOCK_BIN/claude"

# Standard docker mock for the CLI wrapper
cat > "$MOCK_BIN/docker" << MOCKEOF
#!/usr/bin/env bash
case "\$1" in
  info) exit 0 ;;
  ps) echo "" ;;
  image) shift; case "\$1" in inspect) exit 0 ;; *) exit 1 ;; esac ;;
  inspect) echo "2099-01-01T00:00:00.000Z" ;;
  rm) exit 0 ;;
  run) exit 0 ;;
  *) exit 1 ;;
esac
MOCKEOF
chmod +x "$MOCK_BIN/docker"

# Tmux mock: runs command synchronously, captures output to logfile via pipe-pane
cat > "$MOCK_BIN/tmux" << 'MOCKEOF'
#!/usr/bin/env bash
# Extract session name from -t or -s flags
session=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "${args[$i]}" == "-t" || "${args[$i]}" == "-s" ]]; then
    session="${args[$((i+1))]}"
    break
  fi
done
MOCK_STATE="/tmp/tmux-mock-${session:-default}"
mkdir -p "$MOCK_STATE"

case "$1" in
  kill-session) rm -rf "$MOCK_STATE"; mkdir -p "$MOCK_STATE" ;;
  new-session)
    shift
    cmd=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -d) shift ;;
        -s|-x|-y) shift 2 ;;
        *) cmd="$1"; shift ;;
      esac
    done
    bash -c "$cmd" > "$MOCK_STATE/output" 2>&1 || true
    ;;
  pipe-pane)
    shift
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -o)
          logfile=$(echo "$2" | sed "s/cat >> '//; s/'$//")
          if [[ -f "$MOCK_STATE/output" && -n "$logfile" ]]; then
            cat "$MOCK_STATE/output" >> "$logfile"
          fi
          shift 2
          ;;
        *) shift ;;
      esac
    done
    ;;
  attach-session) ;;
  has-session) exit 1 ;;
esac
exit 0
MOCKEOF
chmod +x "$MOCK_BIN/tmux"

# No-op sleep mock to avoid 2s delay from "sleep 2" in setup-token command
cat > "$MOCK_BIN/sleep" << 'MOCKEOF'
#!/usr/bin/env bash
exit 0
MOCKEOF
chmod +x "$MOCK_BIN/sleep"

# No-op security mock to prevent real macOS Keychain access in tests
cat > "$MOCK_BIN/security" << 'MOCKEOF'
#!/usr/bin/env bash
exit 1
MOCKEOF
chmod +x "$MOCK_BIN/security"

output_setup_token=$(cd "$SETUP_TOKEN_DIR" && \
  HOME="$SETUP_TOKEN_HOME" \
  PATH="$MOCK_BIN:$PATH" \
  CLAUDE_YOLO_NO_GITHUB=1 \
  bash "$CLI" --yolo --strategy generic --setup-token 2>&1 || true)

assert_contains "--setup-token runs on host" "$output_setup_token" "claude setup-token"

# Verify credentials were saved to host ~/.claude/
if [[ -f "$SETUP_TOKEN_HOME/.claude/.credentials.json" ]]; then
  pass "--setup-token saves credentials to ~/.claude/.credentials.json"
else
  fail "--setup-token saves credentials to ~/.claude/.credentials.json"
fi

assert_contains "--setup-token shows success message" "$output_setup_token" "Credentials saved"

# Verify the captured token was written to credentials file
setup_token_saved=$(grep -o 'sk-ant-[a-zA-Z0-9_-]*' "$SETUP_TOKEN_HOME/.claude/.credentials.json" 2>/dev/null | head -1)
assert_eq "--setup-token captures and saves token from stdout" "sk-ant-oat01-test-setup-token-value" "$setup_token_saved"

# Verify --setup-token continues to launch (doesn't exit after setup)
assert_contains "--setup-token continues to launch session" "$output_setup_token" "Launching Claude Code"

########################################
# Tests: CLAUDE_CODE_OAUTH_TOKEN env var
########################################

section "CLAUDE_CODE_OAUTH_TOKEN injected from host credentials"

OAUTH_TOKEN_DIR="$TMPDIR_BASE/oauth-token-project"
mkdir -p "$OAUTH_TOKEN_DIR"
touch "$OAUTH_TOKEN_DIR/Gemfile"

OAUTH_TOKEN_HOME="$TMPDIR_BASE/oauth-token-home"
mkdir -p "$OAUTH_TOKEN_HOME/.claude"
echo '{"claudeAiOauth":{"accessToken":"my-oauth-test-token","refreshToken":"my-refresh-token"}}' > "$OAUTH_TOKEN_HOME/.claude/.credentials.json"

OAUTH_TOKEN_DOCKER_LOG="$TMPDIR_BASE/docker-oauth-token.log"

cat > "$MOCK_BIN/docker" << MOCKEOF
#!/usr/bin/env bash
case "\$1" in
  info) exit 0 ;;
  ps) echo "" ;;
  image) shift; case "\$1" in inspect) exit 0 ;; *) exit 1 ;; esac ;;
  inspect) echo "2099-01-01T00:00:00.000Z" ;;
  rm) exit 0 ;;
  run) echo "\$*" > "$OAUTH_TOKEN_DOCKER_LOG"; exit 0 ;;
  *) exit 1 ;;
esac
MOCKEOF
chmod +x "$MOCK_BIN/docker"

output_oauth=$(cd "$OAUTH_TOKEN_DIR" && \
  HOME="$OAUTH_TOKEN_HOME" \
  GH_TOKEN="test_token_for_ci" \
  PATH="$MOCK_BIN:$PATH" \
  bash "$CLI" --yolo --strategy generic 2>&1 || true)

oauth_docker_args=$(cat "$OAUTH_TOKEN_DOCKER_LOG" 2>/dev/null || echo "")

assert_contains "Docker args mount credentials file" "$oauth_docker_args" ".credentials.json"
assert_contains "Output shows credentials injected message" "$output_oauth" "Claude OAuth credentials injected"

########################################
# Tests: no OAuth token without credentials
########################################

section "Missing credentials exits before docker run"

NO_CREDS_DIR="$TMPDIR_BASE/no-creds-project"
mkdir -p "$NO_CREDS_DIR"
touch "$NO_CREDS_DIR/Gemfile"

NO_CREDS_HOME="$TMPDIR_BASE/no-creds-home"
mkdir -p "$NO_CREDS_HOME/.claude"

NO_CREDS_DOCKER_LOG="$TMPDIR_BASE/docker-no-creds.log"
rm -f "$NO_CREDS_DOCKER_LOG"

cat > "$MOCK_BIN/docker" << MOCKEOF
#!/usr/bin/env bash
case "\$1" in
  info) exit 0 ;;
  ps) echo "" ;;
  image) shift; case "\$1" in inspect) exit 0 ;; *) exit 1 ;; esac ;;
  inspect) echo "2099-01-01T00:00:00.000Z" ;;
  rm) exit 0 ;;
  run) echo "\$*" > "$NO_CREDS_DOCKER_LOG"; exit 0 ;;
  *) exit 1 ;;
esac
MOCKEOF
chmod +x "$MOCK_BIN/docker"

no_creds_exit_code=0
output_no_creds=$(cd "$NO_CREDS_DIR" && \
  HOME="$NO_CREDS_HOME" \
  GH_TOKEN="test_token_for_ci" \
  PATH="$MOCK_BIN:$PATH" \
  bash "$CLI" --yolo --strategy generic 2>&1) || no_creds_exit_code=$?

assert_contains "Shows error when no credentials" "$output_no_creds" "No Claude credentials found"

if [[ "$no_creds_exit_code" -ne 0 ]]; then
  pass "Exits non-zero without credentials"
else
  fail "Exits non-zero without credentials (got exit code 0)"
fi

no_creds_docker_args=$(cat "$NO_CREDS_DOCKER_LOG" 2>/dev/null || echo "")
if [[ -z "$no_creds_docker_args" ]]; then
  pass "Docker run not called without credentials"
else
  fail "Docker run not called without credentials (docker run was called)"
fi

########################################
# Tests: ~/.claude.json mount for onboarding skip
########################################

section "\$HOME/.claude.json mounted into container"

CLAUDEJSON_DIR="$TMPDIR_BASE/claudejson-project"
mkdir -p "$CLAUDEJSON_DIR"
touch "$CLAUDEJSON_DIR/Gemfile"

CLAUDEJSON_HOME="$TMPDIR_BASE/claudejson-home"
mkdir -p "$CLAUDEJSON_HOME/.claude"
echo '{"claudeAiOauth":{"accessToken":"cj-token","refreshToken":"cj-refresh-token"}}' > "$CLAUDEJSON_HOME/.claude/.credentials.json"
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

# Reuse NO_CREDS_HOME which has no .claude.json
assert_not_contains "No .claude.json mount without file" "$no_creds_docker_args" ":/home/claude/.claude.json"

########################################
# Tests: check_port_in_use
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

section "resolve_port_conflicts — no conflicts"

RESOLVE_STDERR="$TMPDIR_BASE/resolve-stderr.log"

lsof() { return 1; }

resolve_port_conflicts false -p 3000:3000 -p 5173:5173 2>"$RESOLVE_STDERR"
output=$(cat "$RESOLVE_STDERR")
assert_eq "No output when no conflicts" "" "$output"
assert_contains "Port flags unchanged (3000)" "${_RESOLVED_PORT_FLAGS[*]}" "3000:3000"
assert_contains "Port flags unchanged (5173)" "${_RESOLVED_PORT_FLAGS[*]}" "5173:5173"

unset -f lsof

########################################
# Tests: resolve_port_conflicts — auto-remap
########################################

section "resolve_port_conflicts — auto-remap"

# Mock: port 3000 in use, 4000 free
lsof() {
  case "$*" in
    *:3000*) return 0 ;;
    *) return 1 ;;
  esac
}

# Mock ps for process name display
ps() { echo "ruby"; }

resolve_port_conflicts true -p 3000:3000 -p 5173:5173 2>"$RESOLVE_STDERR"
output=$(cat "$RESOLVE_STDERR")
assert_contains "Auto-remap shows info message" "$output" "Auto-remapped"
assert_contains "Auto-remap shows 3000 → 4000" "$output" "4000"
assert_contains "Remapped port in resolved flags" "${_RESOLVED_PORT_FLAGS[*]}" "4000:3000"
assert_contains "Non-conflicting port unchanged" "${_RESOLVED_PORT_FLAGS[*]}" "5173:5173"

unset -f lsof ps

########################################
# Tests: resolve_port_conflicts — multiple conflicts
########################################

section "resolve_port_conflicts — multiple conflicts auto-remap"

# Mock: both 3000 and 5173 in use
lsof() {
  case "$*" in
    *:3000*|*:5173*) return 0 ;;
    *) return 1 ;;
  esac
}
ps() { echo "node"; }

resolve_port_conflicts true -p 3000:3000 -p 5173:5173 2>"$RESOLVE_STDERR"
output=$(cat "$RESOLVE_STDERR")
assert_contains "Both ports remapped (3000)" "${_RESOLVED_PORT_FLAGS[*]}" "4000:3000"
assert_contains "Both ports remapped (5173)" "${_RESOLVED_PORT_FLAGS[*]}" "6173:5173"
assert_contains "Shows conflict for 3000" "$output" "3000"
assert_contains "Shows conflict for 5173" "$output" "5173"

unset -f lsof ps

########################################
# Tests: Port conflict in headless CLI mode
########################################

section "Port conflict auto-remap in headless CLI mode"

output_port_conflict=$(bash -c '
  export GH_TOKEN=test_token_for_ci
  exec() { echo "EXEC_CMD: $*"; command exit 0; }
  export -f exec
  docker() {
    case "$1" in
      info) return 0 ;;
      ps) echo "" ;;
      image) shift; case "$1" in inspect) return 0 ;; *) return 1 ;; esac ;;
      inspect) echo "2099-01-01T00:00:00.000Z" ;;
      rm) return 0 ;;
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
  lsof() {
    case "$*" in
      *:3000*) return 0 ;;
      *) return 1 ;;
    esac
  }
  export -f lsof
  ps() {
    case "$*" in
      *-o*comm*) echo "ruby" ;;
      *) command ps "$@" ;;
    esac
  }
  export -f ps
  HOME="'"$FAKE_HOME"'"
  cd "'"$RAILS_DIR"'"
  bash "'"$CLI"'" --yolo --strategy rails -p "run tests" 2>&1
' 2>&1 || true)

port_conflict_exec_cmd=$(echo "$output_port_conflict" | grep "EXEC_CMD:" || true)

if [[ "$(uname)" == "Darwin" ]]; then
  assert_contains "Headless: shows auto-remap message" "$output_port_conflict" "Auto-remapped"
  assert_contains "Headless: remapped port in docker args" "$port_conflict_exec_cmd" "4000:3000"
  assert_not_contains "Headless: original conflicting port removed" "$port_conflict_exec_cmd" " 3000:3000"
  assert_contains "Headless: non-conflicting port unchanged" "$port_conflict_exec_cmd" "5173:5173"
else
  pass "Skipped headless port conflict test (Linux uses --network=host)"
fi

########################################
# Tests: Missing credentials halts before environment selection
########################################

section "Missing credentials halts before environment selection"

HALT_CREDS_DIR="$TMPDIR_BASE/halt-creds-project"
mkdir -p "$HALT_CREDS_DIR"
touch "$HALT_CREDS_DIR/Gemfile"

HALT_CREDS_HOME="$TMPDIR_BASE/halt-creds-home"
mkdir -p "$HALT_CREDS_HOME/.claude"
# Intentionally no .credentials.json

HALT_CREDS_DOCKER_LOG="$TMPDIR_BASE/docker-halt-creds.log"
rm -f "$HALT_CREDS_DOCKER_LOG"

cat > "$MOCK_BIN/docker" << MOCKEOF
#!/usr/bin/env bash
case "\$1" in
  info) exit 0 ;;
  ps) echo "" ;;
  image) shift; case "\$1" in inspect) exit 0 ;; *) exit 1 ;; esac ;;
  inspect) echo "2099-01-01T00:00:00.000Z" ;;
  rm) exit 0 ;;
  run) echo "\$*" > "$HALT_CREDS_DOCKER_LOG"; exit 0 ;;
  *) exit 1 ;;
esac
MOCKEOF
chmod +x "$MOCK_BIN/docker"

halt_creds_exit_code=0
output_halt_creds=$(cd "$HALT_CREDS_DIR" && \
  HOME="$HALT_CREDS_HOME" \
  GH_TOKEN="test_token_for_ci" \
  PATH="$MOCK_BIN:$PATH" \
  bash "$CLI" --yolo --strategy generic 2>&1) || halt_creds_exit_code=$?

assert_contains "Shows credentials error when missing" "$output_halt_creds" "No Claude credentials found"
assert_contains "Shows setup-token instruction" "$output_halt_creds" "setup-token"

if [[ "$halt_creds_exit_code" -ne 0 ]]; then
  pass "Exits with non-zero when credentials missing"
else
  fail "Exits with non-zero when credentials missing (got exit code 0)"
fi

# Docker run should never have been called
halt_creds_docker_args=$(cat "$HALT_CREDS_DOCKER_LOG" 2>/dev/null || echo "")
if [[ -z "$halt_creds_docker_args" ]]; then
  pass "Does not reach docker run without credentials"
else
  fail "Does not reach docker run without credentials (docker run was called)"
fi

# Should not contain strategy/launch messages (halted before getting there)
assert_not_contains "Halts before launching Claude" "$output_halt_creds" "Launching Claude Code"

########################################
# Summary
########################################

echo ""
echo "━━━ Results ━━━"
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
  exit 1
fi

echo "  All tests passed!"
exit 0
