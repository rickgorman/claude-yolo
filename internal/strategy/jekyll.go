package strategy

import (
	"fmt"
)

// JekyllStrategy implements the Strategy interface for Jekyll projects.
type JekyllStrategy struct {
	BaseStrategy
	strategiesDir string
}

// NewJekyllStrategy creates a new Jekyll strategy.
func NewJekyllStrategy() *JekyllStrategy {
	return &JekyllStrategy{
		BaseStrategy:  BaseStrategy{name: "jekyll"},
		strategiesDir: "strategies",
	}
}

// Detect runs the Jekyll detection script.
func (s *JekyllStrategy) Detect(projectPath string) (int, string, error) {
	confidence, evidence, err := runDetectScript(s.strategiesDir, "jekyll", projectPath)
	if err != nil {
		return 0, "", FormatError("jekyll", "detect", err)
	}
	return confidence, evidence, nil
}

// Volumes returns the Docker volumes needed for Jekyll.
func (s *JekyllStrategy) Volumes(hash string) []VolumeMount {
	return []VolumeMount{
		{Name: fmt.Sprintf("claude-yolo-%s-gems", hash), Target: "/home/claude/.gems"},
		{Name: fmt.Sprintf("claude-yolo-%s-rbenv", hash), Target: "/home/claude/.rbenv/versions"},
	}
}

// EnvVars returns the environment variables needed for Jekyll.
func (s *JekyllStrategy) EnvVars(projectPath string) ([]EnvVar, error) {
	rubyVersion, err := detectRubyVersion(projectPath)
	if err != nil {
		return nil, FormatError("jekyll", "detect ruby version", err)
	}

	return []EnvVar{
		{Key: "RUBY_VERSION", Value: rubyVersion},
	}, nil
}

// DefaultPorts returns the default port mappings for Jekyll (macOS only).
func (s *JekyllStrategy) DefaultPorts() []PortMapping {
	// Jekyll doesn't have default ports
	return []PortMapping{}
}

// InfoMessage returns the info message to display when starting Jekyll container.
func (s *JekyllStrategy) InfoMessage(projectPath string) (string, error) {
	rubyVersion, err := detectRubyVersion(projectPath)
	if err != nil {
		return "", FormatError("jekyll", "detect ruby version", err)
	}

	return fmt.Sprintf("Jekyll · Ruby %s", rubyVersion), nil
}
