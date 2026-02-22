package strategy

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// NodeStrategy implements the Strategy interface for Node.js/TypeScript projects.
type NodeStrategy struct {
	BaseStrategy
	strategiesDir string
}

// NewNodeStrategy creates a new Node strategy.
func NewNodeStrategy() *NodeStrategy {
	return &NodeStrategy{
		BaseStrategy:  BaseStrategy{name: "node"},
		strategiesDir: "strategies",
	}
}

// Detect runs the Node detection script.
func (s *NodeStrategy) Detect(projectPath string) (int, string, error) {
	confidence, evidence, err := runDetectScript(s.strategiesDir, "node", projectPath)
	if err != nil {
		return 0, "", FormatError("node", "detect", err)
	}
	return confidence, evidence, nil
}

// Volumes returns the Docker volumes needed for Node.
func (s *NodeStrategy) Volumes(hash string) []VolumeMount {
	return []VolumeMount{
		{Name: fmt.Sprintf("claude-yolo-%s-nvm", hash), Target: "/home/claude/.nvm"},
		{Name: fmt.Sprintf("claude-yolo-%s-node", hash), Target: "/workspace/node_modules"},
	}
}

// EnvVars returns the environment variables needed for Node.
func (s *NodeStrategy) EnvVars(projectPath string) ([]EnvVar, error) {
	nodeVersion, err := detectNodeVersion(projectPath)
	if err != nil {
		return nil, FormatError("node", "detect node version", err)
	}

	return []EnvVar{
		{Key: "NODE_VERSION", Value: nodeVersion},
	}, nil
}

// DefaultPorts returns the default port mappings for Node (macOS only).
func (s *NodeStrategy) DefaultPorts() []PortMapping {
	return []PortMapping{
		{Host: 3000, Container: 3000},
		{Host: 5173, Container: 5173},
	}
}

// InfoMessage returns the info message to display when starting Node container.
func (s *NodeStrategy) InfoMessage(projectPath string) (string, error) {
	nodeVersion, err := detectNodeVersion(projectPath)
	if err != nil {
		return "", FormatError("node", "detect node version", err)
	}

	return fmt.Sprintf("Node.js %s · npm", nodeVersion), nil
}

// detectNodeVersion detects the Node version from project files.
func detectNodeVersion(projectPath string) (string, error) {
	// Check .nvmrc
	nvmrcFile := filepath.Join(projectPath, ".nvmrc")
	if data, err := os.ReadFile(nvmrcFile); err == nil {
		version := strings.TrimSpace(string(data))
		if version != "" {
			return version, nil
		}
	}

	// Check .node-version
	nodeVersionFile := filepath.Join(projectPath, ".node-version")
	if data, err := os.ReadFile(nodeVersionFile); err == nil {
		version := strings.TrimSpace(string(data))
		if version != "" {
			return version, nil
		}
	}

	// Check .tool-versions
	toolVersionsFile := filepath.Join(projectPath, ".tool-versions")
	if data, err := os.ReadFile(toolVersionsFile); err == nil {
		lines := strings.Split(string(data), "\n")
		for _, line := range lines {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "nodejs ") {
				fields := strings.Fields(line)
				if len(fields) >= 2 {
					return fields[1], nil
				}
			}
		}
	}

	// Default version
	return "20", nil
}
