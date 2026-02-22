// Package chrome provides Chrome DevTools Protocol integration.
package chrome

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

// IsAvailable checks if Chrome CDP is available on the specified port.
func IsAvailable(port int) bool {
	url := fmt.Sprintf("http://localhost:%d/json/version", port)
	client := &http.Client{Timeout: 1 * time.Second}

	resp, err := client.Get(url)
	if err != nil {
		return false
	}
	defer resp.Body.Close()

	return resp.StatusCode == http.StatusOK
}

// EnsureRunning starts Chrome if it's not already running on the specified port.
// It calls the existing scripts/start-chrome.sh script.
func EnsureRunning(port int, repoDir string) error {
	if IsAvailable(port) {
		return nil
	}

	script := filepath.Join(repoDir, "scripts", "start-chrome.sh")
	cmd := exec.Command(script)
	cmd.Env = append(os.Environ(), fmt.Sprintf("CDP_PORT=%d", port))

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to start Chrome: %w", err)
	}

	// Wait for Chrome to be available
	for i := 0; i < 20; i++ {
		if IsAvailable(port) {
			return nil
		}
		time.Sleep(500 * time.Millisecond)
	}

	return fmt.Errorf("Chrome CDP not available after startup attempt")
}

// Stop stops the Chrome instance on the specified port.
func Stop(port int, repoDir string) error {
	script := filepath.Join(repoDir, "scripts", "start-chrome.sh")
	cmd := exec.Command(script, "--stop")
	cmd.Env = append(os.Environ(), fmt.Sprintf("CDP_PORT=%d", port))
	return cmd.Run()
}

// MCPConfig represents the MCP server configuration for Chrome DevTools.
type MCPConfig struct {
	MCPServers map[string]MCPServer `json:"mcpServers"`
}

// MCPServer represents a single MCP server configuration.
type MCPServer struct {
	Command string   `json:"command"`
	Args    []string `json:"args"`
}

// GenerateMCPConfig creates an MCP configuration for Chrome DevTools.
// If an existing config exists, it merges the chrome-devtools entry.
func GenerateMCPConfig(existingConfigPath string, cdpHost string, cdpPort int) ([]byte, error) {
	browserURL := fmt.Sprintf("http://%s:%d", cdpHost, cdpPort)

	chromeEntry := MCPServer{
		Command: "npx",
		Args:    []string{"-y", "chrome-devtools-mcp@latest", fmt.Sprintf("--browser-url=%s", browserURL)},
	}

	config := &MCPConfig{
		MCPServers: map[string]MCPServer{
			"chrome-devtools": chromeEntry,
		},
	}

	// If existing config exists and is valid JSON, merge it
	if existingConfigPath != "" {
		if data, err := os.ReadFile(existingConfigPath); err == nil {
			var existing MCPConfig
			if json.Unmarshal(data, &existing) == nil {
				// Merge existing servers (chrome-devtools will override)
				for k, v := range existing.MCPServers {
					if k != "chrome-devtools" {
						config.MCPServers[k] = v
					}
				}
			}
		}
	}

	return json.MarshalIndent(config, "", "  ")
}

// WriteMCPConfig writes an MCP configuration to a temporary file.
func WriteMCPConfig(cdpHost string, cdpPort int, existingConfigPath string) (string, error) {
	data, err := GenerateMCPConfig(existingConfigPath, cdpHost, cdpPort)
	if err != nil {
		return "", err
	}

	tmpfile, err := os.CreateTemp("/tmp", "claude-yolo-mcp-*")
	if err != nil {
		return "", err
	}
	defer tmpfile.Close()

	if _, err := tmpfile.Write(data); err != nil {
		os.Remove(tmpfile.Name())
		return "", err
	}

	return tmpfile.Name(), nil
}
