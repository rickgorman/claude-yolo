#!/usr/bin/env bash
# Detection heuristics for Jekyll projects
#
# Outputs:
#   CONFIDENCE:<0-100>
#   EVIDENCE:<comma-separated list of what was found>

set -euo pipefail

PROJECT_DIR="${1:-.}"
CONFIDENCE=0
EVIDENCE=()

# _config.yml (strong Jekyll signal)
if [[ -f "$PROJECT_DIR/_config.yml" ]]; then
  CONFIDENCE=$((CONFIDENCE + 35))
  EVIDENCE+=("_config.yml")

  # Check for Jekyll-specific keys in _config.yml
  if grep -qE '^(remote_theme|theme|jekyll|plugins):' "$PROJECT_DIR/_config.yml" 2>/dev/null; then
    CONFIDENCE=$((CONFIDENCE + 15))
    EVIDENCE+=("Jekyll config keys")
  fi
fi

# Gemfile with jekyll gem
if [[ -f "$PROJECT_DIR/Gemfile" ]]; then
  if grep -q "'jekyll'" "$PROJECT_DIR/Gemfile" 2>/dev/null || \
     grep -q '"jekyll"' "$PROJECT_DIR/Gemfile" 2>/dev/null || \
     grep -q 'github-pages' "$PROJECT_DIR/Gemfile" 2>/dev/null; then
    CONFIDENCE=$((CONFIDENCE + 30))
    EVIDENCE+=("Gemfile with jekyll")
  fi
fi

# _layouts/ directory
if [[ -d "$PROJECT_DIR/_layouts" ]]; then
  CONFIDENCE=$((CONFIDENCE + 10))
  EVIDENCE+=("_layouts/")
fi

# _posts/ directory
if [[ -d "$PROJECT_DIR/_posts" ]]; then
  CONFIDENCE=$((CONFIDENCE + 5))
  EVIDENCE+=("_posts/")
fi

# _data/ directory
if [[ -d "$PROJECT_DIR/_data" ]]; then
  CONFIDENCE=$((CONFIDENCE + 5))
  EVIDENCE+=("_data/")
fi

# _includes/ directory
if [[ -d "$PROJECT_DIR/_includes" ]]; then
  CONFIDENCE=$((CONFIDENCE + 5))
  EVIDENCE+=("_includes/")
fi

# .ruby-version or .tool-versions with ruby
if [[ -f "$PROJECT_DIR/.ruby-version" ]]; then
  ruby_ver=$(cat "$PROJECT_DIR/.ruby-version" | tr -d '[:space:]')
  EVIDENCE+=(".ruby-version ($ruby_ver)")
elif [[ -f "$PROJECT_DIR/.tool-versions" ]]; then
  if grep -q '^ruby ' "$PROJECT_DIR/.tool-versions" 2>/dev/null; then
    EVIDENCE+=(".tool-versions (ruby)")
  fi
fi

# Negative signal: if this looks like a Rails project, it's not Jekyll
if [[ -f "$PROJECT_DIR/Gemfile" ]] && grep -q "'rails'" "$PROJECT_DIR/Gemfile" 2>/dev/null; then
  CONFIDENCE=$((CONFIDENCE - 50))
fi
if [[ -f "$PROJECT_DIR/config/application.rb" ]]; then
  CONFIDENCE=$((CONFIDENCE - 50))
fi

# Floor at 0
[[ $CONFIDENCE -lt 0 ]] && CONFIDENCE=0

# Cap at 100
[[ $CONFIDENCE -gt 100 ]] && CONFIDENCE=100

echo "CONFIDENCE:${CONFIDENCE}"
echo "EVIDENCE:$(IFS=', '; echo "${EVIDENCE[*]}")"
