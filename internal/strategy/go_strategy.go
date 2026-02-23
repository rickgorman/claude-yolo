package strategy

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// GoStrategy implements the Strategy interface for Go projects.
type GoStrategy struct {
	BaseStrategy
	strategiesDir string
}

// NewGoStrategy creates a new Go strategy.
func NewGoStrategy() *GoStrategy {
	return &GoStrategy{
		BaseStrategy:  BaseStrategy{name: "go"},
		strategiesDir: "strategies",
	}
}

// Detect checks for Go project indicators using pure Go.
func (s *GoStrategy) Detect(projectPath string) (confidence int, message string, err error) {
	evidence := []string{}

	// Check for go.mod (strong signal)
	if _, err := os.Stat(filepath.Join(projectPath, "go.mod")); err == nil {
		confidence += 50
		evidence = append(evidence, "go.mod")
	}

	// Check for go.sum
	if _, err := os.Stat(filepath.Join(projectPath, "go.sum")); err == nil {
		confidence += 15
		evidence = append(evidence, "go.sum")
	}

	// Check for main.go in root
	if _, err := os.Stat(filepath.Join(projectPath, "main.go")); err == nil {
		confidence += 15
		evidence = append(evidence, "main.go")
	}

	// Check for cmd/ directory with Go files
	cmdDir := filepath.Join(projectPath, "cmd")
	if info, err := os.Stat(cmdDir); err == nil && info.IsDir() {
		hasGoFiles := false
		_ = filepath.Walk(cmdDir, func(path string, info os.FileInfo, err error) error {
			if err != nil || hasGoFiles {
				return filepath.SkipDir
			}
			// Only check first 2 levels
			rel, _ := filepath.Rel(cmdDir, path)
			depth := strings.Count(rel, string(filepath.Separator))
			if depth > 2 {
				return filepath.SkipDir
			}
			if !info.IsDir() && strings.HasSuffix(path, ".go") {
				hasGoFiles = true
				return filepath.SkipDir
			}
			return nil
		})
		if hasGoFiles {
			confidence += 10
			evidence = append(evidence, "cmd/")
		}
	}

	// Check for .go-version
	goVersionPath := filepath.Join(projectPath, ".go-version")
	if data, err := os.ReadFile(goVersionPath); err == nil {
		goVer := strings.TrimSpace(string(data))
		confidence += 10
		evidence = append(evidence, fmt.Sprintf(".go-version (%s)", goVer))
	}

	// Check for .tool-versions with golang entry
	toolVersionsFile := filepath.Join(projectPath, ".tool-versions")
	if data, err := os.ReadFile(toolVersionsFile); err == nil {
		lines := strings.Split(string(data), "\n")
		for _, line := range lines {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "golang ") {
				confidence += 10
				evidence = append(evidence, ".tool-versions (golang)")
				break
			}
		}
	}

	// Cap at 100
	if confidence > 100 {
		confidence = 100
	}

	return confidence, strings.Join(evidence, ", "), nil
}

// Volumes returns the Docker volumes needed for Go.
func (s *GoStrategy) Volumes(hash string) []VolumeMount {
	return []VolumeMount{
		{Name: fmt.Sprintf("claude-yolo-%s-gopath", hash), Target: "/home/claude/go"},
	}
}

// EnvVars returns the environment variables needed for Go.
func (s *GoStrategy) EnvVars(projectPath string) ([]EnvVar, error) {
	// Go doesn't need version detection - uses system Go
	return []EnvVar{}, nil
}

// DefaultPorts returns the default port mappings for Go (macOS only).
func (s *GoStrategy) DefaultPorts() []PortMapping {
	return []PortMapping{
		{Host: 8080, Container: 8080},
	}
}

// InfoMessage returns the info message to display when starting Go container.
func (s *GoStrategy) InfoMessage(projectPath string) (string, error) {
	return "Go · modules", nil
}
