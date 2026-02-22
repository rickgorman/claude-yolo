#!/usr/bin/env bash
set -euo pipefail

# Source common test framework
source "$(dirname "$0")/lib/common.sh"

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
  tmux() { return 0; }
  export -f tmux
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
# YOLO_CHROME_BINARY="" prevents real Chrome from launching (avoids macOS keychain popup)
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
  export YOLO_CHROME_BINARY=
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


section "Rails display without --chrome"

# Rails info line should show Ruby + Postgres but NOT Chrome CDP
assert_contains "Rails output shows Ruby" "$output_no_chrome" "Ruby"
assert_contains "Rails output shows Postgres" "$output_no_chrome" "Postgres"
assert_not_contains "Rails output without --chrome omits Chrome CDP" "$output_no_chrome" "Chrome CDP"

########################################
# Tests: parse_env_file
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

cat > "$MOCK_BIN/uname" << 'MOCKEOF'
#!/usr/bin/env bash
echo "Darwin"
MOCKEOF
chmod +x "$MOCK_BIN/uname"

cat > "$MOCK_BIN/tmux" << 'MOCKEOF'
#!/usr/bin/env bash
exit 0
MOCKEOF
chmod +x "$MOCK_BIN/tmux"

cat > "$MOCK_BIN/lsof" << 'MOCKEOF'
#!/usr/bin/env bash
exit 1
MOCKEOF
chmod +x "$MOCK_BIN/lsof"

cat > "$MOCK_BIN/curl" << 'MOCKEOF'
#!/usr/bin/env bash
echo "200"
exit 0
MOCKEOF
chmod +x "$MOCK_BIN/curl"

output=$(cd "$RAILS_DIR" && \
  HOME="$FAKE_HOME" \
  GH_TOKEN="test_token_for_ci" \
  PATH="$MOCK_BIN:$PATH" \
  bash "$CLI" --yolo --strategy rails --env MY_VAR=hello --env OTHER_VAR=world 2>&1 || true)

env_docker_args=$(cat "$ENV_DOCKER_LOG" 2>/dev/null || echo "")
assert_contains "--env injects MY_VAR" "$env_docker_args" "MY_VAR=hello"
assert_contains "--env injects OTHER_VAR" "$env_docker_args" "OTHER_VAR=world"

# Cleanup mocks
rm -f "$MOCK_BIN/uname" "$MOCK_BIN/tmux" "$MOCK_BIN/lsof" "$MOCK_BIN/curl"


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

cat > "$MOCK_BIN/uname" << 'MOCKEOF'
#!/usr/bin/env bash
echo "Darwin"
MOCKEOF
chmod +x "$MOCK_BIN/uname"

cat > "$MOCK_BIN/tmux" << 'MOCKEOF'
#!/usr/bin/env bash
exit 0
MOCKEOF
chmod +x "$MOCK_BIN/tmux"

cat > "$MOCK_BIN/lsof" << 'MOCKEOF'
#!/usr/bin/env bash
exit 1
MOCKEOF
chmod +x "$MOCK_BIN/lsof"

cat > "$MOCK_BIN/curl" << 'MOCKEOF'
#!/usr/bin/env bash
echo "200"
exit 0
MOCKEOF
chmod +x "$MOCK_BIN/curl"

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

# Cleanup mocks
rm -f "$MOCK_BIN/uname" "$MOCK_BIN/tmux" "$MOCK_BIN/lsof" "$MOCK_BIN/curl"


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

cat > "$MOCK_BIN/uname" << 'MOCKEOF'
#!/usr/bin/env bash
echo "Darwin"
MOCKEOF
chmod +x "$MOCK_BIN/uname"

cat > "$MOCK_BIN/tmux" << 'MOCKEOF'
#!/usr/bin/env bash
exit 0
MOCKEOF
chmod +x "$MOCK_BIN/tmux"

cat > "$MOCK_BIN/lsof" << 'MOCKEOF'
#!/usr/bin/env bash
exit 1
MOCKEOF
chmod +x "$MOCK_BIN/lsof"

cat > "$MOCK_BIN/curl" << 'MOCKEOF'
#!/usr/bin/env bash
echo "200"
exit 0
MOCKEOF
chmod +x "$MOCK_BIN/curl"

output=$(cd "$RAILS_DIR" && \
  HOME="$FAKE_HOME" \
  GH_TOKEN="test_token_for_ci" \
  PATH="$MOCK_BIN:$PATH" \
  bash "$CLI" --yolo --strategy rails --env INLINE_VAR=inline --env-file "$ENV_FILE_TEST" 2>&1 || true)

combined_docker_args=$(cat "$ENV_COMBINED_LOG" 2>/dev/null || echo "")
assert_contains "Combined: --env var present" "$combined_docker_args" "INLINE_VAR=inline"
assert_contains "Combined: --env-file var present" "$combined_docker_args" "API_KEY=secret123"

# Cleanup mocks
rm -f "$MOCK_BIN/uname" "$MOCK_BIN/tmux" "$MOCK_BIN/lsof" "$MOCK_BIN/curl"

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
  tmux() { return 0; }
  export -f tmux
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
  tmux() { return 0; }
  export -f tmux
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
  tmux() { return 0; }
  export -f tmux
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
  tmux() { return 0; }
  export -f tmux
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

echo "DEBUG: --reset full output:" >&2
echo "$output_reset" >&2
echo "DEBUG: End output" >&2
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

TRUST_YOLO_DIR="$TMPDIR_BASE/trust-yolo-test-dir"
mkdir -p "$TRUST_YOLO_DIR/.yolo"
echo "generic" > "$TRUST_YOLO_DIR/.yolo/strategy"

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
  tmux() { return 0; }
  export -f tmux
  lsof() { return 1; }
  export -f lsof
  curl() {
    case "$*" in
      *api.github.com*) echo "200"; return 0 ;;
      *) return 0 ;;
    esac
  }
  export -f curl
  cd "'"$TRUST_YOLO_DIR"'"
  HOME="'"$TMPDIR_BASE/trust-yolo-test-home"'"
  mkdir -p "$HOME/.claude"
  echo '"'"'{"claudeAiOauth":{"accessToken":"fake-test-token"}}'"'"' > "$HOME/.claude/.credentials.json"
  bash "'"$CLI"'" --yolo --strategy generic --trust-yolo 2>&1
' 2>&1 || true)

assert_contains "--trust-yolo skips prompt" "$output_trust_yolo" "--trust-yolo"
assert_contains "--trust-yolo shows config loaded" "$output_trust_yolo" ".yolo/ config"

########################################
# Tests: Container persistence (no --rm)
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
# Tests: ~/.claude.json mount for onboarding skip
########################################


print_summary "$(basename "$0" .sh)"