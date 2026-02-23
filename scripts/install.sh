#!/usr/bin/env bash
#
# Installation script for claude-yolo
# Builds the binary for your platform and optionally installs it to PATH
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect platform
OS="$(uname -s)"
ARCH="$(uname -m)"

echo "🔧 Claude-YOLO Installation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check prerequisites
if ! command -v go &> /dev/null; then
    echo -e "${RED}✗ Go is not installed${NC}"
    echo "  Please install Go 1.24+ from https://go.dev/dl/"
    exit 1
fi

GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
echo "✓ Found Go $GO_VERSION"

if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}⚠ Docker is not installed${NC}"
    echo "  Docker is required to run claude-yolo"
    echo "  Install from https://docker.com"
fi

echo ""
echo "📦 Building for $OS/$ARCH..."
make build

if [[ -f "bin/claude-yolo" ]]; then
    echo -e "${GREEN}✓ Build successful!${NC}"
    echo ""

    # Ask about installation
    echo "🎯 Installation Options:"
    echo ""
    echo "1) Symlink to /usr/local/bin (requires sudo)"
    echo "2) Add to PATH in shell config"
    echo "3) Skip (just build)"
    echo ""
    read -p "Choose option (1-3): " choice

    case $choice in
        1)
            echo ""
            echo "Installing to /usr/local/bin..."
            sudo ln -sf "$(pwd)/bin/claude-yolo" /usr/local/bin/claude-yolo
            echo -e "${GREEN}✓ Installed to /usr/local/bin/claude-yolo${NC}"
            ;;
        2)
            SHELL_CONFIG=""
            if [[ -f "$HOME/.zshrc" ]]; then
                SHELL_CONFIG="$HOME/.zshrc"
            elif [[ -f "$HOME/.bashrc" ]]; then
                SHELL_CONFIG="$HOME/.bashrc"
            fi

            if [[ -n "$SHELL_CONFIG" ]]; then
                echo ""
                echo "Add this to your $SHELL_CONFIG:"
                echo ""
                echo -e "${YELLOW}export PATH=\"$(pwd)/bin:\$PATH\"${NC}"
                echo ""
            else
                echo "Add $(pwd)/bin to your PATH"
            fi
            ;;
        3)
            echo ""
            echo "Binary available at: $(pwd)/bin/claude-yolo"
            ;;
        *)
            echo "Invalid option"
            exit 1
            ;;
    esac

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}✨ Installation complete!${NC}"
    echo ""
    echo "Test it:"
    echo "  claude-yolo --version"
    echo ""
    echo "Get started:"
    echo "  cd ~/your-project"
    echo "  claude-yolo --yolo"
    echo ""
else
    echo -e "${RED}✗ Build failed${NC}"
    exit 1
fi
