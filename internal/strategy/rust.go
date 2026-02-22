package strategy

import (
	"fmt"
)

// RustStrategy implements the Strategy interface for Rust projects.
type RustStrategy struct {
	BaseStrategy
	strategiesDir string
}

// NewRustStrategy creates a new Rust strategy.
func NewRustStrategy() *RustStrategy {
	return &RustStrategy{
		BaseStrategy:  BaseStrategy{name: "rust"},
		strategiesDir: "strategies",
	}
}

// Detect runs the Rust detection script.
func (s *RustStrategy) Detect(projectPath string) (int, string, error) {
	confidence, evidence, err := runDetectScript(s.strategiesDir, "rust", projectPath)
	if err != nil {
		return 0, "", FormatError("rust", "detect", err)
	}
	return confidence, evidence, nil
}

// Volumes returns the Docker volumes needed for Rust.
func (s *RustStrategy) Volumes(hash string) []VolumeMount {
	return []VolumeMount{
		{Name: fmt.Sprintf("claude-yolo-%s-cargo", hash), Target: "/home/claude/.cargo"},
		{Name: fmt.Sprintf("claude-yolo-%s-rustup", hash), Target: "/home/claude/.rustup"},
		{Name: fmt.Sprintf("claude-yolo-%s-target", hash), Target: "/workspace/target"},
	}
}

// EnvVars returns the environment variables needed for Rust.
func (s *RustStrategy) EnvVars(projectPath string) ([]EnvVar, error) {
	// Rust doesn't need version detection - uses rustup
	return []EnvVar{}, nil
}

// DefaultPorts returns the default port mappings for Rust (macOS only).
func (s *RustStrategy) DefaultPorts() []PortMapping {
	// Rust doesn't have default ports
	return []PortMapping{}
}

// InfoMessage returns the info message to display when starting Rust container.
func (s *RustStrategy) InfoMessage(projectPath string) (string, error) {
	return "Rust · Cargo", nil
}
