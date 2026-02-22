#!/usr/bin/env bash
# Node.js entrypoint for claude-yolo container
# Runs as root to fix volume permissions, then drops to claude user

set -euo pipefail

log() {
  echo "[entrypoint:node] $*" >&2
}

# Fix ownership on Docker volumes (created as root by default)
if [[ "$(id -u)" == "0" ]]; then
  chown -R claude:claude /home/claude/.nvm /home/claude/.claude 2>/dev/null || true
  chown claude:claude /workspace/node_modules 2>/dev/null || true

  # Create minimal .gitconfig from environment variables
  if [[ -n "${GIT_USER_NAME:-}" || -n "${GIT_USER_EMAIL:-}" ]]; then
    cat > /home/claude/.gitconfig << EOF
[user]
	name = ${GIT_USER_NAME}
	email = ${GIT_USER_EMAIL}
EOF
    chown claude:claude /home/claude/.gitconfig
  fi
  exec gosu claude "$0" "$@"
fi

# Initialize nvm
export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Install Node.js if NODE_VERSION is set and not already installed
if [[ -n "${NODE_VERSION:-}" ]]; then
  if ! nvm ls "$NODE_VERSION" &>/dev/null; then
    log "Installing Node.js ${NODE_VERSION} (this may take a moment on first run)..."
    nvm install "$NODE_VERSION"
  fi
  nvm use "$NODE_VERSION"
  log "Using Node.js ${NODE_VERSION}"
elif [[ -f /workspace/.nvmrc ]]; then
  log "Found .nvmrc, installing specified version..."
  nvm install 2>/dev/null || true
  nvm use 2>/dev/null || true
elif [[ -f /workspace/.node-version ]]; then
  node_ver=$(cat /workspace/.node-version | tr -d '[:space:]')
  log "Found .node-version (${node_ver}), installing..."
  nvm install "$node_ver" 2>/dev/null || true
  nvm use "$node_ver" 2>/dev/null || true
fi

log "Node.js: $(node --version 2>/dev/null || echo 'not installed')"
log "npm: $(npm --version 2>/dev/null || echo 'not installed')"

# Install dependencies based on lockfile
if [[ -f /workspace/package.json ]] && [[ -z "$(ls -A /workspace/node_modules 2>/dev/null)" ]]; then
  if [[ -f /workspace/pnpm-lock.yaml ]]; then
    if ! command -v pnpm &>/dev/null; then
      log "Installing pnpm..."
      npm install -g pnpm
    fi
    log "Running pnpm install..."
    pnpm install 2>/dev/null || true
  elif [[ -f /workspace/yarn.lock ]]; then
    if ! command -v yarn &>/dev/null; then
      log "Installing yarn..."
      npm install -g yarn
    fi
    log "Running yarn install..."
    yarn install --frozen-lockfile 2>/dev/null || yarn install 2>/dev/null || true
  elif [[ -f /workspace/bun.lockb ]] || [[ -f /workspace/bun.lock ]]; then
    if ! command -v bun &>/dev/null; then
      log "Installing bun..."
      npm install -g bun
    fi
    log "Running bun install..."
    bun install 2>/dev/null || true
  else
    log "Running npm install..."
    npm install 2>/dev/null || true
  fi
fi

# Propagate host terminal dimensions to the container PTY
if [[ -t 0 ]] && [[ -n "${COLUMNS:-}" ]] && [[ -n "${LINES:-}" ]]; then
  stty columns "$COLUMNS" rows "$LINES" 2>/dev/null || true
fi

exec "$@"
