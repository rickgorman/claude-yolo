#!/usr/bin/env bash
#
# Claude YOLO CLI Test Suite
#
# This is a wrapper that runs all modular test files.
# Individual test files are in test-*.sh
#
# Usage:
#   ./test/test-cli.sh              # Run all tests
#   ./test/test-cli.sh test-basic.sh test-ports.sh  # Run specific tests
#

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$TEST_DIR/run-all-tests.sh" "$@"
