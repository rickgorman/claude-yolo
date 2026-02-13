#!/usr/bin/env bash
# Rust entrypoint for claude-yolo container
# Runs as root to fix volume permissions, then drops to claude user

set -euo pipefail

log() {
  echo "[entrypoint:rust] $*" >&2
}

# Fix ownership on Docker volumes (created as root by default)
if [[ "$(id -u)" == "0" ]]; then
  chown -R claude:claude /home/claude/.cargo /home/claude/.rustup /home/claude/.claude 2>/dev/null || true
  exec gosu claude "$0" "$@"
fi

export PATH="$HOME/.cargo/bin:$PATH"

log "Rust: $(rustc --version)"
log "Cargo: $(cargo --version)"

# Install specific toolchain if rust-toolchain.toml or rust-toolchain exists
if [[ -f /workspace/rust-toolchain.toml ]] || [[ -f /workspace/rust-toolchain ]]; then
  log "Project specifies a rust-toolchain, syncing..."
  rustup show active-toolchain 2>/dev/null || rustup default stable
fi

# Pre-fetch dependencies if Cargo.toml exists (speeds up first build)
if [[ -f /workspace/Cargo.toml ]]; then
  if [[ ! -d /workspace/target ]]; then
    log "Fetching dependencies..."
    cargo fetch 2>/dev/null || true
  fi
fi

exec "$@"
