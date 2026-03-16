#!/usr/bin/env bash
set -euo pipefail

# Source common test framework
source "$(dirname "$0")/lib/common.sh"

########################################
# Tests: generate_qr_pairing_code
########################################


section "generate_qr_pairing_code sets globals"

# Mock qrencode to capture its arguments
QR_CAPTURED_ARGS=""
qrencode() {
  QR_CAPTURED_ARGS="$*"
}

generate_qr_pairing_code 2>/dev/null

assert_match "Sets _QR_SERVICE_NAME to 6 alphanumeric chars" "$_QR_SERVICE_NAME" '^[A-Za-z0-9]{6}$'
assert_match "Sets _QR_PASSWORD to 6 digits" "$_QR_PASSWORD" '^[0-9]{6}$'

unset -f qrencode


section "generate_qr_pairing_code builds correct QR string"

QR_CAPTURED_STRING=""
qrencode() {
  # Capture the last positional argument (the QR string)
  for arg in "$@"; do :; done
  QR_CAPTURED_STRING="$arg"
}

generate_qr_pairing_code 2>/dev/null

assert_match "QR string starts with WIFI:T:ADB;S:" "$QR_CAPTURED_STRING" '^WIFI:T:ADB;S:'
assert_contains "QR string contains service name" "$QR_CAPTURED_STRING" ";S:${_QR_SERVICE_NAME};"
assert_contains "QR string contains password" "$QR_CAPTURED_STRING" ";P:${_QR_PASSWORD};;"
assert_match "QR string matches full format" "$QR_CAPTURED_STRING" '^WIFI:T:ADB;S:[A-Za-z0-9]{6};P:[0-9]{6};;$'

unset -f qrencode


section "generate_qr_pairing_code passes ANSIUTF8 to qrencode"

QR_CAPTURED_FULL=""
qrencode() {
  QR_CAPTURED_FULL="$*"
}

generate_qr_pairing_code 2>/dev/null

assert_contains "qrencode called with -t ANSIUTF8" "$QR_CAPTURED_FULL" "-t ANSIUTF8"
assert_contains "qrencode called with -m 2" "$QR_CAPTURED_FULL" "-m 2"

unset -f qrencode


section "generate_qr_pairing_code produces unique values per call"

qrencode() { :; }

generate_qr_pairing_code 2>/dev/null
first_name="$_QR_SERVICE_NAME"
first_pass="$_QR_PASSWORD"

generate_qr_pairing_code 2>/dev/null
second_name="$_QR_SERVICE_NAME"
second_pass="$_QR_PASSWORD"

if [[ "$first_name" != "$second_name" || "$first_pass" != "$second_pass" ]]; then
  pass "Generates different credentials on each call"
else
  fail "Generates different credentials on each call (got same values twice)"
fi

unset -f qrencode

########################################
# Tests: wait_for_mdns_pair — no mDNS
########################################


section "wait_for_mdns_pair returns 1 when mDNS unavailable"

adb() {
  case "$1" in
    mdns)
      case "$2" in
        check) echo "adb: mDNS not supported"; return 0 ;;
      esac
      ;;
  esac
  return 0
}

wait_for_mdns_pair "123456" 2>/dev/null && result=0 || result=$?
assert_eq "Returns 1 when mDNS daemon not found" "1" "$result"

unset -f adb

########################################
# Tests: wait_for_mdns_pair — successful pair
########################################


section "wait_for_mdns_pair discovers and pairs device"

_ADB_PAIR_LOG=""
_ADB_CONNECT_LOG=""
adb() {
  case "$1" in
    mdns)
      case "$2" in
        check) echo "mdns daemon running: yes"; return 0 ;;
        services)
          echo "adb-ABCDEF	_adb-tls-pairing._tcp.local.	192.168.1.100:37123"
          echo "adb-ABCDEF	_adb-tls-connect._tcp.local.	192.168.1.100:40001"
          return 0
          ;;
      esac
      ;;
    pair)
      _ADB_PAIR_LOG="pair $2 $3"
      echo "Successfully paired"
      return 0
      ;;
    connect)
      _ADB_CONNECT_LOG="connect $2"
      echo "connected to $2"
      return 0
      ;;
  esac
  return 0
}

# Override sleep to avoid delays in tests
sleep() { :; }

wait_for_mdns_pair "654321" 2>/dev/null && result=0 || result=$?

assert_eq "Returns 0 on successful pairing" "0" "$result"
assert_contains "Pairs with discovered address" "$_ADB_PAIR_LOG" "192.168.1.100:37123"
assert_contains "Pairs with provided password" "$_ADB_PAIR_LOG" "654321"
assert_contains "Connects to device after pairing" "$_ADB_CONNECT_LOG" "192.168.1.100:40001"

unset -f adb
unset -f sleep

########################################
# Tests: wait_for_mdns_pair — pair fails
########################################


section "wait_for_mdns_pair returns 1 when pairing fails"

adb() {
  case "$1" in
    mdns)
      case "$2" in
        check) echo "mdns daemon running: yes"; return 0 ;;
        services)
          echo "adb-ABCDEF	_adb-tls-pairing._tcp.local.	192.168.1.100:37123"
          return 0
          ;;
      esac
      ;;
    pair) echo "Failed: pairing rejected"; return 1 ;;
  esac
  return 0
}

sleep() { :; }

wait_for_mdns_pair "000000" 2>/dev/null && result=0 || result=$?
assert_eq "Returns 1 when adb pair fails" "1" "$result"

unset -f adb
unset -f sleep

########################################
# Tests: wait_for_mdns_pair — no connect service
########################################


section "wait_for_mdns_pair succeeds even without connect service"

_ADB_CONNECT_CALLED=false
adb() {
  case "$1" in
    mdns)
      case "$2" in
        check) echo "mdns daemon running: yes"; return 0 ;;
        services)
          # Pairing service visible, but no connect service
          echo "adb-ABCDEF	_adb-tls-pairing._tcp.local.	192.168.1.100:37123"
          return 0
          ;;
      esac
      ;;
    pair) echo "Successfully paired"; return 0 ;;
    connect) _ADB_CONNECT_CALLED=true; return 0 ;;
  esac
  return 0
}

sleep() { :; }

wait_for_mdns_pair "111111" 2>/dev/null && result=0 || result=$?
assert_eq "Returns 0 even without connect service" "0" "$result"

unset -f adb
unset -f sleep

########################################
# Tests: wait_for_mdns_pair — timeout
########################################


section "wait_for_mdns_pair times out when no device appears"

# Use a file-based counter since adb runs in subshell via $()
_POLL_COUNT_FILE="$TMPDIR_BASE/poll-count"
echo "0" > "$_POLL_COUNT_FILE"

adb() {
  case "$1" in
    mdns)
      case "$2" in
        check) echo "mdns daemon running: yes"; return 0 ;;
        services)
          local count
          count=$(cat "$_POLL_COUNT_FILE")
          echo $((count + 1)) > "$_POLL_COUNT_FILE"
          echo ""
          return 0
          ;;
      esac
      ;;
  esac
  return 0
}

sleep() { :; }

wait_for_mdns_pair "999999" 2>/dev/null && result=0 || result=$?
assert_eq "Returns 1 on timeout" "1" "$result"

_final_poll_count=$(cat "$_POLL_COUNT_FILE")
if [[ $_final_poll_count -gt 5 ]]; then
  pass "Polled mDNS services multiple times before timeout ($_final_poll_count polls)"
else
  fail "Polled mDNS services multiple times before timeout (only $_final_poll_count polls)"
fi

rm -f "$_POLL_COUNT_FILE"
unset -f adb
unset -f sleep

########################################
# Tests: preflight_android_adb — QR path
########################################


section "preflight_android_adb uses QR when qrencode available"

# Mock uname to simulate macOS
uname() { echo "Darwin"; }

# Use file-based counter since adb devices runs in subshell via $()
_ADB_CALL_FILE="$TMPDIR_BASE/adb-call-count"
echo "0" > "$_ADB_CALL_FILE"

adb() {
  case "$1" in
    start-server) return 0 ;;
    devices)
      local count
      count=$(cat "$_ADB_CALL_FILE")
      echo $((count + 1)) > "$_ADB_CALL_FILE"
      if [[ $count -lt 1 ]]; then
        echo "List of devices attached"
        echo ""
      else
        echo "List of devices attached"
        echo "192.168.1.100:40001	device"
        echo ""
      fi
      return 0
      ;;
    mdns)
      case "$2" in
        check) echo "mdns daemon running: yes"; return 0 ;;
        services)
          echo "adb-ABCDEF	_adb-tls-pairing._tcp.local.	192.168.1.100:37123"
          echo "adb-ABCDEF	_adb-tls-connect._tcp.local.	192.168.1.100:40001"
          return 0
          ;;
      esac
      ;;
    pair) echo "Successfully paired"; return 0 ;;
    connect) echo "connected"; return 0 ;;
  esac
  return 0
}

qrencode() { :; }
sleep() { :; }

# Run directly (not in subshell) so _ADB_USE_HOST_SERVER propagates
# Feed "Y" on stdin for the read prompt, redirect output to file
_ADB_USE_HOST_SERVER=false
preflight_android_adb < <(echo "Y") 2>"$TMPDIR_BASE/qr-preflight-output" || true

assert_eq "Sets _ADB_USE_HOST_SERVER on QR success" "true" "$_ADB_USE_HOST_SERVER"

_ADB_USE_HOST_SERVER=false
rm -f "$_ADB_CALL_FILE"
unset -f uname adb qrencode sleep

########################################
# Tests: preflight_android_adb — no qrencode fallback
########################################


section "preflight_android_adb shows tip when qrencode unavailable"

uname() { echo "Darwin"; }

adb() {
  case "$1" in
    start-server) return 0 ;;
    devices)
      echo "List of devices attached"
      echo ""
      return 0
      ;;
  esac
  return 0
}

sleep() { :; }

# Override command so "command -v qrencode" fails
command() {
  if [[ "$1" == "-v" && "$2" == "qrencode" ]]; then
    return 1
  fi
  builtin command "$@"
}

# Feed "Y" then empty string (for pairing address prompt) to exit the manual flow
# Redirect stderr (where the tip box is printed) to a file
_TIP_OUTPUT="$TMPDIR_BASE/tip-output"
preflight_android_adb < <(printf "Y\n\n") 2>"$_TIP_OUTPUT" || true

output=$(cat "$_TIP_OUTPUT")
assert_contains "Shows qrencode install tip" "$output" "Install qrencode"
assert_contains "Shows brew install command" "$output" "brew install qrencode"
assert_contains "Shows tip box border" "$output" "one-scan QR pairing"

rm -f "$_TIP_OUTPUT"
unset -f uname adb sleep command

########################################
# Tests: preflight_android_adb — skip on 'n'
########################################


section "preflight_android_adb skips when user declines"

uname() { echo "Darwin"; }

adb() {
  case "$1" in
    start-server) return 0 ;;
    devices)
      echo "List of devices attached"
      echo ""
      return 0
      ;;
  esac
  return 0
}

_ADB_USE_HOST_SERVER=false
preflight_android_adb < <(echo "n") 2>/dev/null || true

assert_eq "Does not set _ADB_USE_HOST_SERVER when declined" "false" "$_ADB_USE_HOST_SERVER"

unset -f uname adb

########################################
# Tests: preflight_android_adb — non-Darwin
########################################


section "preflight_android_adb is no-op on non-Darwin"

uname() { echo "Linux"; }

_ADB_USE_HOST_SERVER=false
preflight_android_adb 2>/dev/null || true

assert_eq "Returns early on Linux" "false" "$_ADB_USE_HOST_SERVER"

unset -f uname

########################################
# Tests: preflight_android_adb — devices already connected
########################################


section "preflight_android_adb skips pairing when devices exist"

uname() { echo "Darwin"; }

adb() {
  case "$1" in
    start-server) return 0 ;;
    devices)
      if [[ "${2:-}" == "-l" ]]; then
        echo "List of devices attached"
        echo "emulator-5554          device product:sdk_phone"
        echo ""
      else
        echo "List of devices attached"
        echo "emulator-5554	device"
        echo ""
      fi
      return 0
      ;;
  esac
  return 0
}

_ADB_USE_HOST_SERVER=false
preflight_android_adb 2>/dev/null || true

assert_eq "Sets _ADB_USE_HOST_SERVER when devices already connected" "true" "$_ADB_USE_HOST_SERVER"

unset -f uname adb

########################################
# Tests: wait_for_mdns_pair — extracts address from varied formats
########################################


section "wait_for_mdns_pair handles different mDNS output formats"

_ADB_PAIR_ADDR=""
adb() {
  case "$1" in
    mdns)
      case "$2" in
        check) echo "mdns daemon running: yes"; return 0 ;;
        services)
          # Slightly different format with extra whitespace
          echo "adb-XYZ123	_adb-tls-pairing._tcp.	10.0.0.42:41234"
          echo "adb-XYZ123	_adb-tls-connect._tcp.	10.0.0.42:5555"
          return 0
          ;;
      esac
      ;;
    pair)
      _ADB_PAIR_ADDR="$2"
      echo "Successfully paired"
      return 0
      ;;
    connect) return 0 ;;
  esac
  return 0
}

sleep() { :; }

wait_for_mdns_pair "123456" 2>/dev/null && result=0 || result=$?

assert_eq "Extracts IP:port from mDNS output" "10.0.0.42:41234" "$_ADB_PAIR_ADDR"

unset -f adb sleep

print_summary "$(basename "$0" .sh)"
