#!/usr/bin/env bash
# Android entrypoint for claude-yolo container
# Starts ADB, optionally connects to a wireless device, ensures gradlew is executable

set -euo pipefail

log() {
  echo "[entrypoint:android] $*" >&2
}

# Create minimal .gitconfig from environment variables
if [[ -n "${GIT_USER_NAME:-}" || -n "${GIT_USER_EMAIL:-}" ]]; then
  cat > /home/claude/.gitconfig << EOF
[user]
	name = ${GIT_USER_NAME}
	email = ${GIT_USER_EMAIL}
EOF
fi

log "Java: $(java -version 2>&1 | head -1)"
log "Android SDK: $ANDROID_HOME"
log "ADB: $(adb version | head -1)"

# Start ADB server
log "Starting ADB server..."
adb start-server

# Connect to wireless device if ANDROID_DEVICE is set (ip:port)
if [[ -n "${ANDROID_DEVICE:-}" ]]; then
  log "Connecting to Android device at ${ANDROID_DEVICE}..."
  adb connect "$ANDROID_DEVICE" || log "WARNING: Could not connect to device at ${ANDROID_DEVICE}"
fi

# List connected devices
adb devices -l 2>/dev/null | tail -n +2 | grep -v "^$" | while read -r line; do
  log "Device: $line"
done || true

# Ensure gradlew is executable if present
if [[ -f /workspace/gradlew ]]; then
  chmod +x /workspace/gradlew
fi

# Propagate host terminal dimensions to the container PTY
if [[ -t 0 ]] && [[ -n "${COLUMNS:-}" ]] && [[ -n "${LINES:-}" ]]; then
  stty columns "$COLUMNS" rows "$LINES" 2>/dev/null || true
fi

exec "$@"
