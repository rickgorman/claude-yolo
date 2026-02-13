#!/usr/bin/env bash
#
# End-to-end test: Chrome instance isolation across worktrees
#
# Spins up two headless Chrome containers on different ports,
# creates tabs in each, and verifies they are fully isolated.
#
# Usage:
#   ./test/test-chrome-multi.sh
#
# Requires: docker

set -euo pipefail

NETWORK="claude-yolo-multi-$$"
CHROME_A="chrome-multi-a-$$"
CHROME_B="chrome-multi-b-$$"
IMAGE="chromedp/headless-shell:latest"
PORT_A=9222
PORT_B=9223

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

cleanup() {
  echo ""
  echo "Cleaning up..."
  docker stop "$CHROME_A" "$CHROME_B" 2>/dev/null || true
  docker network rm "$NETWORK" 2>/dev/null || true
}
trap cleanup EXIT

########################################
# Preflight
########################################

section "Preflight"

if ! command -v docker &>/dev/null; then
  fail "Docker is not installed"
  exit 1
fi

if ! docker info &>/dev/null; then
  fail "Docker is not running"
  exit 1
fi

pass "Docker available"

########################################
# Create network and start two Chromes
########################################

section "Start two headless Chrome instances"

docker network create "$NETWORK" >/dev/null
pass "Created network $NETWORK"

docker run -d --rm \
  --name "$CHROME_A" \
  --network "$NETWORK" \
  -p "${PORT_A}:9222" \
  "$IMAGE" \
  --no-sandbox >/dev/null

docker run -d --rm \
  --name "$CHROME_B" \
  --network "$NETWORK" \
  -p "${PORT_B}:9222" \
  "$IMAGE" \
  --no-sandbox >/dev/null

wait_for_chrome() {
  local container="$1"
  local label="$2"
  local ready=false
  for _ in $(seq 1 30); do
    if docker logs "$container" 2>&1 | grep -q 'DevTools listening'; then
      ready=true
      break
    fi
    sleep 0.5
  done
  if [[ "$ready" == true ]]; then
    pass "$label CDP ready"
  else
    fail "$label CDP did not start in time"
    exit 1
  fi
}

wait_for_chrome "$CHROME_A" "Chrome A (port $PORT_A)"
wait_for_chrome "$CHROME_B" "Chrome B (port $PORT_B)"

########################################
# Verify both are independently reachable
########################################

section "CDP connectivity"

version_a=$(curl -sf "http://localhost:${PORT_A}/json/version" | jq -r .Browser 2>/dev/null) || version_a=""
if [[ -n "$version_a" && "$version_a" != "null" ]]; then
  pass "Chrome A reachable on port $PORT_A ($version_a)"
else
  fail "Chrome A not reachable on port $PORT_A"
fi

version_b=$(curl -sf "http://localhost:${PORT_B}/json/version" | jq -r .Browser 2>/dev/null) || version_b=""
if [[ -n "$version_b" && "$version_b" != "null" ]]; then
  pass "Chrome B reachable on port $PORT_B ($version_b)"
else
  fail "Chrome B not reachable on port $PORT_B"
fi

########################################
# Create unique tabs in each instance
########################################

section "Tab isolation"

TITLE_A="isolation-test-chrome-a-$$"
TITLE_B="isolation-test-chrome-b-$$"

tab_a_url="data:text/html,<title>${TITLE_A}</title>"
tab_a_id=$(curl -sf -X PUT "http://localhost:${PORT_A}/json/new?${tab_a_url}" | jq -r .id 2>/dev/null) || tab_a_id=""

if [[ -n "$tab_a_id" && "$tab_a_id" != "null" ]]; then
  pass "Created tab in Chrome A (title: $TITLE_A)"
else
  fail "Failed to create tab in Chrome A"
fi

tab_b_url="data:text/html,<title>${TITLE_B}</title>"
tab_b_id=$(curl -sf -X PUT "http://localhost:${PORT_B}/json/new?${tab_b_url}" | jq -r .id 2>/dev/null) || tab_b_id=""

if [[ -n "$tab_b_id" && "$tab_b_id" != "null" ]]; then
  pass "Created tab in Chrome B (title: $TITLE_B)"
else
  fail "Failed to create tab in Chrome B"
fi

# Allow tabs to load
sleep 1

########################################
# Verify isolation: A's tab not in B, B's tab not in A
########################################

section "Cross-instance isolation"

tabs_a=$(curl -sf "http://localhost:${PORT_A}/json/list" 2>/dev/null) || tabs_a="[]"
tabs_b=$(curl -sf "http://localhost:${PORT_B}/json/list" 2>/dev/null) || tabs_b="[]"

# Chrome A should have its own tab but NOT Chrome B's tab
if echo "$tabs_a" | jq -r '.[].title' | grep -qF "$TITLE_A"; then
  pass "Chrome A has its own tab ($TITLE_A)"
else
  if echo "$tabs_a" | jq -r '.[].url' | grep -qF "$TITLE_A"; then
    pass "Chrome A has its own tab (matched via URL)"
  else
    fail "Chrome A missing its own tab ($TITLE_A)"
  fi
fi

if echo "$tabs_a" | jq -r '.[].title' | grep -qF "$TITLE_B"; then
  fail "Chrome A has Chrome B's tab ($TITLE_B) — ISOLATION BROKEN"
else
  pass "Chrome A does NOT have Chrome B's tab"
fi

# Chrome B should have its own tab but NOT Chrome A's tab
if echo "$tabs_b" | jq -r '.[].title' | grep -qF "$TITLE_B"; then
  pass "Chrome B has its own tab ($TITLE_B)"
else
  if echo "$tabs_b" | jq -r '.[].url' | grep -qF "$TITLE_B"; then
    pass "Chrome B has its own tab (matched via URL)"
  else
    fail "Chrome B missing its own tab ($TITLE_B)"
  fi
fi

if echo "$tabs_b" | jq -r '.[].title' | grep -qF "$TITLE_A"; then
  fail "Chrome B has Chrome A's tab ($TITLE_A) — ISOLATION BROKEN"
else
  pass "Chrome B does NOT have Chrome A's tab"
fi

########################################
# Cleanup tabs
########################################

section "Tab cleanup"

if [[ -n "$tab_a_id" && "$tab_a_id" != "null" ]]; then
  curl -sf -X PUT "http://localhost:${PORT_A}/json/close/${tab_a_id}" >/dev/null 2>&1 || true
  pass "Closed tab in Chrome A"
fi

if [[ -n "$tab_b_id" && "$tab_b_id" != "null" ]]; then
  curl -sf -X PUT "http://localhost:${PORT_B}/json/close/${tab_b_id}" >/dev/null 2>&1 || true
  pass "Closed tab in Chrome B"
fi

# Verify tabs are gone
sleep 0.5

tabs_a_after=$(curl -sf "http://localhost:${PORT_A}/json/list" | jq -r '.[].title' 2>/dev/null) || tabs_a_after=""
if echo "$tabs_a_after" | grep -qF "$TITLE_A"; then
  fail "Chrome A tab still present after close"
else
  pass "Chrome A tab confirmed closed"
fi

tabs_b_after=$(curl -sf "http://localhost:${PORT_B}/json/list" | jq -r '.[].title' 2>/dev/null) || tabs_b_after=""
if echo "$tabs_b_after" | grep -qF "$TITLE_B"; then
  fail "Chrome B tab still present after close"
else
  pass "Chrome B tab confirmed closed"
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

echo "  All multi-Chrome isolation tests passed!"
exit 0
