# syntax=docker/dockerfile:1
# Python Development Environment for claude-yolo
#
# Includes Python (via pyenv), pip, and common build dependencies.
# Supports virtualenvs, poetry, pipenv, and uv.
#
# Build:
#   docker build -t claude-yolo-python:latest -f strategies/python/Dockerfile strategies/python/

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# System dependencies for building Python and native extensions
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
    # Python build dependencies
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    libbz2-dev \
    libsqlite3-dev \
    libncurses5-dev \
    libffi-dev \
    liblzma-dev \
    libgdbm-dev \
    # Common native library dependencies
    libpq-dev \
    # Tools
    jq

# Node.js 20 LTS (for Claude Code CLI)
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
    && mkdir -p /home/claude/.pyenv \
    && chown -R claude:claude /home/claude /workspace \
    && echo 'claude ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y gosu

USER claude
WORKDIR /home/claude

# Install pyenv
RUN git clone https://github.com/pyenv/pyenv.git ~/.pyenv

RUN echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc \
    && echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc \
    && echo 'eval "$(pyenv init -)"' >> ~/.bashrc

ENV PYENV_ROOT="/home/claude/.pyenv"
ENV PATH="/home/claude/.pyenv/bin:/home/claude/.pyenv/shims:$PATH"

WORKDIR /workspace

# Entrypoint (runs as root to fix volume permissions, then drops to claude)
COPY --chown=claude:claude entrypoint.sh /home/claude/entrypoint.sh
RUN chmod +x /home/claude/entrypoint.sh

USER root
ENTRYPOINT ["/home/claude/entrypoint.sh"]
