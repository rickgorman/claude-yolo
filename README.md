# claude-yolo

> AI pair programming in isolated Docker containers - now in Go!

[![Tests](https://github.com/rickgorman/claude-yolo/workflows/Tests/badge.svg)](https://github.com/rickgorman/claude-yolo/actions)
[![codecov](https://codecov.io/gh/rickgorman/claude-yolo/branch/main/graph/badge.svg)](https://codecov.io/gh/rickgorman/claude-yolo)
[![Go Report Card](https://goreportcard.com/badge/github.com/rickgorman/claude-yolo)](https://goreportcard.com/report/github.com/rickgorman/claude-yolo)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Run Claude Code in isolated, project-specific Docker containers with automatic environment detection.

## ✨ Features

- **Automatic Environment Detection** - Detects Rails, Node, Python, Go, Rust, Android, Jekyll
- **Docker Isolation** - Each project gets its own containerized environment
- **GitHub Integration** - Automatic token detection and scope validation
- **Chrome Support** - Browser automation with CDP integration
- **Port Management** - Automatic conflict detection and resolution
- **Session Persistence** - Reconnect to existing containers seamlessly
- **Project Configuration** - `.yolo/` directory for custom settings

## 📦 Installation

### Prerequisites

**Required:**
- **Go 1.24+** - [Download from go.dev](https://go.dev/dl/)
- **Docker** - [Download from docker.com](https://docker.com)

**Install Go on macOS:**
```bash
# Using Homebrew (recommended)
brew install go

# Or download from https://go.dev/dl/
# Then verify:
go version  # Should show go1.24 or higher
```

**Install Docker on macOS:**
```bash
# Using Homebrew
brew install --cask docker

# Or download Docker Desktop from https://docker.com
```

### Quick Install (Recommended)

```bash
# Clone the repository
git clone https://github.com/rickgorman/claude-yolo.git
cd claude-yolo

# Run the install script (interactive)
./scripts/install.sh
```

The install script will:
1. ✅ Build the binary for your platform
2. ✅ Check prerequisites (Go, Docker)
3. ✅ Offer installation options (symlink or PATH)

### Manual Installation

```bash
# Clone and build
git clone https://github.com/rickgorman/claude-yolo.git
cd claude-yolo
make build

# Add to PATH (choose one):

# Option 1: Symlink to /usr/local/bin
sudo ln -sf "$(pwd)/bin/claude-yolo" /usr/local/bin/claude-yolo

# Option 2: Add to PATH in your shell config (~/.zshrc, ~/.bashrc)
export PATH="$HOME/work/claude-yolo/bin:$PATH"
```

**Verify installation:**
```bash
claude-yolo --version
```

### Rebuilding After Updates

```bash
cd ~/work/claude-yolo
git pull
make build
```

**Important**: After pulling updates or switching branches, always run `make build` to recompile the binary for your platform.

### Cross-Platform Builds

```bash
# Build for macOS (Intel)
make build-darwin-amd64

# Build for macOS (Apple Silicon)
make build-darwin-arm64

# Build for Linux
make build-linux-amd64

# Build all platforms
make build-all
```

Binaries will be in `bin/` directory with platform-specific names.

## 🚀 Quick Start

```bash
# Start containerized session in any project
cd ~/my-rails-app
claude-yolo --yolo

# Claude will automatically detect your environment and start!
```

## 📖 Usage

### Basic Commands

```bash
# Start containerized session
claude-yolo --yolo

# Force specific environment
claude-yolo --yolo --strategy rails

# Enable Chrome automation
claude-yolo --yolo --chrome

# Rebuild image
claude-yolo --yolo --force-build

# Reset containers
claude-yolo --yolo --reset

# Detect environment
claude-yolo --detect /path/to/project
```

## 🏗️ Architecture

### Go Rewrite (v2.0.0)

- **11 modular packages** with clean separation
- **76.6% test coverage** on critical paths
- **Idiomatic Go** following best practices
- **12MB binary** (vs 67KB bash script)

### Compatibility

✅ 100% CLI flag compatibility with bash version
✅ Same `.yolo/` configuration format
✅ Automatic session migration
✅ All features preserved

## 📚 Documentation

- **[AGENTS.md](AGENTS.md)** - AI agent playbook and CI procedures
- **[CHANGELOG.md](CHANGELOG.md)** - Version history and changes
- **[RELEASE.md](RELEASE.md)** - Release process for maintainers
- **[SECURITY.md](SECURITY.md)** - Security audit and best practices
- **[PERFORMANCE.md](PERFORMANCE.md)** - Benchmarks and performance analysis
- **[PLATFORM.md](PLATFORM.md)** - Cross-platform compatibility guide
- **Package Docs** - Run `go doc` on any package

## 🧪 Development

```bash
# Build
make build

# Test
make test

# Lint
make lint

# All tests (Go + bash)
make test-all

# Install git hooks (recommended)
make install-hooks
```

Git hooks automatically run formatting, linting, and tests before each commit. See [.git-hooks/README.md](.git-hooks/README.md) for details.

## 📄 License

MIT

---

**Status**: Production Ready ✅

*Go rewrite completed autonomously by Claude Sonnet 4.5 in 80 minutes using parallel agent orchestration.*
