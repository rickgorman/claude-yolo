#!/usr/bin/env bash
#
# Run all claude-yolo test suites
#
# Usage:
#   ./test/run-all-tests.sh
#   ./test/run-all-tests.sh test-basic.sh test-ports.sh  # Run specific tests
#

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Test files in recommended run order
TEST_FILES=(
  "test-basic.sh"
  "test-helpers.sh"
  "test-strategy-detection.sh"
  "test-version-detection.sh"
  "test-dockerfiles.sh"
  "test-github-token.sh"
  "test-git-config.sh"
  "test-yolo-config.sh"
  "test-ports.sh"
  "test-flags.sh"
  "test-mounting.sh"
  "test-cli-integration.sh"
)

# Allow running specific tests
if [[ $# -gt 0 ]]; then
  TEST_FILES=("$@")
fi

# Track overall results
TOTAL_PASSED=0
TOTAL_FAILED=0
FAILED_SUITES=()

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Running Claude YOLO Test Suite"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for test_file in "${TEST_FILES[@]}"; do
  test_path="$TEST_DIR/$test_file"

  if [[ ! -f "$test_path" ]]; then
    echo "⚠️  Skipping $test_file (not found)"
    continue
  fi

  echo "▶ Running $test_file..."
  echo ""

  if output=$("$test_path" 2>&1); then
    # Parse results from output
    passed=$(echo "$output" | grep "Passed:" | awk '{print $2}')
    echo "$output" | tail -6
    TOTAL_PASSED=$((TOTAL_PASSED + passed))
  else
    # Test suite failed
    echo "$output" | tail -15
    failed=$(echo "$output" | grep "Failed:" | awk '{print $2}')
    TOTAL_FAILED=$((TOTAL_FAILED + failed))
    FAILED_SUITES+=("$test_file")
  fi

  echo ""
done

# Print overall summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Overall Results"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Total Passed: $TOTAL_PASSED"
echo "  Total Failed: $TOTAL_FAILED"
echo ""

if [[ ${#FAILED_SUITES[@]} -gt 0 ]]; then
  echo "  Failed test suites:"
  for suite in "${FAILED_SUITES[@]}"; do
    echo "    ✘ $suite"
  done
  echo ""
  exit 1
fi

echo "  ✅ All test suites passed!"
echo ""
exit 0
