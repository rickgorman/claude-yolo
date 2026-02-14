#!/usr/bin/env bash
# Generic entrypoint for claude-yolo container
# Runs as root to fix volume permissions, then drops to claude user

set -euo pipefail

log() {
  echo "[entrypoint:generic] $*" >&2
}

# Fix ownership on Docker volumes (created as root by default)
if [[ "$(id -u)" == "0" ]]; then
  chown -R claude:claude /home/claude/.claude 2>/dev/null || true
  exec gosu claude "$0" "$@"
fi

# Propagate host terminal dimensions to the container PTY
if [[ -t 0 ]] && [[ -n "${COLUMNS:-}" ]] && [[ -n "${LINES:-}" ]]; then
  stty columns "$COLUMNS" rows "$LINES" 2>/dev/null || true
fi

exec "$@"
