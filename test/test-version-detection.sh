#!/usr/bin/env bash
set -euo pipefail

# Source common test framework
source "$(dirname "$0")/lib/common.sh"

section "Ruby version detection"

ver=$(detect_ruby_version "$RAILS_DIR")
assert_eq "Detects from .ruby-version" "3.3.0" "$ver"

TOOL_VER_DIR="$TMPDIR_BASE/tool-versions-project"
mkdir -p "$TOOL_VER_DIR"
echo "ruby 3.2.2" > "$TOOL_VER_DIR/.tool-versions"
ver=$(detect_ruby_version "$TOOL_VER_DIR")
assert_eq "Detects from .tool-versions" "3.2.2" "$ver"

GEMFILE_VER_DIR="$TMPDIR_BASE/gemfile-ruby-project"
mkdir -p "$GEMFILE_VER_DIR"
cat > "$GEMFILE_VER_DIR/Gemfile" << 'EOF'
source 'https://rubygems.org'
ruby '3.1.4'
gem 'rails'
EOF
ver=$(detect_ruby_version "$GEMFILE_VER_DIR")
assert_eq "Detects from Gemfile ruby declaration" "3.1.4" "$ver"

NOVER_DIR="$TMPDIR_BASE/no-ruby-version"
mkdir -p "$NOVER_DIR"
ver=$(detect_ruby_version "$NOVER_DIR")
assert_eq "Falls back to 4.0.1 when no version found" "4.0.1" "$ver"

# Priority: .ruby-version > .tool-versions > Gemfile
MULTI_DIR="$TMPDIR_BASE/multi-version"
mkdir -p "$MULTI_DIR"
echo "3.3.0" > "$MULTI_DIR/.ruby-version"
echo "ruby 3.2.0" > "$MULTI_DIR/.tool-versions"
cat > "$MULTI_DIR/Gemfile" << 'EOF'
ruby '3.1.0'
EOF
ver=$(detect_ruby_version "$MULTI_DIR")
assert_eq ".ruby-version takes priority over others" "3.3.0" "$ver"

########################################
# Tests: Python version detection
########################################


section "Python version detection"

ver=$(detect_python_version "$PYTHON_DIR")
assert_eq "Detects Python from .python-version" "3.12.0" "$ver"

PYTHON_TOOL_VER_DIR="$TMPDIR_BASE/python-tool-versions"
mkdir -p "$PYTHON_TOOL_VER_DIR"
echo "python 3.11.5" > "$PYTHON_TOOL_VER_DIR/.tool-versions"
ver=$(detect_python_version "$PYTHON_TOOL_VER_DIR")
assert_eq "Detects Python from .tool-versions" "3.11.5" "$ver"

PYTHON_NOVER_DIR="$TMPDIR_BASE/no-python-version"
mkdir -p "$PYTHON_NOVER_DIR"
ver=$(detect_python_version "$PYTHON_NOVER_DIR")
assert_eq "Falls back to 3.12 when no Python version found" "3.12" "$ver"

# Priority: .python-version > .tool-versions
PYTHON_MULTI_DIR="$TMPDIR_BASE/python-multi-version"
mkdir -p "$PYTHON_MULTI_DIR"
echo "3.12.0" > "$PYTHON_MULTI_DIR/.python-version"
echo "python 3.11.0" > "$PYTHON_MULTI_DIR/.tool-versions"
ver=$(detect_python_version "$PYTHON_MULTI_DIR")
assert_eq ".python-version takes priority for Python" "3.12.0" "$ver"

########################################
# Tests: Node.js version detection
########################################


section "Node.js version detection"

ver=$(detect_node_version "$NODE_DIR")
assert_eq "Detects Node from .nvmrc" "20" "$ver"

NODE_VER_DIR="$TMPDIR_BASE/node-version-file"
mkdir -p "$NODE_VER_DIR"
echo "18.19.0" > "$NODE_VER_DIR/.node-version"
ver=$(detect_node_version "$NODE_VER_DIR")
assert_eq "Detects Node from .node-version" "18.19.0" "$ver"

NODE_TOOL_VER_DIR="$TMPDIR_BASE/node-tool-versions"
mkdir -p "$NODE_TOOL_VER_DIR"
echo "nodejs 20.11.0" > "$NODE_TOOL_VER_DIR/.tool-versions"
ver=$(detect_node_version "$NODE_TOOL_VER_DIR")
assert_eq "Detects Node from .tool-versions" "20.11.0" "$ver"

NODE_NOVER_DIR="$TMPDIR_BASE/no-node-version"
mkdir -p "$NODE_NOVER_DIR"
ver=$(detect_node_version "$NODE_NOVER_DIR")
assert_eq "Falls back to 20 when no Node version found" "20" "$ver"

# Priority: .nvmrc > .node-version > .tool-versions
NODE_MULTI_DIR="$TMPDIR_BASE/node-multi-version"
mkdir -p "$NODE_MULTI_DIR"
echo "20" > "$NODE_MULTI_DIR/.nvmrc"
echo "18.0.0" > "$NODE_MULTI_DIR/.node-version"
echo "nodejs 16.0.0" > "$NODE_MULTI_DIR/.tool-versions"
ver=$(detect_node_version "$NODE_MULTI_DIR")
assert_eq ".nvmrc takes priority for Node" "20" "$ver"

########################################
# Tests: list_strategies
########################################


print_summary "$(basename "$0" .sh)"