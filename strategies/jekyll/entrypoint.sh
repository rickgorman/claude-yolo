#!/usr/bin/env bash
# Jekyll entrypoint for claude-yolo container
# Runs as root to fix volume permissions, then drops to claude user

set -euo pipefail

log() {
  echo "[entrypoint:jekyll] $*" >&2
}

# Fix ownership on Docker volumes (created as root by default)
if [[ "$(id -u)" == "0" ]]; then
  chown -R claude:claude /home/claude/.rbenv/versions /home/claude/.gems /home/claude/.claude 2>/dev/null || true

  # Create minimal .gitconfig from environment variables
  if [[ -n "${GIT_USER_NAME:-}" || -n "${GIT_USER_EMAIL:-}" ]]; then
    cat > /home/claude/.gitconfig << EOF
[user]
	name = ${GIT_USER_NAME}
	email = ${GIT_USER_EMAIL}
EOF
    chown claude:claude /home/claude/.gitconfig
  fi
  exec gosu claude "$0" "$@"
fi

# Initialize rbenv
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
eval "$(rbenv init -)"

# Install Ruby if RUBY_VERSION is set and not already installed
if [[ -n "${RUBY_VERSION:-}" ]]; then
  if ! rbenv versions --bare | grep -q "^${RUBY_VERSION}$"; then
    log "Installing Ruby ${RUBY_VERSION} (this may take a few minutes on first run)..."
    rbenv install "$RUBY_VERSION"
  fi
  rbenv global "$RUBY_VERSION"
  log "Using Ruby ${RUBY_VERSION}"
fi

# Install bundler if not present
if ! command -v bundle &>/dev/null; then
  log "Installing bundler..."
  gem install bundler --no-document
fi

# Run bundle install if Gemfile exists and gems aren't installed
if [[ -f /workspace/Gemfile ]]; then
  if ! bundle check &>/dev/null; then
    log "Running bundle install..."
    bundle install --jobs=4 --retry=3
  fi
fi

# Propagate host terminal dimensions to the container PTY
if [[ -t 0 ]] && [[ -n "${COLUMNS:-}" ]] && [[ -n "${LINES:-}" ]]; then
  stty columns "$COLUMNS" rows "$LINES" 2>/dev/null || true
fi

exec "$@"
