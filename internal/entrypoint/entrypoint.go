package entrypoint

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
)

// Run executes the appropriate entrypoint logic for the given strategy.
func Run(strategy string, args []string) error {
	// Log helper
	log := func(msg string) {
		fmt.Fprintf(os.Stderr, "[entrypoint:%s] %s\n", strategy, msg)
	}

	// Fix volume permissions if running as root
	if os.Getuid() == 0 {
		if err := fixVolumePermissions(strategy, log); err != nil {
			return fmt.Errorf("failed to fix permissions: %w", err)
		}

		// Create .gitconfig from environment variables
		if err := createGitConfig(log); err != nil {
			return fmt.Errorf("failed to create .gitconfig: %w", err)
		}

		// Drop to claude user using gosu
		return execGosu(strategy, args)
	}

	// Running as claude user - perform strategy-specific setup
	switch strategy {
	case "rails":
		return runRailsEntrypoint(args, log)
	case "node":
		return runNodeEntrypoint(args, log)
	case "python":
		return runPythonEntrypoint(args, log)
	case "go":
		return runGoEntrypoint(args, log)
	case "rust":
		return runRustEntrypoint(args, log)
	case "android":
		return runAndroidEntrypoint(args, log)
	case "jekyll":
		return runJekyllEntrypoint(args, log)
	case "generic":
		return runGenericEntrypoint(args, log)
	default:
		return fmt.Errorf("unknown strategy: %s", strategy)
	}
}

// fixVolumePermissions fixes ownership on Docker volumes
func fixVolumePermissions(strategy string, _ func(string)) error {
	claudeUID := 1000 // claude user UID
	claudeGID := 1000 // claude group GID

	// Common directories
	dirs := []string{
		"/home/claude/.claude",
	}

	// Strategy-specific directories
	switch strategy {
	case "rails", "jekyll":
		dirs = append(dirs, "/home/claude/.rbenv/versions", "/home/claude/.gems", "/workspace/node_modules")
	case "node":
		dirs = append(dirs, "/home/claude/.nvm", "/workspace/node_modules")
	case "python":
		dirs = append(dirs, "/home/claude/.pyenv/versions")
	case "go":
		dirs = append(dirs, "/home/claude/go")
	case "rust":
		dirs = append(dirs, "/home/claude/.cargo", "/home/claude/.rustup", "/workspace/target")
	case "android":
		dirs = append(dirs, "/home/claude/.gradle")
	}

	for _, dir := range dirs {
		if _, err := os.Stat(dir); err == nil {
			if err := os.Chown(dir, claudeUID, claudeGID); err != nil {
				// Ignore errors - some volumes may not exist yet
				continue
			}
			// Recursively chown if it's a volume mount point
			_ = filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
				if err != nil {
					return nil // ignore errors
				}
				_ = os.Chown(path, claudeUID, claudeGID)
				return nil
			})
		}
	}

	return nil
}

// createGitConfig creates .gitconfig from environment variables
func createGitConfig(_ func(string)) error {
	gitName := os.Getenv("GIT_USER_NAME")
	gitEmail := os.Getenv("GIT_USER_EMAIL")

	if gitName == "" && gitEmail == "" {
		return nil // nothing to create
	}

	gitconfig := filepath.Join("/home/claude", ".gitconfig")

	content := "[user]\n"
	if gitName != "" {
		content += fmt.Sprintf("\tname = %s\n", gitName)
	}
	if gitEmail != "" {
		content += fmt.Sprintf("\temail = %s\n", gitEmail)
	}

	if err := os.WriteFile(gitconfig, []byte(content), 0644); err != nil {
		return err
	}

	if err := os.Chown(gitconfig, 1000, 1000); err != nil {
		return err
	}

	return nil
}

// execGosu drops to claude user using gosu and re-executes the entrypoint
func execGosu(strategy string, args []string) error {
	// Re-exec this binary as claude user
	exe, err := os.Executable()
	if err != nil {
		return err
	}

	gosuArgs := []string{"claude", exe, strategy}
	gosuArgs = append(gosuArgs, args...)

	return syscall.Exec("/usr/local/bin/gosu", gosuArgs, os.Environ())
}

// setTerminalDimensions propagates host terminal dimensions to container PTY
func setTerminalDimensions() {
	if !isTerminal(0) {
		return
	}

	columns := os.Getenv("COLUMNS")
	lines := os.Getenv("LINES")

	if columns != "" && lines != "" {
		cmd := exec.Command("stty", "columns", columns, "rows", lines)
		cmd.Stdin = os.Stdin
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		_ = cmd.Run() // ignore errors
	}
}

// isTerminal checks if fd is a terminal (Unix-like systems only)
func isTerminal(_ int) bool {
	// Simple check: if stdin is a file, it's probably a terminal
	fileInfo, err := os.Stdin.Stat()
	if err != nil {
		return false
	}
	return (fileInfo.Mode() & os.ModeCharDevice) != 0
}

// execCommand replaces current process with the given command
func execCommand(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("no command to execute")
	}

	// Set terminal dimensions before exec
	setTerminalDimensions()

	// Find command in PATH
	path, err := exec.LookPath(args[0])
	if err != nil {
		return fmt.Errorf("command not found: %s", args[0])
	}

	// Exec replaces current process
	return syscall.Exec(path, args, os.Environ())
}

// runCommand runs a command and waits for it to complete
func runCommand(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	return cmd.Run()
}

// commandExists checks if a command exists in PATH
func commandExists(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

// fileExists checks if a file exists
func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

// dirIsEmpty checks if a directory is empty
func dirIsEmpty(path string) bool {
	entries, err := os.ReadDir(path)
	if err != nil {
		return true // treat errors as empty
	}
	return len(entries) == 0
}

// runInShell runs a command in a shell
func runInShell(command string) error {
	cmd := exec.Command("/bin/bash", "-c", command)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	cmd.Env = os.Environ()
	return cmd.Run()
}

// versionInstalled checks if a version manager has a version installed
func versionInstalled(manager, version string) bool {
	switch manager {
	case "rbenv":
		cmd := exec.Command("rbenv", "versions", "--bare")
		output, err := cmd.Output()
		if err != nil {
			return false
		}
		for _, line := range strings.Split(string(output), "\n") {
			if strings.TrimSpace(line) == version {
				return true
			}
		}
		return false
	case "nvm":
		// NVM requires sourcing, check directory exists
		nvmPath := filepath.Join(os.Getenv("HOME"), ".nvm", "versions", "node", "v"+version)
		return fileExists(nvmPath)
	case "pyenv":
		cmd := exec.Command("pyenv", "versions", "--bare")
		output, err := cmd.Output()
		if err != nil {
			return false
		}
		for _, line := range strings.Split(string(output), "\n") {
			if strings.TrimSpace(line) == version {
				return true
			}
		}
		return false
	default:
		return false
	}
}
