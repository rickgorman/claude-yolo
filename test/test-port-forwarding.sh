#!/usr/bin/env bash
#
# End-to-end test: Port forwarding from container to host
#
# Verifies that on macOS (where --network=host is a no-op), containers
# started with -p flags have their ports reachable from the host.
#
# Tests:
#   1. A single published port is reachable from the host
#   2. Multiple published ports are reachable simultaneously
#   3. An unpublished port is NOT reachable from the host
#
# Usage:
#   ./test/test-port-forwarding.sh
#
# Requires: docker, curl

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$TEST_DIR")"

IMAGE="claude-yolo-generic"
CONTAINER_PREFIX="claude-yolo-portfwd-test-$$"

_PASS=0
_FAIL=0
_ERRORS=()
_CONTAINERS=()

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

_HOST_PIDS=()

cleanup() {
  echo ""
  echo "Cleaning up..."
  for c in "${_CONTAINERS[@]}"; do
    docker rm -f "$c" 2>/dev/null || true
  done
  for pid in "${_HOST_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT

# Start a Node.js HTTP server inside a container that responds with "OK" on a given port.
# Usage: start_http_server <container_name> <port>
start_http_server() {
  local container="$1"
  local port="$2"
  docker exec -d "$container" \
    node -e "
      require('http').createServer((_, res) => {
        res.writeHead(200);
        res.end('OK:${port}');
      }).listen(${port}, '0.0.0.0');
    "
}

# Wait for a port to become reachable from the host.
# Usage: wait_for_port <port> [max_attempts]
wait_for_port() {
  local port="$1"
  local max="${2:-20}"
  local attempt=0
  while [[ $attempt -lt $max ]]; do
    if curl -sf --connect-timeout 1 "http://localhost:${port}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
    attempt=$((attempt + 1))
  done
  return 1
}

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
# Test 1: Single port reachable
########################################

section "Single published port is reachable from host"

CONTAINER_1="${CONTAINER_PREFIX}-single"
_CONTAINERS+=("$CONTAINER_1")

# Pick a high port to avoid conflicts
PORT_A=19301

docker run -d --name "$CONTAINER_1" \
  -p "${PORT_A}:${PORT_A}" \
  "${IMAGE}:latest" \
  tail -f /dev/null \
  >/dev/null 2>&1

start_http_server "$CONTAINER_1" "$PORT_A"

if wait_for_port "$PORT_A"; then
  response=$(curl -sf "http://localhost:${PORT_A}" 2>/dev/null || echo "")
  if [[ "$response" == "OK:${PORT_A}" ]]; then
    pass "Port ${PORT_A} reachable, correct response"
  else
    fail "Port ${PORT_A} reachable but wrong response (got: '${response}')"
  fi
else
  fail "Port ${PORT_A} not reachable from host within timeout"
fi

########################################
# Test 2: Multiple ports reachable
########################################

section "Multiple published ports reachable simultaneously"

CONTAINER_2="${CONTAINER_PREFIX}-multi"
_CONTAINERS+=("$CONTAINER_2")

PORT_B=19302
PORT_C=19303

docker run -d --name "$CONTAINER_2" \
  -p "${PORT_B}:${PORT_B}" \
  -p "${PORT_C}:${PORT_C}" \
  "${IMAGE}:latest" \
  tail -f /dev/null \
  >/dev/null 2>&1

start_http_server "$CONTAINER_2" "$PORT_B"
start_http_server "$CONTAINER_2" "$PORT_C"

if wait_for_port "$PORT_B"; then
  response_b=$(curl -sf "http://localhost:${PORT_B}" 2>/dev/null || echo "")
  if [[ "$response_b" == "OK:${PORT_B}" ]]; then
    pass "First port ${PORT_B} reachable, correct response"
  else
    fail "First port ${PORT_B} wrong response (got: '${response_b}')"
  fi
else
  fail "First port ${PORT_B} not reachable from host"
fi

if wait_for_port "$PORT_C"; then
  response_c=$(curl -sf "http://localhost:${PORT_C}" 2>/dev/null || echo "")
  if [[ "$response_c" == "OK:${PORT_C}" ]]; then
    pass "Second port ${PORT_C} reachable, correct response"
  else
    fail "Second port ${PORT_C} wrong response (got: '${response_c}')"
  fi
else
  fail "Second port ${PORT_C} not reachable from host"
fi

########################################
# Test 3: Unpublished port NOT reachable
########################################

section "Unpublished port is NOT reachable from host"

# Container 2 only published PORT_B and PORT_C; start a server on a different port
PORT_D=19304
start_http_server "$CONTAINER_2" "$PORT_D"

# Give it a moment to start inside the container
sleep 1

# Verify it's running inside the container
internal_check=$(docker exec "$CONTAINER_2" \
  curl -sf --connect-timeout 1 "http://localhost:${PORT_D}" 2>/dev/null || echo "")

if [[ "$internal_check" == "OK:${PORT_D}" ]]; then
  pass "Unpublished port ${PORT_D} is serving inside container"
else
  fail "Server on port ${PORT_D} not running inside container (pre-check failed)"
fi

# But it should NOT be reachable from the host
if curl -sf --connect-timeout 2 "http://localhost:${PORT_D}" >/dev/null 2>&1; then
  fail "Unpublished port ${PORT_D} should NOT be reachable from host"
else
  pass "Unpublished port ${PORT_D} correctly unreachable from host"
fi

########################################
# Test 4: Verify docker port output
########################################

section "Docker port reports correct mappings"

port_output=$(docker port "$CONTAINER_2" 2>/dev/null || echo "")

if echo "$port_output" | grep -q "${PORT_B}"; then
  pass "docker port shows mapping for ${PORT_B}"
else
  fail "docker port missing mapping for ${PORT_B}"
fi

if echo "$port_output" | grep -q "${PORT_C}"; then
  pass "docker port shows mapping for ${PORT_C}"
else
  fail "docker port missing mapping for ${PORT_C}"
fi

if echo "$port_output" | grep -q "${PORT_D}"; then
  fail "docker port should NOT show unpublished ${PORT_D}"
else
  pass "docker port correctly omits unpublished ${PORT_D}"
fi

########################################
# Test 5: Port conflict — remapped port reaches container
########################################

section "Port conflict: remapped port reaches container"

# Use a port not used by earlier tests (19301-19304 are taken)
PORT_CONFLICT=19305
node -e "
  require('http').createServer((_, res) => {
    res.writeHead(200);
    res.end('HOST_OCCUPIED');
  }).listen(${PORT_CONFLICT}, '0.0.0.0');
" &
_HOST_PIDS+=($!)
sleep 1

# Verify the port is actually occupied on the host
host_response=$(curl -sf "http://localhost:${PORT_CONFLICT}" 2>/dev/null || echo "")
if [[ "$host_response" == "HOST_OCCUPIED" ]]; then
  pass "Port ${PORT_CONFLICT} occupied on host for conflict test"
else
  fail "Failed to occupy port ${PORT_CONFLICT} on host (got: '${host_response}')"
fi

# Start a container with the REMAPPED port mapped to the container's internal port
# This simulates what resolve_port_conflicts would do: remap host port to +1000
CONTAINER_5="${CONTAINER_PREFIX}-conflict"
_CONTAINERS+=("$CONTAINER_5")
REMAPPED_PORT=$((PORT_CONFLICT + 1000))

docker run -d --name "$CONTAINER_5" \
  -p "${REMAPPED_PORT}:${PORT_CONFLICT}" \
  "${IMAGE}:latest" \
  tail -f /dev/null \
  >/dev/null 2>&1

# Start HTTP server inside container on the CONTAINER port (original)
start_http_server "$CONTAINER_5" "$PORT_CONFLICT"

# Verify the remapped host port reaches the container
if wait_for_port "$REMAPPED_PORT"; then
  response=$(curl -sf "http://localhost:${REMAPPED_PORT}" 2>/dev/null || echo "")
  if [[ "$response" == "OK:${PORT_CONFLICT}" ]]; then
    pass "Remapped port ${REMAPPED_PORT} reaches container port ${PORT_CONFLICT}"
  else
    fail "Remapped port response incorrect (got: '${response}')"
  fi
else
  fail "Remapped port ${REMAPPED_PORT} not reachable from host"
fi

# Verify original port still returns host response (not container)
original_response=$(curl -sf "http://localhost:${PORT_CONFLICT}" 2>/dev/null || echo "")
if [[ "$original_response" == "HOST_OCCUPIED" ]]; then
  pass "Original port ${PORT_CONFLICT} still serves host process"
else
  fail "Original port ${PORT_CONFLICT} response changed (got: '${original_response}')"
fi

########################################
# Test 6: Conflict detection via lsof
########################################

section "Conflict detection identifies occupied port"

# PORT_CONFLICT (19301) is still occupied by the host listener from Test 5
if lsof -i ":${PORT_CONFLICT}" -sTCP:LISTEN &>/dev/null; then
  pass "lsof detects occupied port ${PORT_CONFLICT}"
else
  fail "lsof did not detect occupied port ${PORT_CONFLICT}"
fi

# REMAPPED_PORT (20301) is occupied by docker
if lsof -i ":${REMAPPED_PORT}" -sTCP:LISTEN &>/dev/null; then
  pass "lsof detects docker-occupied port ${REMAPPED_PORT}"
else
  fail "lsof did not detect docker-occupied port ${REMAPPED_PORT}"
fi

# A truly free port should not be detected
FREE_PORT=19399
if lsof -i ":${FREE_PORT}" -sTCP:LISTEN &>/dev/null; then
  fail "lsof falsely detected free port ${FREE_PORT}"
else
  pass "lsof correctly reports port ${FREE_PORT} as free"
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

echo "  All port forwarding tests passed!"
exit 0
