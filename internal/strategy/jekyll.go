package strategy

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
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

// Detect checks for Jekyll project indicators using pure Go.
func (s *JekyllStrategy) Detect(projectPath string) (confidence int, message string, err error) {
	evidence := []string{}

	// Check for _config.yml (strong Jekyll signal)
	configPath := filepath.Join(projectPath, "_config.yml")
	if data, err := os.ReadFile(configPath); err == nil {
		confidence += 35
		evidence = append(evidence, "_config.yml")

		// Check for Jekyll-specific keys in _config.yml
		content := string(data)
		re := regexp.MustCompile(`^(remote_theme|theme|jekyll|plugins):`)
		lines := strings.Split(content, "\n")
		for _, line := range lines {
			if re.MatchString(line) {
				confidence += 15
				evidence = append(evidence, "Jekyll config keys")
				break
			}
		}
	}

	// Check for Gemfile with jekyll gem
	gemfilePath := filepath.Join(projectPath, "Gemfile")
	if data, err := os.ReadFile(gemfilePath); err == nil {
		content := string(data)
		if strings.Contains(content, "'jekyll'") ||
			strings.Contains(content, `"jekyll"`) ||
			strings.Contains(content, "github-pages") {
			confidence += 30
			evidence = append(evidence, "Gemfile with jekyll")
		}
	}

	// Check for _layouts/ directory
	if info, err := os.Stat(filepath.Join(projectPath, "_layouts")); err == nil && info.IsDir() {
		confidence += 10
		evidence = append(evidence, "_layouts/")
	}

	// Check for _posts/ directory
	if info, err := os.Stat(filepath.Join(projectPath, "_posts")); err == nil && info.IsDir() {
		confidence += 5
		evidence = append(evidence, "_posts/")
	}

	// Check for _data/ directory
	if info, err := os.Stat(filepath.Join(projectPath, "_data")); err == nil && info.IsDir() {
		confidence += 5
		evidence = append(evidence, "_data/")
	}

	// Check for _includes/ directory
	if info, err := os.Stat(filepath.Join(projectPath, "_includes")); err == nil && info.IsDir() {
		confidence += 5
		evidence = append(evidence, "_includes/")
	}

	// Check for .ruby-version or .tool-versions (evidence only, no confidence)
	rubyVersionPath := filepath.Join(projectPath, ".ruby-version")
	if data, err := os.ReadFile(rubyVersionPath); err == nil {
		rubyVer := strings.TrimSpace(string(data))
		evidence = append(evidence, fmt.Sprintf(".ruby-version (%s)", rubyVer))
	} else {
		toolVersionsFile := filepath.Join(projectPath, ".tool-versions")
		if data, err := os.ReadFile(toolVersionsFile); err == nil {
			lines := strings.Split(string(data), "\n")
			for _, line := range lines {
				line = strings.TrimSpace(line)
				if strings.HasPrefix(line, "ruby ") {
					evidence = append(evidence, ".tool-versions (ruby)")
					break
				}
			}
		}
	}

	// Negative signal: if this looks like a Rails project
	gemfilePath = filepath.Join(projectPath, "Gemfile")
	if data, err := os.ReadFile(gemfilePath); err == nil {
		if strings.Contains(string(data), "'rails'") {
			confidence -= 50
		}
	}
	if _, err := os.Stat(filepath.Join(projectPath, "config", "application.rb")); err == nil {
		confidence -= 50
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

// Volumes returns the Docker volumes needed for Jekyll.
func (s *JekyllStrategy) Volumes(hash string) []VolumeMount {
	return []VolumeMount{
		{Name: fmt.Sprintf("claude-yolo-%s-gems", hash), Target: "/home/claude/.gems"},
		{Name: fmt.Sprintf("claude-yolo-%s-rbenv", hash), Target: "/home/claude/.rbenv/versions"},
	}
}

// EnvVars returns the environment variables needed for Jekyll.
func (s *JekyllStrategy) EnvVars(projectPath string) ([]EnvVar, error) {
	rubyVersion := detectRubyVersion(projectPath)

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
	rubyVersion := detectRubyVersion(projectPath)

	return fmt.Sprintf("Jekyll · Ruby %s", rubyVersion), nil
}
