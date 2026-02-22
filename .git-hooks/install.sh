#!/bin/bash
# Install git hooks for claude-yolo development

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"

echo "Installing git hooks..."

# Ensure hooks directory exists
mkdir -p "$HOOKS_DIR"

# Install pre-commit hook
if [ -f "$HOOKS_DIR/pre-commit" ] && [ ! -L "$HOOKS_DIR/pre-commit" ]; then
    echo "Warning: .git/hooks/pre-commit already exists and is not a symlink"
    echo "Backing up to .git/hooks/pre-commit.backup"
    mv "$HOOKS_DIR/pre-commit" "$HOOKS_DIR/pre-commit.backup"
fi

ln -sf "../../.git-hooks/pre-commit" "$HOOKS_DIR/pre-commit"
chmod +x "$HOOKS_DIR/pre-commit"

echo "✓ Installed pre-commit hook"

# Verify installation
if [ -L "$HOOKS_DIR/pre-commit" ]; then
    echo "✓ Git hooks installed successfully"
    echo ""
    echo "Hooks active:"
    ls -lh "$HOOKS_DIR/pre-commit"
    echo ""
    echo "To uninstall: rm .git/hooks/pre-commit"
    echo "To bypass: git commit --no-verify"
else
    echo "✗ Installation failed"
    exit 1
fi
