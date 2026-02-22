package github

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// TokenResult holds information about a discovered GitHub token.
type TokenResult struct {
	Token  string
	Source string
}

// FindToken searches for a GitHub token in multiple locations.
// Search order:
//  1. GH_TOKEN environment variable
//  2. GITHUB_TOKEN environment variable
//  3. .env file in project directory (worktreePath)
//  4. ~/.env
//  5. ~/.config/gh/hosts.yml (or $XDG_CONFIG_HOME/gh/hosts.yml)
//
// Returns the first token found, along with its source location.
func FindToken(worktreePath string) (*TokenResult, error) {
	// 1. Check GH_TOKEN env var
	if token := os.Getenv("GH_TOKEN"); token != "" {
		return &TokenResult{
			Token:  token,
			Source: "GH_TOKEN env var",
		}, nil
	}

	// 2. Check GITHUB_TOKEN env var
	if token := os.Getenv("GITHUB_TOKEN"); token != "" {
		return &TokenResult{
			Token:  token,
			Source: "GITHUB_TOKEN env var",
		}, nil
	}

	// 3. Check .env in project directory
	projectEnv := filepath.Join(worktreePath, ".env")
	if token, err := parseEnvFile(projectEnv); err == nil && token != "" {
		return &TokenResult{
			Token:  token,
			Source: projectEnv,
		}, nil
	}

	// 4. Check ~/.env
	homeDir, err := os.UserHomeDir()
	if err == nil {
		homeEnv := filepath.Join(homeDir, ".env")
		if token, err := parseEnvFile(homeEnv); err == nil && token != "" {
			return &TokenResult{
				Token:  token,
				Source: homeEnv,
			}, nil
		}
	}

	// 5. Check ~/.config/gh/hosts.yml
	ghConfigPath := getGHConfigPath()
	if token, err := parseGHHostsYAML(ghConfigPath); err == nil && token != "" {
		return &TokenResult{
			Token:  token,
			Source: ghConfigPath,
		}, nil
	}

	// No token found
	return nil, fmt.Errorf("GitHub token not found\n\nSearched:\n  • GH_TOKEN environment variable\n  • GITHUB_TOKEN environment variable\n  • %s/.env\n  • ~/.env\n  • ~/.config/gh/hosts.yml\n\nSet one with:\n  export GH_TOKEN=ghp_your_token_here\n\nOr skip this check entirely:\n  export CLAUDE_YOLO_NO_GITHUB=1",
		worktreePath)
}

// getGHConfigPath returns the path to gh CLI config file.
// Checks $XDG_CONFIG_HOME/gh/hosts.yml or ~/.config/gh/hosts.yml.
func getGHConfigPath() string {
	// Check XDG_CONFIG_HOME first
	if xdgConfig := os.Getenv("XDG_CONFIG_HOME"); xdgConfig != "" {
		return filepath.Join(xdgConfig, "gh", "hosts.yml")
	}

	// Fall back to ~/.config
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(homeDir, ".config", "gh", "hosts.yml")
}

// parseGHHostsYAML extracts the oauth_token from gh CLI's hosts.yml file.
// Simple parser that looks for lines like "    oauth_token: ghp_..."
func parseGHHostsYAML(filePath string) (string, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return "", err
	}
	defer func() { _ = file.Close() }()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()

		// Look for "oauth_token:" (with any amount of leading whitespace)
		if strings.Contains(line, "oauth_token:") {
			// Extract the value after "oauth_token:"
			parts := strings.SplitN(line, "oauth_token:", 2)
			if len(parts) == 2 {
				token := strings.TrimSpace(parts[1])
				if token != "" {
					return token, nil
				}
			}
		}
	}

	if err := scanner.Err(); err != nil {
		return "", err
	}

	return "", nil
}
