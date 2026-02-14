#!/usr/bin/env bash
# Python entrypoint for claude-yolo container
# Runs as root to fix volume permissions, then drops to claude user

set -euo pipefail

log() {
  echo "[entrypoint:python] $*" >&2
}

# Fix ownership on Docker volumes (created as root by default)
if [[ "$(id -u)" == "0" ]]; then
  chown -R claude:claude /home/claude/.pyenv /home/claude/.claude 2>/dev/null || true
  exec gosu claude "$0" "$@"
fi

# Initialize pyenv
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
eval "$(pyenv init -)"

# Install Python if PYTHON_VERSION is set and not already installed
if [[ -n "${PYTHON_VERSION:-}" ]]; then
  if ! pyenv versions --bare | grep -q "^${PYTHON_VERSION}$"; then
    log "Installing Python ${PYTHON_VERSION} (this may take a few minutes on first run)..."
    pyenv install "$PYTHON_VERSION"
  fi
  pyenv global "$PYTHON_VERSION"
  log "Using Python ${PYTHON_VERSION}"
fi

# Install dependencies based on project tooling
if [[ -f /workspace/pyproject.toml ]]; then
  # Check for uv.lock first (fastest), then poetry.lock, then fall back to pip
  if [[ -f /workspace/uv.lock ]] && command -v uv &>/dev/null; then
    log "Running uv sync..."
    uv sync 2>/dev/null || true
  elif [[ -f /workspace/poetry.lock ]] && command -v poetry &>/dev/null; then
    log "Running poetry install..."
    poetry install --no-interaction 2>/dev/null || true
  else
    log "Running pip install..."
    pip install -e ".[dev]" 2>/dev/null || pip install -e . 2>/dev/null || true
  fi
elif [[ -f /workspace/requirements.txt ]]; then
  log "Running pip install -r requirements.txt..."
  pip install -r /workspace/requirements.txt 2>/dev/null || true
elif [[ -f /workspace/Pipfile ]] && command -v pipenv &>/dev/null; then
  log "Running pipenv install..."
  pipenv install --dev 2>/dev/null || true
fi

# Propagate host terminal dimensions to the container PTY
if [[ -t 0 ]] && [[ -n "${COLUMNS:-}" ]] && [[ -n "${LINES:-}" ]]; then
  stty columns "$COLUMNS" rows "$LINES" 2>/dev/null || true
fi

exec "$@"
