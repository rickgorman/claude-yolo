# Android Development Environment for claude-yolo
#
# IMPORTANT: Requires x86_64 — Android SDK build tools (aapt2) are only
# available for this architecture. On Apple Silicon, this runs under Rosetta.
#
# Build:
#   docker build --platform linux/amd64 \
#       -t claude-yolo-android:latest \
#       -f strategies/android/Dockerfile strategies/android/

FROM --platform=linux/amd64 ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# System dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    curl \
    wget \
    ca-certificates \
    gnupg \
    unzip \
    jq \
    sudo \
    # Java 17 for Android SDK
    openjdk-17-jdk-headless \
    && rm -rf /var/lib/apt/lists/*

# Node.js 20 LTS (for Claude Code CLI)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Workspace (created as root before user switch)
RUN mkdir -p /workspace

# Create claude user
RUN useradd -m -s /bin/bash claude \
    && mkdir -p /home/claude/.claude \
    && mkdir -p /home/claude/android-sdk \
    && mkdir -p /home/claude/.gradle \
    && chown -R claude:claude /home/claude /workspace \
    && echo 'claude ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

USER claude
WORKDIR /home/claude

# Java environment
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH="$JAVA_HOME/bin:$PATH"

# Download and install Android SDK command-line tools (with SHA256 verification)
ENV ANDROID_SDK_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
ENV ANDROID_SDK_TOOLS_SHA256="2d2d50857e4eb553af5a6dc3ad507a17adf43d115264b1afc116f95c92e5e258"
RUN curl -L "$ANDROID_SDK_TOOLS_URL" -o /tmp/cmdline-tools.zip \
    && echo "$ANDROID_SDK_TOOLS_SHA256  /tmp/cmdline-tools.zip" | sha256sum -c - \
    && unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools-extract \
    && mkdir -p /home/claude/android-sdk/cmdline-tools/latest \
    && mv /tmp/cmdline-tools-extract/cmdline-tools/* /home/claude/android-sdk/cmdline-tools/latest/ \
    && rm -rf /tmp/cmdline-tools.zip /tmp/cmdline-tools-extract

# Android environment
ENV ANDROID_HOME=/home/claude/android-sdk
ENV PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/34.0.0:$PATH"

# Accept licenses and install SDK components
RUN yes | sdkmanager --licenses > /dev/null 2>&1 || true \
    && sdkmanager "platforms;android-34" "build-tools;34.0.0" "platform-tools"

# Verify Android tools
RUN aapt2 version && adb version

WORKDIR /workspace

# Entrypoint
COPY --chown=claude:claude entrypoint.sh /home/claude/entrypoint.sh
RUN chmod +x /home/claude/entrypoint.sh

ENTRYPOINT ["/home/claude/entrypoint.sh"]
