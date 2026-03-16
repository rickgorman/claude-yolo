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

# Fix Docker socket permissions for --with-docker
if [[ "$(id -u)" == "0" ]] && [[ -S /var/run/docker.sock ]]; then
  SOCK_GID=$(stat -c '%g' /var/run/docker.sock)
  SOCK_GROUP=$(getent group "$SOCK_GID" | cut -d: -f1 || true)
  if [[ -z "${SOCK_GROUP:-}" ]]; then
    SOCK_GROUP=dockerhost
    groupadd -g "$SOCK_GID" "$SOCK_GROUP"
  fi
  usermod -aG "$SOCK_GROUP" claude
elif [[ -S /var/run/docker.sock ]]; then
  SOCK_GID=$(stat -c '%g' /var/run/docker.sock)
  SOCK_GROUP=$(getent group "$SOCK_GID" | cut -d: -f1 || true)
  if [[ -z "${SOCK_GROUP:-}" ]]; then
    SOCK_GROUP=dockerhost
    sudo groupadd -g "$SOCK_GID" "$SOCK_GROUP" 2>/dev/null || true
  fi
  if ! id -nG claude 2>/dev/null | grep -qw "$SOCK_GROUP"; then
    sudo usermod -aG "$SOCK_GROUP" claude 2>/dev/null || true
  fi
fi

log "Java: $(java -version 2>&1 | head -1)"
log "Android SDK: $ANDROID_HOME"
log "ADB: $(adb version | head -1)"

# ADB setup: remote host server (macOS Docker bridge) or local server
if [[ -n "${ADB_HOST:-}" ]]; then
  # macOS: use host's ADB server via Docker bridge
  export ANDROID_ADB_SERVER_ADDRESS="${ADB_HOST}"
  export ANDROID_ADB_SERVER_PORT="${ADB_PORT:-5037}"
  log "Using host ADB server at ${ADB_HOST}:${ADB_PORT:-5037}"
else
  # Linux / direct: start local ADB server
  log "Starting ADB server..."
  adb start-server
  if [[ -n "${ANDROID_DEVICE:-}" ]]; then
    log "Connecting to Android device at ${ANDROID_DEVICE}..."
    adb connect "$ANDROID_DEVICE" || log "WARNING: Could not connect to device at ${ANDROID_DEVICE}"
  fi
fi

# List connected devices
adb devices -l 2>/dev/null | tail -n +2 | grep -v "^$" | while read -r line; do
  log "Device: $line"
done || true

log "QR pairing available: run 'adb-qr-pair' to reconnect wireless debugging"

# Ensure gradlew is executable if present
if [[ -f /workspace/gradlew ]]; then
  chmod +x /workspace/gradlew
fi

# Propagate host terminal dimensions to the container PTY
if [[ -t 0 ]] && [[ -n "${COLUMNS:-}" ]] && [[ -n "${LINES:-}" ]]; then
  stty columns "$COLUMNS" rows "$LINES" 2>/dev/null || true
fi

exec "$@"
