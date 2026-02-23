# syntax=docker/dockerfile:1
# Rails Development Environment for claude-yolo
#
# Based on Debian with Ruby (via rbenv), Node.js, and PostgreSQL client.
#
# Build:
#   docker build -t claude-yolo-rails:latest -f strategies/rails/Dockerfile .

# Build entrypoint binary
FROM golang:1.24-alpine AS entrypoint-builder
WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY cmd/entrypoint ./cmd/entrypoint
COPY internal/entrypoint ./internal/entrypoint
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /entrypoint ./cmd/entrypoint

# Main image
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# System dependencies
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y \
    build-essential \
    autoconf \
    patch \
    rustc \
    git \
    curl \
    wget \
    ca-certificates \
    gnupg \
    sudo \
    # Ruby build dependencies
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    libyaml-dev \
    libffi-dev \
    libgdbm-dev \
    libgmp-dev \
    libncurses5-dev \
    # PostgreSQL client
    libpq-dev \
    postgresql-client \
    # Tools
    jq \
    unzip \
    socat

# Node.js 22 LTS
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs

# GitHub CLI
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh

# Yarn + Claude Code CLI (global installs need root)
RUN --mount=type=cache,target=/root/.npm \
    npm install -g yarn @anthropic-ai/claude-code

# Workspace (created as root before user switch)
RUN mkdir -p /workspace

# Create claude user
RUN useradd -m -s /bin/bash claude \
    && mkdir -p /home/claude/.claude \
    && mkdir -p /home/claude/.gems \
    && mkdir -p /home/claude/.rbenv \
    && chown -R claude:claude /home/claude /workspace \
    && echo 'claude ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y gosu

USER claude
WORKDIR /home/claude

# Install rbenv + ruby-build
RUN git clone https://github.com/rbenv/rbenv.git ~/.rbenv \
    && cd ~/.rbenv && src/configure && make -C src \
    && git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build

RUN echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc \
    && echo 'eval "$(rbenv init -)"' >> ~/.bashrc

ENV PATH="/home/claude/.rbenv/bin:/home/claude/.rbenv/shims:/home/claude/.gems/bin:$PATH"
ENV GEM_HOME="/home/claude/.gems"
ENV BUNDLE_PATH="/home/claude/.gems"
ENV BUNDLE_BIN="/home/claude/.gems/bin"

WORKDIR /workspace

# Switch to root for entrypoint setup
USER root

# Entrypoint (runs as root to fix volume permissions, then drops to claude)
COPY --from=entrypoint-builder /entrypoint /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint

ENTRYPOINT ["/usr/local/bin/entrypoint", "rails"]
CMD ["claude"]
