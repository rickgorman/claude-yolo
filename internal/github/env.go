// Package github provides GitHub token detection and validation.
package github

import (
	"bufio"
	"os"
	"strings"
)

// parseEnvFile reads a .env file and searches for GH_TOKEN or GITHUB_TOKEN.
// Supports formats:
//   - GH_TOKEN=value
//   - GITHUB_TOKEN=value
//   - export GH_TOKEN=value
//   - export GITHUB_TOKEN=value
// Values can be quoted with single or double quotes.
func parseEnvFile(filePath string) (string, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return "", err
	}
	defer func() { _ = file.Close() }()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		// Try both GH_TOKEN and GITHUB_TOKEN
		for _, key := range []string{"GH_TOKEN", "GITHUB_TOKEN"} {
			if token := extractTokenFromLine(line, key); token != "" {
				return token, nil
			}
		}
	}

	if err := scanner.Err(); err != nil {
		return "", err
	}

	return "", nil
}

// extractTokenFromLine extracts a token value from a line like:
// GH_TOKEN=value or export GH_TOKEN="value" or GITHUB_TOKEN='value'
// Also handles whitespace around the equals sign: GH_TOKEN = value
func extractTokenFromLine(line, key string) string {
	// Handle "export KEY=value" format
	line = strings.TrimPrefix(line, "export ")
	line = strings.TrimSpace(line)

	// Check if line starts with the key (with optional whitespace before =)
	if !strings.HasPrefix(line, key) {
		return ""
	}

	// Remove the key from the beginning
	line = strings.TrimPrefix(line, key)
	line = strings.TrimSpace(line)

	// Check for equals sign
	if !strings.HasPrefix(line, "=") {
		return ""
	}

	// Remove equals sign
	line = strings.TrimPrefix(line, "=")
	line = strings.TrimSpace(line)

	// Remove quotes (single or double)
	value := strings.Trim(line, `"'`)
	value = strings.TrimSpace(value)

	return value
}
