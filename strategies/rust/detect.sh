#!/usr/bin/env bash
# Detection heuristics for Rust projects
#
# Outputs:
#   CONFIDENCE:<0-100>
#   EVIDENCE:<comma-separated list of what was found>

set -euo pipefail

PROJECT_DIR="${1:-.}"
CONFIDENCE=0
EVIDENCE=()

# Cargo.toml (strong signal)
if [[ -f "$PROJECT_DIR/Cargo.toml" ]]; then
  CONFIDENCE=$((CONFIDENCE + 40))
  EVIDENCE+=("Cargo.toml")
fi

# Cargo.lock
if [[ -f "$PROJECT_DIR/Cargo.lock" ]]; then
  CONFIDENCE=$((CONFIDENCE + 10))
  EVIDENCE+=("Cargo.lock")
fi

# src/main.rs or src/lib.rs
if [[ -f "$PROJECT_DIR/src/main.rs" ]]; then
  CONFIDENCE=$((CONFIDENCE + 20))
  EVIDENCE+=("src/main.rs")
elif [[ -f "$PROJECT_DIR/src/lib.rs" ]]; then
  CONFIDENCE=$((CONFIDENCE + 20))
  EVIDENCE+=("src/lib.rs")
fi

# rust-toolchain.toml or rust-toolchain
if [[ -f "$PROJECT_DIR/rust-toolchain.toml" ]] || [[ -f "$PROJECT_DIR/rust-toolchain" ]]; then
  CONFIDENCE=$((CONFIDENCE + 15))
  EVIDENCE+=("rust-toolchain")
fi

# .cargo/ directory
if [[ -d "$PROJECT_DIR/.cargo" ]]; then
  CONFIDENCE=$((CONFIDENCE + 5))
  EVIDENCE+=(".cargo/")
fi

# build.rs
if [[ -f "$PROJECT_DIR/build.rs" ]]; then
  CONFIDENCE=$((CONFIDENCE + 10))
  EVIDENCE+=("build.rs")
fi

# Cap at 100
[[ $CONFIDENCE -gt 100 ]] && CONFIDENCE=100

echo "CONFIDENCE:${CONFIDENCE}"
echo "EVIDENCE:$(IFS=', '; echo "${EVIDENCE[*]}")"
