# syntax=docker/dockerfile:1
# Generic Development Environment for claude-yolo
#
# Minimal container with GitHub CLI and Claude Code — no language runtime.
# Useful for planning, research, code review, or any task that doesn't
# need a specific language toolchain.
#
# Build:
#   docker build -t claude-yolo-generic:latest -f .Dockerfile strategies/generic/

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
    git \
    curl \
    wget \
    ca-certificates \
    gnupg \
    sudo \
    jq

# Node.js 20 LTS (required for Claude Code CLI)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# GitHub CLI
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh

# Claude Code CLI
RUN --mount=type=cache,target=/root/.npm \
    npm install -g @anthropic-ai/claude-code

# Workspace (created as root before user switch)
RUN mkdir -p /workspace

# Create claude user
RUN useradd -m -s /bin/bash claude \
    && mkdir -p /home/claude/.claude \
    && chown -R claude:claude /home/claude /workspace \
    && echo 'claude ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y gosu

WORKDIR /workspace

# Entrypoint (runs as root to fix volume permissions, then drops to claude)
COPY --from=entrypoint-builder /entrypoint /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint

USER root
ENTRYPOINT ["/usr/local/bin/entrypoint", "generic"]
CMD ["claude"]
