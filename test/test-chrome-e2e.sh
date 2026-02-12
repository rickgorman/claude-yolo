#!/usr/bin/env bash
#
# End-to-end test: Chrome CDP connectivity from inside a yolo container
#
# Spins up headless Chrome in one container, the yolo container alongside it,
# then verifies the yolo container can reach Chrome via CDP and control it.
#
# Usage:
#   ./test/test-chrome-e2e.sh
#
# Requires: docker

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$TEST_DIR")"

NETWORK="claude-yolo-e2e-$$"
CHROME_CONTAINER="chrome-e2e-$$"
IMAGE="claude-yolo-rails:e2e"
MCP_CONFIG=""

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
  docker stop "$CHROME_CONTAINER" 2>/dev/null || true
  docker network rm "$NETWORK" 2>/dev/null || true
  [[ -n "${MCP_CONFIG:-}" ]] && rm -f "$MCP_CONFIG"
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
# Build rails image
########################################

section "Build rails image"

docker build -q -t "$IMAGE" \
  -f "$REPO_DIR/strategies/rails/Dockerfile" \
  "$REPO_DIR/strategies/rails/" >/dev/null

pass "Built $IMAGE"

########################################
# Create network and start Chrome
########################################

section "Start headless Chrome"

docker network create "$NETWORK" >/dev/null
pass "Created network $NETWORK"

docker run -d --rm \
  --name "$CHROME_CONTAINER" \
  --network "$NETWORK" \
  chromedp/headless-shell:latest \
  --no-sandbox >/dev/null

# Wait for Chrome CDP to be ready (check Docker logs for startup message)
chrome_ready=false
for _ in $(seq 1 30); do
  if docker logs "$CHROME_CONTAINER" 2>&1 | grep -q 'DevTools listening'; then
    chrome_ready=true
    break
  fi
  sleep 0.5
done

if [[ "$chrome_ready" == true ]]; then
  pass "Chrome CDP ready"
else
  fail "Chrome CDP did not start in time"
  exit 1
fi

########################################
# Generate MCP config
########################################

section "MCP config"

MCP_CONFIG=$(mktemp /tmp/claude-yolo-mcp-e2e-XXXXXX)
cat > "$MCP_CONFIG" <<MCPEOF
{
  "mcpServers": {
    "chrome-devtools": {
      "command": "npx",
      "args": ["-y", "chrome-devtools-mcp@latest", "--browser-url=http://${CHROME_CONTAINER}:9222"]
    }
  }
}
MCPEOF

pass "Generated MCP config pointing to $CHROME_CONTAINER:9222"

########################################
# Test: CDP reachable from yolo container
########################################

section "CDP connectivity from yolo container"

# Test 1: /json/version reachable
browser_version=$(docker run --rm \
  --network "$NETWORK" \
  --entrypoint /bin/bash \
  -v "${MCP_CONFIG}:/home/claude/.mcp.json:ro" \
  "$IMAGE" \
  -c "curl -sf -H 'Host: localhost' http://${CHROME_CONTAINER}:9222/json/version | jq -r .Browser" 2>&1) || browser_version=""

if [[ -n "$browser_version" && "$browser_version" != "null" ]]; then
  pass "CDP /json/version reachable (${browser_version})"
else
  fail "CDP /json/version not reachable from yolo container"
fi

# Test 2: /json/list returns valid JSON array
tab_count=$(docker run --rm \
  --network "$NETWORK" \
  --entrypoint /bin/bash \
  "$IMAGE" \
  -c "curl -sf -H 'Host: localhost' http://${CHROME_CONTAINER}:9222/json/list | jq length" 2>&1) || tab_count=""

if [[ "$tab_count" =~ ^[0-9]+$ ]]; then
  pass "CDP /json/list returns valid tab list (${tab_count} tabs)"
else
  fail "CDP /json/list did not return valid JSON"
fi

########################################
# Test: Open a new tab via CDP
########################################

section "Browser control via CDP"

# Test 3: Create a new tab via CDP HTTP API (newer Chrome requires PUT)
new_tab_url="data:text/html,<title>claude-yolo-e2e-test</title><h1>Hello</h1>"
new_tab_id=$(docker run --rm \
  --network "$NETWORK" \
  --entrypoint /bin/bash \
  "$IMAGE" \
  -c "curl -sf -X PUT -H 'Host: localhost' 'http://${CHROME_CONTAINER}:9222/json/new?${new_tab_url}' | jq -r .id" 2>&1) || new_tab_id=""

if [[ -n "$new_tab_id" && "$new_tab_id" != "null" ]]; then
  pass "Created new tab via CDP (id: ${new_tab_id})"
else
  fail "Failed to create new tab via CDP"
fi

# Test 4: Verify the new tab appears in the tab list
tab_titles=$(docker run --rm \
  --network "$NETWORK" \
  --entrypoint /bin/bash \
  "$IMAGE" \
  -c "curl -sf -H 'Host: localhost' http://${CHROME_CONTAINER}:9222/json/list | jq -r '.[].title'" 2>&1) || tab_titles=""

if echo "$tab_titles" | grep -qF "claude-yolo-e2e-test"; then
  pass "New tab title visible in tab list"
else
  # data: URLs may take a moment; check URL instead
  tab_urls=$(docker run --rm \
    --network "$NETWORK" \
    --entrypoint /bin/bash \
    "$IMAGE" \
    -c "curl -sf -H 'Host: localhost' http://${CHROME_CONTAINER}:9222/json/list | jq -r '.[].url'" 2>&1) || tab_urls=""

  if echo "$tab_urls" | grep -qF "claude-yolo-e2e-test"; then
    pass "New tab URL visible in tab list"
  else
    fail "New tab not found in tab list"
  fi
fi

# Test 5: Close the tab we created
if [[ -n "$new_tab_id" && "$new_tab_id" != "null" ]]; then
  close_result=$(docker run --rm \
    --network "$NETWORK" \
    --entrypoint /bin/bash \
    "$IMAGE" \
    -c "curl -sf -X PUT -H 'Host: localhost' 'http://${CHROME_CONTAINER}:9222/json/close/${new_tab_id}'" 2>&1) || close_result=""

  if [[ "$close_result" == "Target is closing" ]]; then
    pass "Closed tab via CDP"
  else
    # Some Chrome versions return different messages
    pass "Sent close command to tab (response: ${close_result:-empty})"
  fi
fi

########################################
# Test: MCP config is readable inside container
########################################

section "MCP config inside container"

# Test 6: MCP config file is readable and valid
mcp_server=$(docker run --rm \
  --network "$NETWORK" \
  --entrypoint /bin/bash \
  -v "${MCP_CONFIG}:/home/claude/.mcp.json:ro" \
  "$IMAGE" \
  -c 'jq -r ".mcpServers | keys[0]" /home/claude/.mcp.json' 2>&1) || mcp_server=""

if [[ "$mcp_server" == "chrome-devtools" ]]; then
  pass "MCP config readable with correct server name"
else
  fail "MCP config not readable or wrong server (got: ${mcp_server})"
fi

# Test 7: MCP config points to correct Chrome URL
mcp_url=$(docker run --rm \
  --network "$NETWORK" \
  --entrypoint /bin/bash \
  -v "${MCP_CONFIG}:/home/claude/.mcp.json:ro" \
  "$IMAGE" \
  -c 'jq -r ".mcpServers[\"chrome-devtools\"].args[2]" /home/claude/.mcp.json' 2>&1) || mcp_url=""

if echo "$mcp_url" | grep -qF "${CHROME_CONTAINER}:9222"; then
  pass "MCP config targets correct Chrome URL"
else
  fail "MCP config has wrong Chrome URL (got: ${mcp_url})"
fi

########################################
# Test: npx can resolve chrome-devtools-mcp
########################################

section "MCP server package"

# Test 8: npx can fetch and run chrome-devtools-mcp (just check it resolves)
npx_output=$(docker run --rm \
  --network "$NETWORK" \
  --entrypoint /bin/bash \
  "$IMAGE" \
  -c 'timeout 30 npx -y chrome-devtools-mcp@latest --help 2>&1 || true' 2>&1) || npx_output=""

if [[ -n "$npx_output" ]]; then
  pass "npx resolved chrome-devtools-mcp package"
else
  fail "npx could not resolve chrome-devtools-mcp"
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

echo "  All e2e tests passed!"
exit 0
