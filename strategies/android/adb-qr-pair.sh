#!/usr/bin/env bash
# In-container ADB QR reconnect for wireless debugging
#
# Exit codes:
#   0 = paired and connected
#   1 = failed (agent should try manual fallback)
#   2 = fatal (missing tools)
#
# Usage:
#   adb-qr-pair            # QR code pairing (default)
#   adb-qr-pair --manual   # Show manual pairing instructions

set -euo pipefail

log() {
  echo "[adb-qr-pair] $*" >&2
}

generate_qr() {
  local service_name password qr_string

  service_name=$(head -c 100 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 6)
  password=$(head -c 500 /dev/urandom | LC_ALL=C tr -dc '0-9' | head -c 6)

  qr_string="WIFI:T:ADB;S:${service_name};P:${password};;"

  log "On your phone: Developer Options → Wireless Debugging → Pair with QR code"
  echo "" >&2
  qrencode -t ANSIUTF8 -m 2 "$qr_string" >&2
  echo "" >&2
  log "Scan this QR code with your Android device"

  # Password on stdout for internal capture
  echo "$password"
}

wait_for_mdns() {
  local password="$1"
  local timeout=60
  local elapsed=0
  local interval=2

  if ! adb mdns check 2>/dev/null | grep -q "mdns daemon"; then
    log "ADB mDNS not available — cannot discover devices"
    return 1
  fi

  log "Waiting for device to appear (${timeout}s timeout)..."

  while [[ $elapsed -lt $timeout ]]; do
    local services
    services=$(adb mdns services 2>/dev/null || true)
    local pair_line
    pair_line=$(echo "$services" | grep "_adb-tls-pairing" | head -1 || true)

    if [[ -n "$pair_line" ]]; then
      local pair_addr
      pair_addr=$(echo "$pair_line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+' | head -1 || true)

      if [[ -n "$pair_addr" ]]; then
        log "Device found! Pairing with ${pair_addr}..."
        if adb pair "$pair_addr" "$password" 2>&1; then
          log "Paired successfully"

          sleep 2
          local connect_line
          connect_line=$(adb mdns services 2>/dev/null | grep "_adb-tls-connect" | head -1 || true)
          local connect_addr
          connect_addr=$(echo "$connect_line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+' | head -1 || true)

          if [[ -n "$connect_addr" ]]; then
            log "Connecting to ${connect_addr}..."
            adb connect "$connect_addr" 2>&1 || log "Connect failed (device may still be reachable)"
          fi
          return 0
        else
          log "Pairing failed"
          return 1
        fi
      fi
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  log "Timed out waiting for device"
  return 1
}

show_manual_instructions() {
  log "Manual wireless debugging steps:"
  log "  1. On phone: Developer Options → Wireless Debugging → Enable"
  log "  2. Tap 'Pair device with pairing code' to get IP:port and code"
  log "  3. Run: adb pair <ip:port> <pairing-code>"
  log "  4. Then: adb connect <ip:port>"
  log "  5. Verify: adb devices -l"
}

main() {
  # Handle --manual flag
  if [[ "${1:-}" == "--manual" ]]; then
    show_manual_instructions
    exit 1
  fi

  # Preflight: check adb
  if ! command -v adb &>/dev/null; then
    log "FATAL: adb not found on PATH"
    exit 2
  fi

  # Log host forwarding config
  if [[ -n "${ANDROID_ADB_SERVER_ADDRESS:-}" ]]; then
    log "ADB server address: ${ANDROID_ADB_SERVER_ADDRESS}"
  fi

  # Show current device status
  log "Current devices:"
  adb devices -l 2>/dev/null | tail -n +2 | grep -v "^$" | while read -r line; do
    log "  $line"
  done || true

  # Check qrencode availability
  if ! command -v qrencode &>/dev/null; then
    log "qrencode not found — falling back to manual instructions"
    show_manual_instructions
    exit 1
  fi

  # Generate QR and capture password from stdout
  local password
  password=$(generate_qr)

  # Wait for mDNS discovery and pair
  if wait_for_mdns "$password"; then
    log "Wireless debugging reconnected"
    adb devices -l 2>/dev/null | tail -n +2 | grep -v "^$" | while read -r line; do
      log "  $line"
    done || true
    exit 0
  fi

  # Pairing failed — show manual fallback
  log "QR pairing failed — try manual pairing instead"
  show_manual_instructions
  exit 1
}

main "$@"
