#!/usr/bin/env bash
# Start Chrome with remote debugging enabled
# Used by claude-yolo to provide Chrome CDP access to Claude

set -euo pipefail

CDP_PORT="${CDP_PORT:-9222}"
PID_FILE="${TMPDIR:-/tmp}/claude-yolo-chrome-${CDP_PORT}.pid"

# Detect Chrome path based on OS
# YOLO_CHROME_BINARY="" disables Chrome detection (used in tests to prevent real launches)
detect_chrome() {
  if [[ -v YOLO_CHROME_BINARY ]]; then
    if [[ -n "$YOLO_CHROME_BINARY" && -x "$YOLO_CHROME_BINARY" ]]; then
      echo "$YOLO_CHROME_BINARY"
      return 0
    fi
    return 1
  fi

  local paths=(
    # macOS
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    "/Applications/Chromium.app/Contents/MacOS/Chromium"
    # Linux
    "/usr/bin/google-chrome"
    "/usr/bin/google-chrome-stable"
    "/usr/bin/chromium"
    "/usr/bin/chromium-browser"
  )

  for path in "${paths[@]}"; do
    if [[ -x "$path" ]]; then
      echo "$path"
      return 0
    fi
  done

  return 1
}

# Check if Chrome CDP is already running
cdp_running() {
  curl -s --connect-timeout 1 "http://localhost:${CDP_PORT}/json/version" &>/dev/null
}

stop_chrome() {
  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      echo "[start-chrome] Stopped Chrome (PID $pid, port ${CDP_PORT})" >&2
    fi
    rm -f "$PID_FILE"
  fi
}

main() {
  if [[ "${1:-}" == "--stop" ]]; then
    stop_chrome
    exit 0
  fi

  if cdp_running; then
    echo "[start-chrome] Chrome CDP already running on port ${CDP_PORT}" >&2
    exit 0
  fi

  local chrome_path
  chrome_path=$(detect_chrome) || {
    echo "[start-chrome] ERROR: Chrome not found" >&2
    exit 1
  }

  echo "[start-chrome] Starting Chrome with remote debugging on port ${CDP_PORT}..." >&2

  # Start Chrome in background with remote debugging
  # Using a unique user data dir per CDP port to avoid conflicts between worktrees
  local user_data_dir="${CHROME_USER_DATA_DIR:-${HOME}/.claude-yolo-chrome-${CDP_PORT}}"
  mkdir -p "$user_data_dir"

  "$chrome_path" \
    --headless=new \
    --remote-debugging-port="${CDP_PORT}" \
    --user-data-dir="$user_data_dir" \
    --no-first-run \
    --no-default-browser-check \
    --disable-background-networking \
    --disable-client-side-phishing-detection \
    --disable-default-apps \
    --disable-extensions \
    --disable-hang-monitor \
    --disable-popup-blocking \
    --disable-prompt-on-repost \
    --disable-sync \
    --disable-translate \
    --metrics-recording-only \
    --safebrowsing-disable-auto-update \
    &>/dev/null &

  CHROME_PID=$!
  echo "$CHROME_PID" > "$PID_FILE"

  # Wait for CDP to become available
  local attempts=0
  while ! cdp_running && [[ $attempts -lt 20 ]]; do
    sleep 0.5
    attempts=$((attempts + 1))
  done

  if cdp_running; then
    echo "[start-chrome] Chrome CDP ready on port ${CDP_PORT}" >&2
  else
    echo "[start-chrome] ERROR: Chrome CDP not available after startup" >&2
    exit 1
  fi
}

main "$@"
