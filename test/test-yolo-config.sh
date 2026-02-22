#!/usr/bin/env bash
set -euo pipefail

# Source common test framework
source "$(dirname "$0")/lib/common.sh"

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
echo '{"claudeAiOauth":{"accessToken":"fake-test-token"}}' > "$YOLO_ENV_TRUST_DIR/.claude/.credentials.json"

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

cat > "$MOCK_BIN/uname" << 'MOCKEOF'
#!/usr/bin/env bash
echo "Darwin"
MOCKEOF
chmod +x "$MOCK_BIN/uname"

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
check_yolo_config "$EMPTY_DIR" "false" 2>/dev/null
assert_eq "check_yolo_config returns 0 without .yolo/" "false" "$YOLO_CONFIG_LOADED"


section "check_yolo_config — --trust-yolo flag"

YOLO_TRUST_FLAG_DIR="$TMPDIR_BASE/yolo-trust-flag"
mkdir -p "$YOLO_TRUST_FLAG_DIR/.yolo"
echo "generic" > "$YOLO_TRUST_FLAG_DIR/.yolo/strategy"
YOLO_TRUST_HOME="$TMPDIR_BASE/yolo-trust-home"
mkdir -p "$YOLO_TRUST_HOME/.claude"

YOLO_CONFIG_LOADED=false
HOME="$YOLO_TRUST_HOME" check_yolo_config "$YOLO_TRUST_FLAG_DIR" "true" 2>/dev/null
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
HOME="$YOLO_TRUST_HOME" check_yolo_config "$YOLO_TRUST_FLAG_DIR" "false" 2>/dev/null
assert_eq "check_yolo_config auto-trusts known config" "true" "$YOLO_CONFIG_LOADED"

########################################
# Tests: --reset flag
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
echo '{"claudeAiOauth":{"accessToken":"fake-test-token"}}' > "$YOLO_DOCKERFILE_HOME/.claude/.credentials.json"

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

cat > "$MOCK_BIN/uname" << 'MOCKEOF'
#!/usr/bin/env bash
echo "Darwin"
MOCKEOF
chmod +x "$MOCK_BIN/uname"

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


print_summary "$(basename "$0" .sh)"