package strategy

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// RailsStrategy implements the Strategy interface for Ruby on Rails projects.
type RailsStrategy struct {
	BaseStrategy
	strategiesDir string
}

// NewRailsStrategy creates a new Rails strategy.
func NewRailsStrategy() *RailsStrategy {
	return &RailsStrategy{
		BaseStrategy:  BaseStrategy{name: "rails"},
		strategiesDir: "strategies",
	}
}

// Detect runs the Rails detection script.
func (s *RailsStrategy) Detect(projectPath string) (int, string, error) {
	confidence, evidence, err := runDetectScript(s.strategiesDir, "rails", projectPath)
	if err != nil {
		return 0, "", FormatError("rails", "detect", err)
	}
	return confidence, evidence, nil
}

// Volumes returns the Docker volumes needed for Rails.
func (s *RailsStrategy) Volumes(hash string) []VolumeMount {
	return []VolumeMount{
		{Name: fmt.Sprintf("claude-yolo-%s-gems", hash), Target: "/home/claude/.gems"},
		{Name: fmt.Sprintf("claude-yolo-%s-rbenv", hash), Target: "/home/claude/.rbenv/versions"},
		{Name: fmt.Sprintf("claude-yolo-%s-node", hash), Target: "/workspace/node_modules"},
	}
}

// EnvVars returns the environment variables needed for Rails.
func (s *RailsStrategy) EnvVars(projectPath string) ([]EnvVar, error) {
	rubyVersion, err := detectRubyVersion(projectPath)
	if err != nil {
		return nil, FormatError("rails", "detect ruby version", err)
	}

	return []EnvVar{
		{Key: "RUBY_VERSION", Value: rubyVersion},
		{Key: "DB_HOST", Value: "host.docker.internal"},
		{Key: "DB_USERNAME", Value: "postgres"},
		{Key: "DB_PASSWORD", Value: "postgres"},
	}, nil
}

// DefaultPorts returns the default port mappings for Rails (macOS only).
func (s *RailsStrategy) DefaultPorts() []PortMapping {
	return []PortMapping{
		{Host: 3000, Container: 3000},
		{Host: 5173, Container: 5173},
	}
}

// InfoMessage returns the info message to display when starting Rails container.
func (s *RailsStrategy) InfoMessage(projectPath string) (string, error) {
	rubyVersion, err := detectRubyVersion(projectPath)
	if err != nil {
		return "", FormatError("rails", "detect ruby version", err)
	}

	return fmt.Sprintf("Ruby %s · Postgres", rubyVersion), nil
}

// detectRubyVersion detects the Ruby version from project files.
func detectRubyVersion(projectPath string) (string, error) {
	// Check .ruby-version
	rubyVersionFile := filepath.Join(projectPath, ".ruby-version")
	if data, err := os.ReadFile(rubyVersionFile); err == nil {
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
			if strings.HasPrefix(line, "ruby ") || strings.HasPrefix(line, "local ruby ") {
				fields := strings.Fields(line)
				if len(fields) >= 2 {
					return fields[len(fields)-1], nil
				}
			}
		}
	}

	// Check Gemfile
	gemfile := filepath.Join(projectPath, "Gemfile")
	if data, err := os.ReadFile(gemfile); err == nil {
		lines := strings.Split(string(data), "\n")
		for _, line := range lines {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "ruby ") {
				// Extract version from: ruby "3.2.0" or ruby '3.2.0'
				line = strings.TrimPrefix(line, "ruby ")
				line = strings.Trim(line, "\"'")
				if line != "" {
					return line, nil
				}
			}
		}
	}

	// Default version
	return "4.0.1", nil
}
