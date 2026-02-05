# Dockerfile for claude-yolo
# Based on Debian with Claude Code, Ruby, Node.js, and PostgreSQL client

FROM debian:bookworm-slim

# Avoid prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    # Build essentials
    build-essential \
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
    libncurses5-dev \
    # PostgreSQL client
    libpq-dev \
    postgresql-client \
    # Node.js will be installed separately
    # Other useful tools
    jq \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js (LTS)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Yarn
RUN npm install -g yarn

# Create claude user
RUN useradd -m -s /bin/bash claude \
    && mkdir -p /home/claude/.claude \
    && mkdir -p /home/claude/.gems \
    && mkdir -p /home/claude/.rbenv \
    && chown -R claude:claude /home/claude

# Switch to claude user
USER claude
WORKDIR /home/claude

# Install rbenv
RUN git clone https://github.com/rbenv/rbenv.git ~/.rbenv \
    && cd ~/.rbenv && src/configure && make -C src \
    && git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build

# Set up rbenv in bashrc
RUN echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc \
    && echo 'eval "$(rbenv init -)"' >> ~/.bashrc

# Set environment variables
ENV PATH="/home/claude/.rbenv/bin:/home/claude/.rbenv/shims:/home/claude/.gems/bin:$PATH"
ENV GEM_HOME="/home/claude/.gems"
ENV BUNDLE_PATH="/home/claude/.gems"
ENV BUNDLE_BIN="/home/claude/.gems/bin"

# Install Claude Code CLI via npm
RUN npm install -g @anthropic-ai/claude-code

# Create workspace directory
RUN mkdir -p /workspace
WORKDIR /workspace

# Copy entrypoint script
COPY --chown=claude:claude scripts/entrypoint.sh /home/claude/entrypoint.sh
RUN chmod +x /home/claude/entrypoint.sh

ENTRYPOINT ["/home/claude/entrypoint.sh"]
