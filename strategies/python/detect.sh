#!/usr/bin/env bash
# Detection heuristics for Python projects
#
# Outputs:
#   CONFIDENCE:<0-100>
#   EVIDENCE:<comma-separated list of what was found>

set -euo pipefail

PROJECT_DIR="${1:-.}"
CONFIDENCE=0
EVIDENCE=()

# pyproject.toml (strong signal — modern Python)
if [[ -f "$PROJECT_DIR/pyproject.toml" ]]; then
  CONFIDENCE=$((CONFIDENCE + 35))
  EVIDENCE+=("pyproject.toml")
fi

# requirements.txt
if [[ -f "$PROJECT_DIR/requirements.txt" ]]; then
  CONFIDENCE=$((CONFIDENCE + 30))
  EVIDENCE+=("requirements.txt")
fi

# setup.py (legacy but common)
if [[ -f "$PROJECT_DIR/setup.py" ]]; then
  CONFIDENCE=$((CONFIDENCE + 20))
  EVIDENCE+=("setup.py")
fi

# setup.cfg
if [[ -f "$PROJECT_DIR/setup.cfg" ]]; then
  CONFIDENCE=$((CONFIDENCE + 10))
  EVIDENCE+=("setup.cfg")
fi

# .python-version (pyenv)
if [[ -f "$PROJECT_DIR/.python-version" ]]; then
  python_ver=$(cat "$PROJECT_DIR/.python-version" | tr -d '[:space:]')
  CONFIDENCE=$((CONFIDENCE + 15))
  EVIDENCE+=(".python-version ($python_ver)")
fi

# Pipfile (pipenv)
if [[ -f "$PROJECT_DIR/Pipfile" ]]; then
  CONFIDENCE=$((CONFIDENCE + 20))
  EVIDENCE+=("Pipfile")
fi

# poetry.lock
if [[ -f "$PROJECT_DIR/poetry.lock" ]]; then
  CONFIDENCE=$((CONFIDENCE + 10))
  EVIDENCE+=("poetry.lock")
fi

# uv.lock (uv package manager)
if [[ -f "$PROJECT_DIR/uv.lock" ]]; then
  CONFIDENCE=$((CONFIDENCE + 10))
  EVIDENCE+=("uv.lock")
fi

# tox.ini
if [[ -f "$PROJECT_DIR/tox.ini" ]]; then
  CONFIDENCE=$((CONFIDENCE + 5))
  EVIDENCE+=("tox.ini")
fi

# Cap at 100
[[ $CONFIDENCE -gt 100 ]] && CONFIDENCE=100

echo "CONFIDENCE:${CONFIDENCE}"
echo "EVIDENCE:$(IFS=', '; echo "${EVIDENCE[*]}")"
