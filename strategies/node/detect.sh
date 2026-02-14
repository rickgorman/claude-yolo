#!/usr/bin/env bash
# Detection heuristics for Node.js/TypeScript projects
#
# Outputs:
#   CONFIDENCE:<0-100>
#   EVIDENCE:<comma-separated list of what was found>

set -euo pipefail

PROJECT_DIR="${1:-.}"
CONFIDENCE=0
EVIDENCE=()

# package.json (strong signal)
if [[ -f "$PROJECT_DIR/package.json" ]]; then
  CONFIDENCE=$((CONFIDENCE + 40))
  EVIDENCE+=("package.json")
fi

# package-lock.json or yarn.lock or pnpm-lock.yaml
if [[ -f "$PROJECT_DIR/package-lock.json" ]]; then
  CONFIDENCE=$((CONFIDENCE + 15))
  EVIDENCE+=("package-lock.json")
elif [[ -f "$PROJECT_DIR/yarn.lock" ]]; then
  CONFIDENCE=$((CONFIDENCE + 15))
  EVIDENCE+=("yarn.lock")
elif [[ -f "$PROJECT_DIR/pnpm-lock.yaml" ]]; then
  CONFIDENCE=$((CONFIDENCE + 15))
  EVIDENCE+=("pnpm-lock.yaml")
elif [[ -f "$PROJECT_DIR/bun.lockb" ]] || [[ -f "$PROJECT_DIR/bun.lock" ]]; then
  CONFIDENCE=$((CONFIDENCE + 15))
  EVIDENCE+=("bun.lock")
fi

# tsconfig.json (TypeScript)
if [[ -f "$PROJECT_DIR/tsconfig.json" ]]; then
  CONFIDENCE=$((CONFIDENCE + 15))
  EVIDENCE+=("tsconfig.json")
fi

# .nvmrc or .node-version
if [[ -f "$PROJECT_DIR/.nvmrc" ]]; then
  node_ver=$(cat "$PROJECT_DIR/.nvmrc" | tr -d '[:space:]')
  CONFIDENCE=$((CONFIDENCE + 10))
  EVIDENCE+=(".nvmrc ($node_ver)")
elif [[ -f "$PROJECT_DIR/.node-version" ]]; then
  node_ver=$(cat "$PROJECT_DIR/.node-version" | tr -d '[:space:]')
  CONFIDENCE=$((CONFIDENCE + 10))
  EVIDENCE+=(".node-version ($node_ver)")
fi

# .tool-versions with nodejs entry
if [[ -f "$PROJECT_DIR/.tool-versions" ]]; then
  if grep -q '^nodejs ' "$PROJECT_DIR/.tool-versions" 2>/dev/null; then
    CONFIDENCE=$((CONFIDENCE + 10))
    EVIDENCE+=(".tool-versions (nodejs)")
  fi
fi

# next.config.js/ts, vite.config.ts, webpack.config.js (framework signals)
if [[ -f "$PROJECT_DIR/next.config.js" ]] || [[ -f "$PROJECT_DIR/next.config.ts" ]] || [[ -f "$PROJECT_DIR/next.config.mjs" ]]; then
  CONFIDENCE=$((CONFIDENCE + 10))
  EVIDENCE+=("next.config")
elif [[ -f "$PROJECT_DIR/vite.config.ts" ]] || [[ -f "$PROJECT_DIR/vite.config.js" ]]; then
  CONFIDENCE=$((CONFIDENCE + 10))
  EVIDENCE+=("vite.config")
elif [[ -f "$PROJECT_DIR/webpack.config.js" ]] || [[ -f "$PROJECT_DIR/webpack.config.ts" ]]; then
  CONFIDENCE=$((CONFIDENCE + 10))
  EVIDENCE+=("webpack.config")
fi

# Negative signal: if this looks like a Rails project with a package.json,
# it's probably not primarily a Node project
if [[ -f "$PROJECT_DIR/Gemfile" ]] && grep -q "'rails'" "$PROJECT_DIR/Gemfile" 2>/dev/null; then
  CONFIDENCE=$((CONFIDENCE - 30))
fi

# Floor at 0
[[ $CONFIDENCE -lt 0 ]] && CONFIDENCE=0

# Cap at 100
[[ $CONFIDENCE -gt 100 ]] && CONFIDENCE=100

echo "CONFIDENCE:${CONFIDENCE}"
echo "EVIDENCE:$(IFS=', '; echo "${EVIDENCE[*]}")"
