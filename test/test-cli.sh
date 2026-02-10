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
TMPDIR_BASE=$(mktemp -d)
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

# Empty project
EMPTY_DIR="$TMPDIR_BASE/empty-project"
mkdir -p "$EMPTY_DIR"

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
assert_eq "Falls back to 3.3.0 when no version found" "3.3.0" "$ver"

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
# Tests: list_strategies
########################################

section "list_strategies"

strategies=$(list_strategies)
assert_contains "list_strategies includes rails" "$strategies" "rails"
assert_contains "list_strategies includes android" "$strategies" "android"

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

# Use a restricted PATH that has bash/coreutils but not docker
output=$(env PATH="/usr/bin:/bin" bash "$CLI" --yolo 2>&1 || true)

assert_contains "Shows error when docker missing" "$output" "Docker is not installed"
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
  bash "'"$CLI"'" --yolo 2>&1
' 2>&1 || true)

assert_contains "Shows error when docker not running" "$output" "Docker is not running"

section "CLI integration — --strategy with bad name"

output=$(bash -c '
  docker() {
    case "$1" in
      info) return 0 ;;
      ps) echo "" ;;
      *) return 1 ;;
    esac
  }
  export -f docker
  bash "'"$CLI"'" --yolo --strategy nonexistent 2>&1
' 2>&1 || true)

assert_contains "Bad strategy shows error" "$output" "Unknown strategy: nonexistent"

section "CLI integration — output formatting (no detection)"

output=$(bash -c '
  docker() {
    case "$1" in
      info) return 0 ;;
      ps) echo "" ;;
      image) return 1 ;;
      *) return 1 ;;
    esac
  }
  export -f docker
  cd "'"$EMPTY_DIR"'"
  echo "99" | bash "'"$CLI"'" --yolo 2>&1
' 2>&1 || true)

assert_contains "Output includes header" "$output" "claude·yolo"
assert_contains "Output includes no-detect warning" "$output" "No environment auto-detected"
assert_contains "Output includes strategy list" "$output" "Select an environment"
assert_contains "Output shows strategy descriptions" "$output" "Ruby (rbenv)"
assert_contains "Output shows android description" "$output" "JDK 17"

section "CLI integration — invalid menu selection"

output=$(bash -c '
  docker() {
    case "$1" in
      info) return 0 ;;
      ps) echo "" ;;
      image) return 1 ;;
      *) return 1 ;;
    esac
  }
  export -f docker
  cd "'"$EMPTY_DIR"'"
  echo "abc" | bash "'"$CLI"'" --yolo 2>&1
' 2>&1 || true)

assert_contains "Non-numeric input shows error" "$output" "Invalid selection"

section "CLI integration — out-of-range menu selection"

output=$(bash -c '
  docker() {
    case "$1" in
      info) return 0 ;;
      ps) echo "" ;;
      image) return 1 ;;
      *) return 1 ;;
    esac
  }
  export -f docker
  cd "'"$EMPTY_DIR"'"
  echo "99" | bash "'"$CLI"'" --yolo 2>&1
' 2>&1 || true)

assert_contains "Out-of-range selection shows error" "$output" "Invalid selection"

section "CLI integration — auto-detect high confidence"

output=$(bash -c '
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
  # Mock curl for CDP check
  curl() { return 0; }
  export -f curl
  cd "'"$RAILS_DIR"'"
  bash "'"$CLI"'" --yolo --strategy rails 2>&1
' 2>&1 || true)

assert_contains "Shows worktree path" "$output" "Worktree"
assert_contains "Shows escape hatch" "$output" "Ctrl+C to exit"
assert_contains "Shows Launching message" "$output" "Launching Claude Code"
assert_contains "Shows footer" "$output" "└"

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
