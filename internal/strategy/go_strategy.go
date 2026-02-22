package strategy

import (
	"fmt"
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

// Detect runs the Go detection script.
func (s *GoStrategy) Detect(projectPath string) (int, string, error) {
	confidence, evidence, err := runDetectScript(s.strategiesDir, "go", projectPath)
	if err != nil {
		return 0, "", FormatError("go", "detect", err)
	}
	return confidence, evidence, nil
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
