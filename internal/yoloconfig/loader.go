// Package yoloconfig handles .yolo/ project configuration loading and trust management.
package yoloconfig

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/rickgorman/claude-yolo/pkg/hash"
)

// Config represents a loaded .yolo/ configuration.
type Config struct {
	Dir           string
	Strategy      string
	Dockerfile    string
	Env           map[string]string
	Ports         []string
	HasDockerfile bool
	Trusted       bool
}

// Load attempts to load .yolo/ configuration from a worktree.
// Returns nil if no .yolo/ directory exists.
func Load(worktreePath string, autoTrust bool) (*Config, error) {
	yoloDir := filepath.Join(worktreePath, ".yolo")

	info, err := os.Stat(yoloDir)
	if err != nil || !info.IsDir() {
		return nil, nil // No .yolo/ directory
	}

	config := &Config{
		Dir: yoloDir,
		Env: make(map[string]string),
	}

	// Load strategy override
	if strategyFile := filepath.Join(yoloDir, "strategy"); fileExists(strategyFile) {
		data, _ := os.ReadFile(strategyFile)
		config.Strategy = strings.TrimSpace(string(data))
	}

	// Check for Dockerfile
	if dockerfile := filepath.Join(yoloDir, "Dockerfile"); fileExists(dockerfile) {
		config.Dockerfile = dockerfile
		config.HasDockerfile = true
	}

	// Load env vars
	if envFile := filepath.Join(yoloDir, "env"); fileExists(envFile) {
		config.Env, _ = loadEnvFile(envFile)
	}

	// Load ports
	if portsFile := filepath.Join(yoloDir, "ports"); fileExists(portsFile) {
		config.Ports, _ = loadPortsFile(portsFile)
	}

	// Check trust
	configHash, err := computeConfigHash(yoloDir)
	if err != nil {
		return config, err
	}

	if autoTrust {
		if err := trustConfig(configHash); err != nil {
			return config, err
		}
		config.Trusted = true
	} else {
		config.Trusted = isConfigTrusted(configHash)
	}

	return config, nil
}

func loadEnvFile(path string) (map[string]string, error) {
	env := make(map[string]string)

	file, err := os.Open(path)
	if err != nil {
		return env, err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())

		// Skip comments and empty lines
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		// Strip export prefix
		line = strings.TrimPrefix(line, "export ")

		// Parse KEY=VALUE
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}

		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])

		// Strip quotes
		value = strings.Trim(value, "\"'")

		env[key] = value
	}

	return env, scanner.Err()
}

func loadPortsFile(path string) ([]string, error) {
	var ports []string

	file, err := os.Open(path)
	if err != nil {
		return ports, err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())

		// Skip comments, empty lines, and hash comment
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		// Remove whitespace
		line = strings.ReplaceAll(line, " ", "")

		ports = append(ports, line)
	}

	return ports, scanner.Err()
}

func computeConfigHash(yoloDir string) (string, error) {
	var combined strings.Builder

	entries, err := os.ReadDir(yoloDir)
	if err != nil {
		return "", err
	}

	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}

		filePath := filepath.Join(yoloDir, entry.Name())
		data, err := os.ReadFile(filePath)
		if err != nil {
			continue
		}

		combined.Write(data)
	}

	fullHash := hash.MD5Sum(combined.String())
	return fullHash[:16], nil
}

func isConfigTrusted(configHash string) bool {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return false
	}

	trustFile := filepath.Join(homeDir, ".claude", ".yolo-trusted")
	data, err := os.ReadFile(trustFile)
	if err != nil {
		return false
	}

	return strings.Contains(string(data), configHash)
}

func trustConfig(configHash string) error {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return err
	}

	trustFile := filepath.Join(homeDir, ".claude", ".yolo-trusted")
	os.MkdirAll(filepath.Dir(trustFile), 0755)

	file, err := os.OpenFile(trustFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}
	defer file.Close()

	_, err = fmt.Fprintln(file, configHash)
	return err
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
