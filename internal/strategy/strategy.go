// Package strategy provides environment detection and configuration for different project types.
package strategy

import (
	"fmt"
)

// DetectionResult holds the output from a detection script.
type DetectionResult struct {
	Strategy   string
	Confidence int
	Evidence   string
}

// VolumeMount represents a Docker volume mount configuration.
type VolumeMount struct {
	Name   string
	Target string
}

// EnvVar represents an environment variable.
type EnvVar struct {
	Key   string
	Value string
}

// PortMapping represents a port mapping for macOS.
type PortMapping struct {
	Host      int
	Container int
}

// Strategy defines the interface that all environment strategies must implement.
type Strategy interface {
	// Name returns the strategy name (e.g., "rails", "node", "python")
	Name() string

	// Detect runs the detection script and returns the confidence level and evidence.
	// Returns confidence (0-100) and evidence string.
	Detect(projectPath string) (int, string, error)

	// Volumes returns the Docker volumes needed for this strategy.
	// The hash parameter is used to create project-specific volume names.
	Volumes(hash string) []VolumeMount

	// EnvVars returns the environment variables needed for this strategy.
	// The projectPath parameter is used for version detection.
	EnvVars(projectPath string) ([]EnvVar, error)

	// DefaultPorts returns the default port mappings for macOS.
	DefaultPorts() []PortMapping

	// InfoMessage returns the info message to display when starting a container.
	// The projectPath parameter is used for version detection.
	InfoMessage(projectPath string) (string, error)
}

// BaseStrategy provides common functionality for all strategies.
type BaseStrategy struct {
	name string
}

// Name returns the strategy name.
func (s *BaseStrategy) Name() string {
	return s.name
}

// FormatError creates a formatted error message for strategy operations.
func FormatError(strategy, operation string, err error) error {
	return fmt.Errorf("strategy %s: %s: %w", strategy, operation, err)
}
