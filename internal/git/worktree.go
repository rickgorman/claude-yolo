// Package git provides Git repository operations.
package git

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// GetWorktreePath returns the root path of the current git worktree.
// Falls back to current working directory if not in a git repository.
func GetWorktreePath() (string, error) {
	cmd := exec.Command("git", "rev-parse", "--show-toplevel")
	output, err := cmd.Output()
	if err != nil {
		// Not in a git repo, use current directory
		return os.Getwd()
	}

	path := strings.TrimSpace(string(output))
	return path, nil
}

// IsGitRepository checks if the current directory is inside a git repository.
func IsGitRepository() bool {
	cmd := exec.Command("git", "rev-parse", "--git-dir")
	err := cmd.Run()
	return err == nil
}

// GetGitDir returns the .git directory path for the current repository.
// This handles both regular repos and worktrees.
func GetGitDir(worktreePath string) (string, error) {
	gitFile := filepath.Join(worktreePath, ".git")

	// Check if .git is a file (worktree) or directory (regular repo)
	info, err := os.Stat(gitFile)
	if err != nil {
		return "", err
	}

	if info.IsDir() {
		// Regular repository
		return gitFile, nil
	}

	// Worktree - read gitdir from .git file
	data, err := os.ReadFile(gitFile)
	if err != nil {
		return "", err
	}

	// Format: "gitdir: /path/to/main/repo/.git/worktrees/branch-name"
	content := strings.TrimSpace(string(data))
	if strings.HasPrefix(content, "gitdir: ") {
		gitdir := strings.TrimPrefix(content, "gitdir: ")
		return gitdir, nil
	}

	return gitFile, nil
}

// GetParentGitDir returns the parent .git directory for a worktree.
// This is needed when mounting git directories in Docker containers.
func GetParentGitDir(worktreePath string) (string, error) {
	gitdir, err := GetGitDir(worktreePath)
	if err != nil {
		return "", err
	}

	// Navigate up from .git/worktrees/branch-name to .git
	parent := filepath.Dir(filepath.Dir(gitdir))
	return parent, nil
}
