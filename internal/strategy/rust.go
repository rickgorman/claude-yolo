package strategy

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
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

// Detect checks for Rust project indicators using pure Go.
func (s *RustStrategy) Detect(projectPath string) (confidence int, message string, err error) {
	evidence := []string{}

	// Check for Cargo.toml (strong signal)
	if _, err := os.Stat(filepath.Join(projectPath, "Cargo.toml")); err == nil {
		confidence += 40
		evidence = append(evidence, "Cargo.toml")
	}

	// Check for Cargo.lock
	if _, err := os.Stat(filepath.Join(projectPath, "Cargo.lock")); err == nil {
		confidence += 10
		evidence = append(evidence, "Cargo.lock")
	}

	// Check for src/main.rs or src/lib.rs
	if _, err := os.Stat(filepath.Join(projectPath, "src", "main.rs")); err == nil {
		confidence += 20
		evidence = append(evidence, "src/main.rs")
	} else if _, err := os.Stat(filepath.Join(projectPath, "src", "lib.rs")); err == nil {
		confidence += 20
		evidence = append(evidence, "src/lib.rs")
	}

	// Check for rust-toolchain.toml or rust-toolchain
	if _, err := os.Stat(filepath.Join(projectPath, "rust-toolchain.toml")); err == nil {
		confidence += 15
		evidence = append(evidence, "rust-toolchain")
	} else if _, err := os.Stat(filepath.Join(projectPath, "rust-toolchain")); err == nil {
		confidence += 15
		evidence = append(evidence, "rust-toolchain")
	}

	// Check for .cargo/ directory
	if info, err := os.Stat(filepath.Join(projectPath, ".cargo")); err == nil && info.IsDir() {
		confidence += 5
		evidence = append(evidence, ".cargo/")
	}

	// Check for build.rs
	if _, err := os.Stat(filepath.Join(projectPath, "build.rs")); err == nil {
		confidence += 10
		evidence = append(evidence, "build.rs")
	}

	// Cap at 100
	if confidence > 100 {
		confidence = 100
	}

	return confidence, strings.Join(evidence, ", "), nil
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
