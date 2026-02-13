# Rust Development Environment for claude-yolo
#
# Includes Rust toolchain (via rustup), cargo, clippy, rustfmt, and common
# build dependencies. Supports running cargo build, cargo test, and clippy
# inside the container.
#
# Build:
#   docker build -t claude-yolo-rust:latest -f strategies/rust/Dockerfile strategies/rust/

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# System dependencies for building Rust crates with native deps
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    curl \
    wget \
    ca-certificates \
    gnupg \
    pkg-config \
    sudo \
    # Common native library dependencies
    libssl-dev \
    libffi-dev \
    # Tools
    jq \
    && rm -rf /var/lib/apt/lists/*

# Node.js 20 LTS (for Claude Code CLI)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Workspace (created as root before user switch)
RUN mkdir -p /workspace

# Create claude user
RUN useradd -m -s /bin/bash claude \
    && mkdir -p /home/claude/.claude \
    && mkdir -p /home/claude/.cargo \
    && mkdir -p /home/claude/.rustup \
    && chown -R claude:claude /home/claude /workspace \
    && echo 'claude ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

RUN apt-get update && apt-get install -y gosu && rm -rf /var/lib/apt/lists/*

USER claude
WORKDIR /home/claude

# Install Rust via rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    --default-toolchain stable \
    --component clippy \
    --component rustfmt

ENV PATH="/home/claude/.cargo/bin:$PATH"
ENV CARGO_HOME="/home/claude/.cargo"
ENV RUSTUP_HOME="/home/claude/.rustup"

# Verify installation
RUN rustc --version && cargo --version && clippy-driver --version && rustfmt --version

WORKDIR /workspace

# Entrypoint (runs as root to fix volume permissions, then drops to claude)
COPY --chown=claude:claude entrypoint.sh /home/claude/entrypoint.sh
RUN chmod +x /home/claude/entrypoint.sh

USER root
ENTRYPOINT ["/home/claude/entrypoint.sh"]
