#!/usr/bin/env bash
# Detection heuristics for Rails projects
#
# Outputs:
#   CONFIDENCE:<0-100>
#   EVIDENCE:<comma-separated list of what was found>

set -euo pipefail

PROJECT_DIR="${1:-.}"
CONFIDENCE=0
EVIDENCE=()

# Gemfile exists
if [[ -f "$PROJECT_DIR/Gemfile" ]]; then
  CONFIDENCE=$((CONFIDENCE + 20))
  if grep -q "'rails'" "$PROJECT_DIR/Gemfile" 2>/dev/null || \
     grep -q '"rails"' "$PROJECT_DIR/Gemfile" 2>/dev/null; then
    CONFIDENCE=$((CONFIDENCE + 40))
    EVIDENCE+=("Gemfile with rails")
  else
    EVIDENCE+=("Gemfile (no rails gem)")
  fi
fi

# config/application.rb
if [[ -f "$PROJECT_DIR/config/application.rb" ]]; then
  CONFIDENCE=$((CONFIDENCE + 20))
  EVIDENCE+=("config/application.rb")
fi

# .ruby-version
if [[ -f "$PROJECT_DIR/.ruby-version" ]]; then
  ruby_ver=$(cat "$PROJECT_DIR/.ruby-version" | tr -d '[:space:]')
  CONFIDENCE=$((CONFIDENCE + 10))
  EVIDENCE+=(".ruby-version ($ruby_ver)")
fi

# bin/rails
if [[ -f "$PROJECT_DIR/bin/rails" ]]; then
  CONFIDENCE=$((CONFIDENCE + 10))
  EVIDENCE+=("bin/rails")
fi

# Cap at 100
[[ $CONFIDENCE -gt 100 ]] && CONFIDENCE=100

echo "CONFIDENCE:${CONFIDENCE}"
echo "EVIDENCE:$(IFS=', '; echo "${EVIDENCE[*]}")"
