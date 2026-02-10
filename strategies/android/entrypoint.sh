#!/usr/bin/env bash
# Android entrypoint for claude-yolo container
# Starts ADB, optionally connects to a wireless device, ensures gradlew is executable

set -euo pipefail

log() {
  echo "[entrypoint:android] $*" >&2
}

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

exec "$@"
