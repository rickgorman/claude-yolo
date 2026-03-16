#!/usr/bin/env bash
set -euo pipefail

# Source common test framework (provides assert_*, pass, fail, section, print_summary)
source "$(dirname "$0")/lib/common.sh"

# Source the adb-qr-pair script with main disabled
_AQP_SCRIPT="$REPO_DIR/strategies/android/adb-qr-pair.sh"
_tmp_aqp="$TMPDIR_BASE/adb-qr-pair-functions.sh"
sed 's/^main "\$@"$/# main "$@"/' "$_AQP_SCRIPT" > "$_tmp_aqp"
source "$_tmp_aqp"

########################################
# Tests: generate_qr
########################################


section "generate_qr outputs 6-digit password to stdout"

qrencode() { :; }

password=$(generate_qr 2>/dev/null)
assert_match "Password is 6 digits" "$password" '^[0-9]{6}$'

unset -f qrencode


section "generate_qr calls qrencode with correct flags"

QR_CAPTURED_ARGS=""
qrencode() {
  QR_CAPTURED_ARGS="$*"
}

generate_qr 2>/dev/null >/dev/null

assert_contains "qrencode called with -t ANSIUTF8" "$QR_CAPTURED_ARGS" "-t ANSIUTF8"
assert_contains "qrencode called with -m 2" "$QR_CAPTURED_ARGS" "-m 2"

# Verify the QR string format
QR_STRING=""
for arg in $QR_CAPTURED_ARGS; do
  if [[ "$arg" == WIFI:* ]]; then
    QR_STRING="$arg"
  fi
done

assert_match "QR string matches WIFI:T:ADB format" "$QR_STRING" '^WIFI:T:ADB;S:[A-Za-z0-9]{6};P:[0-9]{6};;$'

unset -f qrencode


section "generate_qr produces unique values per call"

qrencode() { :; }

first_pass=$(generate_qr 2>/dev/null)
second_pass=$(generate_qr 2>/dev/null)

if [[ "$first_pass" != "$second_pass" ]]; then
  pass "Generates different passwords on each call"
else
  fail "Generates different passwords on each call (got same value twice)"
fi

unset -f qrencode

########################################
# Tests: wait_for_mdns
########################################


section "wait_for_mdns returns 1 when mDNS unavailable"

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

wait_for_mdns "123456" 2>/dev/null && result=0 || result=$?
assert_eq "Returns 1 when mDNS daemon not found" "1" "$result"

unset -f adb


section "wait_for_mdns discovers, pairs, and connects"

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

sleep() { :; }

wait_for_mdns "654321" 2>/dev/null && result=0 || result=$?

assert_eq "Returns 0 on successful pairing" "0" "$result"
assert_contains "Pairs with discovered address" "$_ADB_PAIR_LOG" "192.168.1.100:37123"
assert_contains "Pairs with provided password" "$_ADB_PAIR_LOG" "654321"
assert_contains "Connects to device after pairing" "$_ADB_CONNECT_LOG" "192.168.1.100:40001"

unset -f adb
unset -f sleep


section "wait_for_mdns returns 1 when pair fails"

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

wait_for_mdns "000000" 2>/dev/null && result=0 || result=$?
assert_eq "Returns 1 when adb pair fails" "1" "$result"

unset -f adb
unset -f sleep


section "wait_for_mdns times out when no device appears"

_POLL_COUNT_FILE="$TMPDIR_BASE/aqp-poll-count"
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

wait_for_mdns "999999" 2>/dev/null && result=0 || result=$?
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
# Tests: show_manual_instructions
########################################


section "show_manual_instructions includes key commands"

manual_output=$(show_manual_instructions 2>&1)

assert_contains "Includes adb pair command" "$manual_output" "adb pair"
assert_contains "Includes adb connect command" "$manual_output" "adb connect"

########################################
# Tests: --manual flag
########################################


section "--manual flag shows manual instructions without QR"

manual_output=$("$_AQP_SCRIPT" --manual 2>&1) && result=0 || result=$?

assert_eq "Exits with code 1 for --manual" "1" "$result"
assert_contains "Shows adb pair in manual mode" "$manual_output" "adb pair"
assert_contains "Shows adb connect in manual mode" "$manual_output" "adb connect"

########################################
# Tests: preflight — adb missing
########################################


section "Preflight exits 2 when adb missing"

# Create a minimal script that runs main with empty PATH to simulate missing adb
_exit_code_file="$TMPDIR_BASE/aqp-exit-code"
env -i PATH="/usr/bin" HOME="$HOME" bash -c "
  command() { return 1; }
  source '$_tmp_aqp'
  main 2>/dev/null
" > /dev/null 2>&1 && echo "0" > "$_exit_code_file" || echo "$?" > "$_exit_code_file"

exit_code=$(cat "$_exit_code_file")
assert_eq "Exits 2 when adb not found" "2" "$exit_code"

rm -f "$_exit_code_file"

print_summary "$(basename "$0" .sh)"
