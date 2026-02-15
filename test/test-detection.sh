#!/usr/bin/env bash
#
# Strategy detection tests using static fixture environments
#
# Usage:
#   ./test/test-detection.sh
#
# Each fixture in test/fixtures/environments/ is a directory with empty marker
# files that mimic a real project. Tests verify that each strategy's detect.sh
# returns high confidence for its own environment and low confidence for others.

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$TEST_DIR")"
STRATEGIES_DIR="$REPO_DIR/strategies"
FIXTURES_DIR="$TEST_DIR/fixtures/environments"

########################################
# Test framework
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

section() {
  echo ""
  echo "━━━ $1 ━━━"
}

# Run a strategy's detect.sh against a fixture, return confidence as integer
detect() {
  local strategy="$1" fixture="$2"
  local output
  output=$("$STRATEGIES_DIR/$strategy/detect.sh" "$FIXTURES_DIR/$fixture" 2>/dev/null)
  echo "$output" | grep '^CONFIDENCE:' | cut -d: -f2
}

# Assert confidence is at or above a threshold
assert_high() {
  local description="$1" confidence="$2" threshold="${3:-80}"
  if [[ "$confidence" -ge "$threshold" ]]; then
    pass "$description ($confidence%)"
  else
    fail "$description (expected ≥${threshold}%, got $confidence%)"
  fi
}

# Assert confidence is below a threshold
assert_low() {
  local description="$1" confidence="$2" threshold="${3:-80}"
  if [[ "$confidence" -lt "$threshold" ]]; then
    pass "$description ($confidence%)"
  else
    fail "$description (expected <${threshold}%, got $confidence%)"
  fi
}

########################################
# Jekyll detection
########################################

section "Jekyll — matches own environment"

conf=$(detect jekyll jekyll-full)
assert_high "Jekyll detects full Jekyll project" "$conf"

section "Jekyll — weak signal"

conf=$(detect jekyll jekyll-weak)
assert_low "Jekyll <80% for bare _config.yml" "$conf"

section "Jekyll — no false positives"

conf=$(detect jekyll rails-full)
assert_low "Jekyll rejects Rails project" "$conf" 1

conf=$(detect jekyll node-full)
assert_low "Jekyll rejects Node project" "$conf" 1

conf=$(detect jekyll python-full)
assert_low "Jekyll rejects Python project" "$conf" 1

conf=$(detect jekyll empty)
assert_low "Jekyll rejects empty dir" "$conf" 1

########################################
# Rails detection
########################################

section "Rails — matches own environment"

conf=$(detect rails rails-full)
assert_high "Rails detects full Rails project" "$conf"

section "Rails — no false positives"

conf=$(detect rails jekyll-full)
assert_low "Rails rejects Jekyll project" "$conf"

conf=$(detect rails node-full)
assert_low "Rails rejects Node project" "$conf"

conf=$(detect rails python-full)
assert_low "Rails rejects Python project" "$conf"

conf=$(detect rails empty)
assert_low "Rails rejects empty dir" "$conf" 1

########################################
# Node detection
########################################

section "Node — matches own environment"

conf=$(detect node node-full)
assert_high "Node detects full Node project" "$conf"

section "Node — no false positives"

conf=$(detect node jekyll-full)
assert_low "Node rejects Jekyll project" "$conf"

conf=$(detect node rails-full)
assert_low "Node rejects Rails project" "$conf"

conf=$(detect node python-full)
assert_low "Node rejects Python project" "$conf"

conf=$(detect node empty)
assert_low "Node rejects empty dir" "$conf" 1

########################################
# Python detection
########################################

section "Python — matches own environment"

conf=$(detect python python-full)
assert_high "Python detects full Python project" "$conf"

section "Python — no false positives"

conf=$(detect python jekyll-full)
assert_low "Python rejects Jekyll project" "$conf" 1

conf=$(detect python rails-full)
assert_low "Python rejects Rails project" "$conf" 1

conf=$(detect python node-full)
assert_low "Python rejects Node project" "$conf" 1

conf=$(detect python empty)
assert_low "Python rejects empty dir" "$conf" 1

########################################
# Summary
########################################

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
total=$((_PASS + _FAIL))
echo "  $total tests: $_PASS passed, $_FAIL failed"

if [[ ${#_ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "  Failures:"
  for err in "${_ERRORS[@]}"; do
    echo "    - $err"
  done
  echo ""
  exit 1
fi

echo ""
