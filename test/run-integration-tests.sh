#!/usr/bin/env bash
#
# Run integration tests that require real docker
#
# These tests need actual docker daemon and are slower than unit tests.
# They test env injection, volume mounting, and docker argument passing.
#

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Integration tests (need real docker)
INTEGRATION_TEST_FILES=(
  "test-yolo-config.sh"
  "test-flags.sh"
  "test-mounting.sh"
)

exec "$TEST_DIR/run-all-tests.sh" "${INTEGRATION_TEST_FILES[@]}"
