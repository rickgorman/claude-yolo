# Rails Development Environment for claude-yolo
#
# Based on Debian with Ruby (via rbenv), Node.js, and PostgreSQL client.
#
# Build:
#   docker build -t claude-yolo-rails:latest -f strategies/rails/Dockerfile strategies/rails/

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# System dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    autoconf \
    patch \
    rustc \
    git \
    curl \
    wget \
    ca-certificates \
    gnupg \
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
    && rm -rf /var/lib/apt/lists/*

# Node.js 20 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Yarn + Claude Code CLI (global installs need root)
RUN npm install -g yarn @anthropic-ai/claude-code

# Workspace (created as root before user switch)
RUN mkdir -p /workspace

# Create claude user
RUN useradd -m -s /bin/bash claude \
    && mkdir -p /home/claude/.claude \
    && mkdir -p /home/claude/.gems \
    && mkdir -p /home/claude/.rbenv \
    && chown -R claude:claude /home/claude /workspace

RUN apt-get update && apt-get install -y gosu && rm -rf /var/lib/apt/lists/*

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

# Entrypoint (runs as root to fix volume permissions, then drops to claude)
COPY --chown=claude:claude entrypoint.sh /home/claude/entrypoint.sh
RUN chmod +x /home/claude/entrypoint.sh

USER root
ENTRYPOINT ["/home/claude/entrypoint.sh"]
