#!/usr/bin/env bash
#
# Integration test: Container persistence across sessions
#
# Verifies that:
#   1. A container created without --rm persists after stop
#   2. Runtime changes (files, apt packages) survive restart
#   3. A second session can reattach to the stopped container
#   4. Container removal (--reset equivalent) resets all state
#
# Usage:
#   ./test/test-container-persistence.sh
#
# Requires: docker

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$TEST_DIR")"

IMAGE="claude-yolo-generic"
CONTAINER_NAME="claude-yolo-persist-test-$$"

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
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT

########################################
# Preflight: ensure generic image exists
########################################

section "Preflight"

if ! docker image inspect "${IMAGE}:latest" &>/dev/null; then
  echo "  Building ${IMAGE} image..."
  DOCKER_BUILDKIT=1 docker build \
    -t "${IMAGE}:latest" \
    -f "$REPO_DIR/strategies/generic/Dockerfile" \
    "$REPO_DIR/strategies/generic/" >/dev/null 2>&1 || {
    fail "Could not build generic image"
    exit 1
  }
fi
pass "Generic image available"

########################################
# Test 1: Container persists after stop
########################################

section "Container persists after stop (no --rm)"

cleanup

# Create a container WITHOUT --rm, using a long-running process
docker run -d --name "$CONTAINER_NAME" \
  "${IMAGE}:latest" \
  tail -f /dev/null \
  >/dev/null 2>&1

# Session 1: create a file via exec
docker exec "$CONTAINER_NAME" \
  sh -c 'echo "hello from session 1" > /tmp/persist-test.txt' 2>/dev/null

# Verify file exists in session 1
content=$(docker exec "$CONTAINER_NAME" cat /tmp/persist-test.txt 2>/dev/null || echo "")
if [[ "$content" == "hello from session 1" ]]; then
  pass "File created in session 1"
else
  fail "File not created in session 1 (got: '$content')"
fi

# Stop the container (simulates user exiting)
docker stop "$CONTAINER_NAME" >/dev/null 2>&1

status=$(docker inspect --format '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "missing")
if [[ "$status" == "exited" ]]; then
  pass "Container persists in exited state after stop"
else
  fail "Container should be exited (got: $status)"
fi

########################################
# Test 2: Runtime changes survive restart
########################################

section "Runtime changes survive restart"

# Restart the stopped container
docker start "$CONTAINER_NAME" >/dev/null 2>&1

status=$(docker inspect --format '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "missing")
if [[ "$status" == "running" ]]; then
  pass "Container restarts successfully"
else
  fail "Container failed to restart (status: $status)"
fi

# Session 2: check that file from session 1 still exists
content=$(docker exec "$CONTAINER_NAME" cat /tmp/persist-test.txt 2>/dev/null || echo "GONE")
if [[ "$content" == "hello from session 1" ]]; then
  pass "File from session 1 persists after restart"
else
  fail "File from session 1 lost after restart (got: '$content')"
fi

# Session 2: create another file
docker exec "$CONTAINER_NAME" \
  sh -c 'echo "hello from session 2" > /tmp/persist-test-2.txt' 2>/dev/null

# Stop and restart again
docker stop "$CONTAINER_NAME" >/dev/null 2>&1
docker start "$CONTAINER_NAME" >/dev/null 2>&1

# Session 3: verify both files survive
content1=$(docker exec "$CONTAINER_NAME" cat /tmp/persist-test.txt 2>/dev/null || echo "GONE")
content2=$(docker exec "$CONTAINER_NAME" cat /tmp/persist-test-2.txt 2>/dev/null || echo "GONE")

if [[ "$content1" == "hello from session 1" ]]; then
  pass "Session 1 file survives two restart cycles"
else
  fail "Session 1 file lost (got: '$content1')"
fi

if [[ "$content2" == "hello from session 2" ]]; then
  pass "Session 2 file survives restart cycle"
else
  fail "Session 2 file lost (got: '$content2')"
fi

########################################
# Test 3: apt-get installs survive restart
########################################

section "Installed packages survive restart"

# Install a small package
docker exec --user root "$CONTAINER_NAME" \
  sh -c 'apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq cowsay >/dev/null 2>&1' 2>/dev/null

if docker exec "$CONTAINER_NAME" test -f /usr/games/cowsay 2>/dev/null; then
  pass "cowsay installed successfully"
else
  fail "cowsay not found after install"
fi

# Stop and restart
docker stop "$CONTAINER_NAME" >/dev/null 2>&1
docker start "$CONTAINER_NAME" >/dev/null 2>&1

if docker exec "$CONTAINER_NAME" test -f /usr/games/cowsay 2>/dev/null; then
  pass "cowsay persists after container restart"
else
  fail "cowsay lost after container restart"
fi

########################################
# Test 4: Container removal resets state
########################################

section "Container removal resets all state (--reset equivalent)"

# Remove and recreate
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

docker run -d --name "$CONTAINER_NAME" \
  "${IMAGE}:latest" \
  tail -f /dev/null \
  >/dev/null 2>&1

# Old files should be gone
old_content=$(docker exec "$CONTAINER_NAME" cat /tmp/persist-test.txt 2>/dev/null || echo "GONE")
if [[ "$old_content" == "GONE" ]]; then
  pass "Old session files removed after container recreation"
else
  fail "Old session files still present after recreation"
fi

# cowsay should be gone
if docker exec "$CONTAINER_NAME" test -f /usr/games/cowsay 2>/dev/null; then
  fail "cowsay should not exist in fresh container"
else
  pass "cowsay correctly absent in fresh container"
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
