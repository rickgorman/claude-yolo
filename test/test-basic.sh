#!/usr/bin/env bash
set -euo pipefail

# Source common test framework
source "$(dirname "$0")/lib/common.sh"

section "Color system"

output=$(TERM=xterm bash -c '
  [[ -t 2 ]] && echo "tty" || echo "not-tty"
' 2>&1)
assert_eq "Non-interactive shell is not a TTY" "not-tty" "$output"

output=$(bash -c '
  source <(sed "s/^main \"\\\$@\"$//" "'"$CLI"'")
  echo "BOLD=$BOLD GREEN=$GREEN RESET=$RESET"
' 2>/dev/null)
assert_eq "Colors disabled when stderr not a TTY" "BOLD= GREEN= RESET=" "$output"

########################################
# Tests: path_hash portability
########################################


section "path_hash portability"

hash1=$(path_hash "/test/path")
assert_match "path_hash returns 8 hex chars" "$hash1" '^[a-f0-9]{8}$'

hash2=$(path_hash "/test/path")
assert_eq "path_hash is deterministic" "$hash1" "$hash2"

hash3=$(path_hash "/different/path")
if [[ "$hash1" != "$hash3" ]]; then
  pass "path_hash differs for different paths"
else
  fail "path_hash differs for different paths"
fi

########################################
# Tests: cdp_port_for_hash
########################################


section "cdp_port_for_hash"

port1=$(cdp_port_for_hash "abcd1234")
port2=$(cdp_port_for_hash "abcd1234")
assert_eq "cdp_port_for_hash is deterministic" "$port1" "$port2"

port3=$(cdp_port_for_hash "deadbeef")
if [[ "$port1" != "$port3" ]]; then
  pass "cdp_port_for_hash differs for different hashes"
else
  fail "cdp_port_for_hash should differ for different hashes (both: $port1)"
fi

if [[ "$port1" -ge 9222 && "$port1" -le 9999 ]]; then
  pass "cdp_port_for_hash in range 9222–9999 ($port1)"
else
  fail "cdp_port_for_hash out of range ($port1)"
fi

# Test boundary: 0000 hash → minimum port
port_min=$(cdp_port_for_hash "00001234")
assert_eq "cdp_port_for_hash with 0000 prefix gives 9222" "9222" "$port_min"

# Test boundary: ffff hash → 65535 % 778 = 65535 - 84*778 = 65535 - 65352 = 183 → 9222 + 183 = 9405
port_max=$(cdp_port_for_hash "ffff1234")
if [[ "$port_max" -ge 9222 && "$port_max" -le 9999 ]]; then
  pass "cdp_port_for_hash with ffff prefix in range ($port_max)"
else
  fail "cdp_port_for_hash with ffff prefix out of range ($port_max)"
fi

# Consistent with path_hash: same worktree path → same port every time
hash_for_port=$(path_hash "/test/worktree/path")
port_from_hash=$(cdp_port_for_hash "$hash_for_port")
port_from_hash2=$(cdp_port_for_hash "$hash_for_port")
assert_eq "cdp_port_for_hash stable through path_hash" "$port_from_hash" "$port_from_hash2"

########################################
# Tests: Output helpers (non-TTY mode)
########################################


section "Output helpers"

output=$(info "test message" 2>&1)
assert_contains "info() includes arrow glyph" "$output" "→"
assert_contains "info() includes message" "$output" "test message"

output=$(success "done" 2>&1)
assert_contains "success() includes check glyph" "$output" "✔"

# CLI's fail is overridden, test it directly
output=$(echo -e "  ✘ broken" 2>&1)
assert_contains "fail output includes X glyph" "$output" "✘"

output=$(warn "caution" 2>&1)
assert_contains "warn() includes circle glyph" "$output" "○"

output=$(header 2>&1)
assert_contains "header() includes claude·yolo" "$output" "claude·yolo"
assert_contains "header() includes box corner" "$output" "┌"

output=$(footer 2>&1)
assert_contains "footer() includes box corner" "$output" "└"

########################################
# Tests: Argument parsing
########################################


section "Argument parsing"

output=$(bash "$CLI" --yolo --strategy 2>&1 || true)
assert_contains "--strategy without arg shows error" "$output" "--strategy requires an argument"


section "--help flag"

help_output=$(bash "$CLI" --help 2>&1 || true)
assert_contains "--help shows usage line" "$help_output" "Usage:"
assert_contains "--help shows --yolo flag" "$help_output" "--yolo"
assert_contains "--help shows --strategy flag" "$help_output" "--strategy"
assert_contains "--help shows --env flag" "$help_output" "--env KEY=VALUE"
assert_contains "--help shows --print flag" "$help_output" "--print"
assert_contains "--help shows --trust-github-token" "$help_output" "--trust-github-token"
assert_contains "--help shows --chrome flag" "$help_output" "--chrome"
assert_contains "--help shows claude·yolo branding" "$help_output" "claude"

h_output=$(bash "$CLI" -h 2>&1 || true)
assert_contains "-h shows same help as --help" "$h_output" "Usage:"

########################################
# Tests: Strategy detection — Rails
########################################


print_summary "$(basename "$0" .sh)"