# syntax=docker/dockerfile:1
# Node.js/TypeScript Development Environment for claude-yolo
#
# Includes Node.js (via nvm), npm, yarn, pnpm, and common build dependencies.
# Supports TypeScript, Next.js, Vite, and other Node.js frameworks.
#
# Build:
#   docker build -t claude-yolo-node:latest -f strategies/node/Dockerfile strategies/node/

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# System dependencies
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y \
    build-essential \
    git \
    curl \
    wget \
    ca-certificates \
    gnupg \
    sudo \
    # Common native addon dependencies
    python3 \
    libssl-dev \
    # Tools
    jq

# Node.js 20 LTS (for Claude Code CLI — installed at system level)
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
    && mkdir -p /home/claude/.nvm \
    && chown -R claude:claude /home/claude /workspace \
    && echo 'claude ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y gosu

USER claude
WORKDIR /home/claude

# Install nvm
ENV NVM_DIR="/home/claude/.nvm"
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash

RUN echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc \
    && echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.bashrc

WORKDIR /workspace

# Entrypoint (runs as root to fix volume permissions, then drops to claude)
COPY --chown=claude:claude entrypoint.sh /home/claude/entrypoint.sh
RUN chmod +x /home/claude/entrypoint.sh

USER root
ENTRYPOINT ["/home/claude/entrypoint.sh"]
