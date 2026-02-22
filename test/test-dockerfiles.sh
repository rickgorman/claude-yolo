#!/usr/bin/env bash
set -euo pipefail

# Source common test framework
source "$(dirname "$0")/lib/common.sh"

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


section "Dockerfile socat"

rails_dockerfile=$(cat "$STRATEGIES_DIR/rails/Dockerfile")
assert_contains "Rails Dockerfile installs socat" "$rails_dockerfile" "socat"

########################################
# Tests: Rails display without Chrome CDP
########################################


print_summary "$(basename "$0" .sh)"