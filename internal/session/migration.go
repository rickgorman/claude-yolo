package session

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/rickgorman/claude-yolo/internal/ui"
)

// MigrateYoloSessions migrates legacy yolo-sessions from various .*/yolo-sessions/
// directories to the new ~/.claude/projects/ structure.
func MigrateYoloSessions() error {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return err
	}

	// Find all .*/yolo-sessions/ directories
	pattern := filepath.Join(homeDir, ".*/yolo-sessions/")
	matches, err := filepath.Glob(pattern)
	if err != nil {
		return nil // Ignore glob errors
	}

	for _, baseDir := range matches {
		if err := migrateSessionsInDir(baseDir); err != nil {
			// Log but continue with other directories
			ui.Warn("Failed to migrate sessions from %s: %v", baseDir, err)
		}
	}

	return nil
}

func migrateSessionsInDir(baseDir string) error {
	entries, err := os.ReadDir(baseDir)
	if err != nil {
		return err
	}

	homeDir, _ := os.UserHomeDir()

	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}

		hash := entry.Name()
		sessionDir := filepath.Join(baseDir, hash)

		// Check if container is still running
		cmd := exec.Command("docker", "ps", "--filter", "name=claude-yolo-"+hash, "--format", "{{.Names}}")
		output, err := cmd.Output()
		if err == nil && len(strings.TrimSpace(string(output))) > 0 {
			// Container still running, skip migration
			continue
		}

		// Get worktree path
		worktreePath, err := getWorktreePath(sessionDir, hash)
		if err != nil || worktreePath == "" {
			// Can't determine worktree, check if directory has files
			hasFiles, _ := hasSessionFiles(sessionDir)
			if hasFiles {
				ui.Warn("Cannot migrate yolo session %s: worktree path unknown", hash)
			} else {
				_ = os.RemoveAll(sessionDir)
			}
			continue
		}

		// Migrate files
		encodedPath := strings.ReplaceAll(worktreePath, "/", "-")
		targetDir := filepath.Join(homeDir, ".claude", "projects", encodedPath)
		_ = os.MkdirAll(targetDir, 0755)

		moved := 0
		files, _ := os.ReadDir(sessionDir)
		for _, file := range files {
			if !file.IsDir() {
				src := filepath.Join(sessionDir, file.Name())
				dst := filepath.Join(targetDir, file.Name())
				if err := os.Rename(src, dst); err == nil {
					moved++
				}
			}
		}

		if moved > 0 {
			ui.Info("Migrated %d session file(s) for %s", moved, worktreePath)
		}

		// Cleanup
		_ = os.Remove(filepath.Join(sessionDir, ".worktree-path"))
		_ = os.Remove(sessionDir)
	}

	return nil
}

func getWorktreePath(sessionDir, hash string) (string, error) {
	// Try .worktree-path file first
	metaFile := filepath.Join(sessionDir, ".worktree-path")
	if data, err := os.ReadFile(metaFile); err == nil {
		return strings.TrimSpace(string(data)), nil
	}

	// Try docker inspect
	cmd := exec.Command("docker", "inspect",
		"--format", "{{range .Mounts}}{{if eq .Destination \"/workspace\"}}{{.Source}}{{end}}{{end}}",
		"claude-yolo-"+hash)
	output, err := cmd.Output()
	if err != nil {
		return "", err
	}

	return strings.TrimSpace(string(output)), nil
}

func hasSessionFiles(dir string) (bool, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return false, err
	}

	for _, entry := range entries {
		if !entry.IsDir() {
			return true, nil
		}
	}

	return false, nil
}
