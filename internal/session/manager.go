// Package session manages Claude session directories and migration.
package session

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// GetProjectSessionDir returns the session directory for a worktree.
// Sessions are stored in ~/.claude/projects/<encoded-path>/ to match
// the native Claude project directory structure.
func GetProjectSessionDir(worktreePath string) (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}

	// Encode path by replacing / with -
	encodedPath := strings.ReplaceAll(worktreePath, "/", "-")

	sessionDir := filepath.Join(homeDir, ".claude", "projects", encodedPath)

	// Ensure directory exists
	if err := os.MkdirAll(sessionDir, 0755); err != nil {
		return "", fmt.Errorf("failed to create session directory: %w", err)
	}

	return sessionDir, nil
}

// EnsureClaudeDir ensures ~/.claude directory exists for bind mounting.
func EnsureClaudeDir() error {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return err
	}

	claudeDir := filepath.Join(homeDir, ".claude")
	return os.MkdirAll(claudeDir, 0755)
}
