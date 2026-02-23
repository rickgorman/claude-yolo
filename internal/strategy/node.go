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

// Detect checks for Node.js/TypeScript project indicators using pure Go.
func (s *NodeStrategy) Detect(projectPath string) (confidence int, message string, err error) {
	evidence := []string{}

	// Check for package.json (strong signal)
	if _, err := os.Stat(filepath.Join(projectPath, "package.json")); err == nil {
		confidence += 40
		evidence = append(evidence, "package.json")
	}

	// Check for lock files
	if _, err := os.Stat(filepath.Join(projectPath, "package-lock.json")); err == nil {
		confidence += 15
		evidence = append(evidence, "package-lock.json")
	} else if _, err := os.Stat(filepath.Join(projectPath, "yarn.lock")); err == nil {
		confidence += 15
		evidence = append(evidence, "yarn.lock")
	} else if _, err := os.Stat(filepath.Join(projectPath, "pnpm-lock.yaml")); err == nil {
		confidence += 15
		evidence = append(evidence, "pnpm-lock.yaml")
	} else if _, err := os.Stat(filepath.Join(projectPath, "bun.lockb")); err == nil {
		confidence += 15
		evidence = append(evidence, "bun.lock")
	} else if _, err := os.Stat(filepath.Join(projectPath, "bun.lock")); err == nil {
		confidence += 15
		evidence = append(evidence, "bun.lock")
	}

	// Check for tsconfig.json
	if _, err := os.Stat(filepath.Join(projectPath, "tsconfig.json")); err == nil {
		confidence += 15
		evidence = append(evidence, "tsconfig.json")
	}

	// Check for .nvmrc
	nvmrcPath := filepath.Join(projectPath, ".nvmrc")
	if data, err := os.ReadFile(nvmrcPath); err == nil {
		nodeVer := strings.TrimSpace(string(data))
		confidence += 10
		evidence = append(evidence, fmt.Sprintf(".nvmrc (%s)", nodeVer))
	} else {
		// Check for .node-version
		nodeVersionPath := filepath.Join(projectPath, ".node-version")
		if data, err := os.ReadFile(nodeVersionPath); err == nil {
			nodeVer := strings.TrimSpace(string(data))
			confidence += 10
			evidence = append(evidence, fmt.Sprintf(".node-version (%s)", nodeVer))
		}
	}

	// Check for .tool-versions with nodejs entry
	toolVersionsFile := filepath.Join(projectPath, ".tool-versions")
	if data, err := os.ReadFile(toolVersionsFile); err == nil {
		lines := strings.Split(string(data), "\n")
		for _, line := range lines {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "nodejs ") {
				confidence += 10
				evidence = append(evidence, ".tool-versions (nodejs)")
				break
			}
		}
	}

	// Check for framework configs
	nextConfigs := []string{"next.config.js", "next.config.ts", "next.config.mjs"}
	for _, cfg := range nextConfigs {
		if _, err := os.Stat(filepath.Join(projectPath, cfg)); err == nil {
			confidence += 10
			evidence = append(evidence, "next.config")
			break
		}
	}
	viteConfigs := []string{"vite.config.ts", "vite.config.js"}
	hasVite := false
	for _, cfg := range viteConfigs {
		if _, err := os.Stat(filepath.Join(projectPath, cfg)); err == nil {
			confidence += 10
			evidence = append(evidence, "vite.config")
			hasVite = true
			break
		}
	}
	if !hasVite {
		webpackConfigs := []string{"webpack.config.js", "webpack.config.ts"}
		for _, cfg := range webpackConfigs {
			if _, err := os.Stat(filepath.Join(projectPath, cfg)); err == nil {
				confidence += 10
				evidence = append(evidence, "webpack.config")
				break
			}
		}
	}

	// Negative signal: if this looks like a Rails project
	gemfilePath := filepath.Join(projectPath, "Gemfile")
	if data, err := os.ReadFile(gemfilePath); err == nil {
		content := string(data)
		if strings.Contains(content, "'rails'") {
			confidence -= 30
		}
	}

	// Floor at 0
	if confidence < 0 {
		confidence = 0
	}

	// Cap at 100
	if confidence > 100 {
		confidence = 100
	}

	return confidence, strings.Join(evidence, ", "), nil
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
	nodeVersion := detectNodeVersion(projectPath)

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
	nodeVersion := detectNodeVersion(projectPath)

	return fmt.Sprintf("Node.js %s · npm", nodeVersion), nil
}

// detectNodeVersion detects the Node version from project files.
func detectNodeVersion(projectPath string) string {
	// Check .nvmrc
	nvmrcFile := filepath.Join(projectPath, ".nvmrc")
	if data, err := os.ReadFile(nvmrcFile); err == nil {
		version := strings.TrimSpace(string(data))
		if version != "" {
			return version
		}
	}

	// Check .node-version
	nodeVersionFile := filepath.Join(projectPath, ".node-version")
	if data, err := os.ReadFile(nodeVersionFile); err == nil {
		version := strings.TrimSpace(string(data))
		if version != "" {
			return version
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
					return fields[1]
				}
			}
		}
	}

	// Default version
	return "20"
}
