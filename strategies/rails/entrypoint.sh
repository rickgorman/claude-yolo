#!/usr/bin/env bash
# Rails entrypoint for claude-yolo container
# Installs the correct Ruby version and runs bundle install

set -euo pipefail

log() {
  echo "[entrypoint:rails] $*" >&2
}

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

exec "$@"
