#!/usr/bin/env bash
# Go entrypoint for claude-yolo container
# Runs as root to fix volume permissions, then drops to claude user

set -euo pipefail

log() {
  echo "[entrypoint:go] $*" >&2
}

# Fix ownership on Docker volumes (created as root by default)
if [[ "$(id -u)" == "0" ]]; then
  chown -R claude:claude /home/claude/go /home/claude/.claude 2>/dev/null || true
  exec gosu claude "$0" "$@"
fi

export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:/usr/local/go/bin:$PATH"

log "Go: $(go version)"

# Download dependencies if go.mod exists
if [[ -f /workspace/go.mod ]]; then
  if [[ ! -d /workspace/vendor ]] && [[ ! -d "$GOPATH/pkg/mod/cache" ]] || [[ -z "$(ls -A "$GOPATH/pkg/mod/cache" 2>/dev/null)" ]]; then
    log "Downloading dependencies..."
    go mod download 2>/dev/null || true
  fi
fi

# Propagate host terminal dimensions to the container PTY
if [[ -t 0 ]] && [[ -n "${COLUMNS:-}" ]] && [[ -n "${LINES:-}" ]]; then
  stty columns "$COLUMNS" rows "$LINES" 2>/dev/null || true
fi

exec "$@"
