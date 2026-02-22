#!/usr/bin/env bash
set -euo pipefail

# Source common test framework
source "$(dirname "$0")/lib/common.sh"

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


section "Strategy detection — Generic"

generic_output=$("$STRATEGIES_DIR/generic/detect.sh" "$RAILS_DIR" 2>/dev/null)
generic_confidence=$(echo "$generic_output" | grep '^CONFIDENCE:' | cut -d: -f2)
assert_eq "Generic detection always 0% (manual only)" "0" "$generic_confidence"

generic_empty=$("$STRATEGIES_DIR/generic/detect.sh" "$EMPTY_DIR" 2>/dev/null)
generic_empty_conf=$(echo "$generic_empty" | grep '^CONFIDENCE:' | cut -d: -f2)
assert_eq "Generic detection 0% for empty dir" "0" "$generic_empty_conf"


section "Strategy detection — Python"

python_output=$("$STRATEGIES_DIR/python/detect.sh" "$PYTHON_DIR" 2>/dev/null)
python_confidence=$(echo "$python_output" | grep '^CONFIDENCE:' | cut -d: -f2)
python_evidence=$(echo "$python_output" | grep '^EVIDENCE:' | cut -d: -f2-)

if [[ "$python_confidence" -ge 80 ]]; then
  pass "Python confidence ≥80% for full Python project ($python_confidence%)"
else
  fail "Python confidence ≥80% for full Python project (got $python_confidence%)"
fi
assert_contains "Python evidence includes pyproject.toml" "$python_evidence" "pyproject.toml"
assert_contains "Python evidence includes requirements.txt" "$python_evidence" "requirements.txt"
assert_contains "Python evidence includes .python-version" "$python_evidence" ".python-version"


section "Strategy detection — Python (weak signal)"

weak_python_output=$("$STRATEGIES_DIR/python/detect.sh" "$WEAK_PYTHON" 2>/dev/null)
weak_python_conf=$(echo "$weak_python_output" | grep '^CONFIDENCE:' | cut -d: -f2)

if [[ "$weak_python_conf" -lt 80 ]]; then
  pass "Python detection <80% for just requirements.txt ($weak_python_conf%)"
else
  fail "Python detection <80% for just requirements.txt (got $weak_python_conf%)"
fi

python_empty=$("$STRATEGIES_DIR/python/detect.sh" "$EMPTY_DIR" 2>/dev/null)
python_empty_conf=$(echo "$python_empty" | grep '^CONFIDENCE:' | cut -d: -f2)
assert_eq "Python detection 0% for empty dir" "0" "$python_empty_conf"


section "Strategy detection — Node.js"

node_output=$("$STRATEGIES_DIR/node/detect.sh" "$NODE_DIR" 2>/dev/null)
node_confidence=$(echo "$node_output" | grep '^CONFIDENCE:' | cut -d: -f2)
node_evidence=$(echo "$node_output" | grep '^EVIDENCE:' | cut -d: -f2-)

if [[ "$node_confidence" -ge 80 ]]; then
  pass "Node.js confidence ≥80% for full Node project ($node_confidence%)"
else
  fail "Node.js confidence ≥80% for full Node project (got $node_confidence%)"
fi
assert_contains "Node.js evidence includes package.json" "$node_evidence" "package.json"
assert_contains "Node.js evidence includes tsconfig.json" "$node_evidence" "tsconfig.json"
assert_contains "Node.js evidence includes .nvmrc" "$node_evidence" ".nvmrc"


section "Strategy detection — Node.js (weak signal)"

weak_node_output=$("$STRATEGIES_DIR/node/detect.sh" "$WEAK_NODE" 2>/dev/null)
weak_node_conf=$(echo "$weak_node_output" | grep '^CONFIDENCE:' | cut -d: -f2)

if [[ "$weak_node_conf" -lt 80 ]]; then
  pass "Node.js detection <80% for just package.json ($weak_node_conf%)"
else
  fail "Node.js detection <80% for just package.json (got $weak_node_conf%)"
fi


section "Strategy detection — Node.js (Rails project with package.json)"

rails_node_output=$("$STRATEGIES_DIR/node/detect.sh" "$RAILS_WITH_NODE" 2>/dev/null)
rails_node_conf=$(echo "$rails_node_output" | grep '^CONFIDENCE:' | cut -d: -f2)

if [[ "$rails_node_conf" -lt 80 ]]; then
  pass "Node.js detection <80% for Rails project with package.json ($rails_node_conf%)"
else
  fail "Node.js detection <80% for Rails project with package.json (got $rails_node_conf%)"
fi

node_empty=$("$STRATEGIES_DIR/node/detect.sh" "$EMPTY_DIR" 2>/dev/null)
node_empty_conf=$(echo "$node_empty" | grep '^CONFIDENCE:' | cut -d: -f2)
assert_eq "Node.js detection 0% for empty dir" "0" "$node_empty_conf"


section "Strategy detection — Go"

go_output=$("$STRATEGIES_DIR/go/detect.sh" "$GO_DIR" 2>/dev/null)
go_confidence=$(echo "$go_output" | grep '^CONFIDENCE:' | cut -d: -f2)
go_evidence=$(echo "$go_output" | grep '^EVIDENCE:' | cut -d: -f2-)

if [[ "$go_confidence" -ge 80 ]]; then
  pass "Go confidence ≥80% for full Go project ($go_confidence%)"
else
  fail "Go confidence ≥80% for full Go project (got $go_confidence%)"
fi
assert_contains "Go evidence includes go.mod" "$go_evidence" "go.mod"
assert_contains "Go evidence includes main.go" "$go_evidence" "main.go"
assert_contains "Go evidence includes cmd/" "$go_evidence" "cmd/"


section "Strategy detection — Go (weak signal)"

weak_go_output=$("$STRATEGIES_DIR/go/detect.sh" "$WEAK_GO" 2>/dev/null)
weak_go_conf=$(echo "$weak_go_output" | grep '^CONFIDENCE:' | cut -d: -f2)

if [[ "$weak_go_conf" -lt 80 ]]; then
  pass "Go detection <80% for just go.mod ($weak_go_conf%)"
else
  fail "Go detection <80% for just go.mod (got $weak_go_conf%)"
fi

go_empty=$("$STRATEGIES_DIR/go/detect.sh" "$EMPTY_DIR" 2>/dev/null)
go_empty_conf=$(echo "$go_empty" | grep '^CONFIDENCE:' | cut -d: -f2)
assert_eq "Go detection 0% for empty dir" "0" "$go_empty_conf"


section "Strategy detection — No match (new strategies)"

assert_eq "Python detection 0% for empty dir" "0" "$python_empty_conf"
assert_eq "Node.js detection 0% for empty dir" "0" "$node_empty_conf"
assert_eq "Go detection 0% for empty dir" "0" "$go_empty_conf"

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

detections=$(run_detection "$PYTHON_DIR")
assert_contains "run_detection finds python for Python project" "$detections" "python"

detections=$(run_detection "$NODE_DIR")
assert_contains "run_detection finds node for Node.js project" "$detections" "node"

detections=$(run_detection "$GO_DIR")
assert_contains "run_detection finds go for Go project" "$detections" "go"

########################################
# Tests: Ruby version detection
########################################


section "list_strategies"

strategies=$(list_strategies)
assert_contains "list_strategies includes rails" "$strategies" "rails"
assert_contains "list_strategies includes android" "$strategies" "android"
assert_contains "list_strategies includes generic" "$strategies" "generic"
assert_contains "list_strategies includes python" "$strategies" "python"
assert_contains "list_strategies includes node" "$strategies" "node"
assert_contains "list_strategies includes go" "$strategies" "go"

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


print_summary "$(basename "$0" .sh)"