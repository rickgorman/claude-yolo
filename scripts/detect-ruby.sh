#!/usr/bin/env bash
# Detect Ruby version from project files
# Checks .ruby-version first, then parses Gemfile

set -euo pipefail

detect_ruby_version() {
  local project_dir="${1:-.}"

  # Try .ruby-version first
  if [[ -f "${project_dir}/.ruby-version" ]]; then
    cat "${project_dir}/.ruby-version" | tr -d '[:space:]'
    return 0
  fi

  # Try .tool-versions (asdf)
  if [[ -f "${project_dir}/.tool-versions" ]]; then
    grep "^ruby " "${project_dir}/.tool-versions" 2>/dev/null | awk '{print $2}' | head -1
    if [[ $? -eq 0 ]]; then
      return 0
    fi
  fi

  # Fall back to parsing Gemfile
  if [[ -f "${project_dir}/Gemfile" ]]; then
    local version
    version=$(grep -E "^ruby ['\"]" "${project_dir}/Gemfile" 2>/dev/null | \
      sed -E "s/ruby ['\"]([^'\"]+)['\"].*/\1/" | head -1)
    if [[ -n "$version" ]]; then
      echo "$version"
      return 0
    fi
  fi

  # Default fallback
  echo "3.3.0"
}

detect_ruby_version "${1:-.}"
