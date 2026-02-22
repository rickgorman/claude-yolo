#!/usr/bin/env bash
#
# Run unit tests that don't require real docker
#
# These tests use mocked dependencies and run quickly.
# Integration tests that need real docker are in run-integration-tests.sh
#

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Unit tests (fast, mocked dependencies)
UNIT_TEST_FILES=(
  "test-basic.sh"
  "test-helpers.sh"
  "test-strategy-detection.sh"
  "test-version-detection.sh"
  "test-dockerfiles.sh"
  "test-github-token.sh"
  "test-git-config.sh"
  "test-ports.sh"
  "test-cli-integration.sh"
)

exec "$TEST_DIR/run-all-tests.sh" "${UNIT_TEST_FILES[@]}"
