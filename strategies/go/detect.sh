#!/usr/bin/env bash
# Detection heuristics for Go projects
#
# Outputs:
#   CONFIDENCE:<0-100>
#   EVIDENCE:<comma-separated list of what was found>

set -euo pipefail

PROJECT_DIR="${1:-.}"
CONFIDENCE=0
EVIDENCE=()

# go.mod (strong signal)
if [[ -f "$PROJECT_DIR/go.mod" ]]; then
  CONFIDENCE=$((CONFIDENCE + 50))
  EVIDENCE+=("go.mod")
fi

# go.sum
if [[ -f "$PROJECT_DIR/go.sum" ]]; then
  CONFIDENCE=$((CONFIDENCE + 15))
  EVIDENCE+=("go.sum")
fi

# main.go in root
if [[ -f "$PROJECT_DIR/main.go" ]]; then
  CONFIDENCE=$((CONFIDENCE + 15))
  EVIDENCE+=("main.go")
fi

# cmd/ directory (common Go project layout)
if [[ -d "$PROJECT_DIR/cmd" ]]; then
  go_in_cmd=$(find "$PROJECT_DIR/cmd" -maxdepth 2 -name "*.go" -print -quit 2>/dev/null || true)
  if [[ -n "$go_in_cmd" ]]; then
    CONFIDENCE=$((CONFIDENCE + 10))
    EVIDENCE+=("cmd/")
  fi
fi

# .go-version
if [[ -f "$PROJECT_DIR/.go-version" ]]; then
  go_ver=$(cat "$PROJECT_DIR/.go-version" | tr -d '[:space:]')
  CONFIDENCE=$((CONFIDENCE + 10))
  EVIDENCE+=(".go-version ($go_ver)")
fi

# .tool-versions with golang entry
if [[ -f "$PROJECT_DIR/.tool-versions" ]]; then
  if grep -q '^golang ' "$PROJECT_DIR/.tool-versions" 2>/dev/null; then
    CONFIDENCE=$((CONFIDENCE + 10))
    EVIDENCE+=(".tool-versions (golang)")
  fi
fi

# Cap at 100
[[ $CONFIDENCE -gt 100 ]] && CONFIDENCE=100

echo "CONFIDENCE:${CONFIDENCE}"
echo "EVIDENCE:$(IFS=', '; echo "${EVIDENCE[*]}")"
