package strategy

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// PythonStrategy implements the Strategy interface for Python projects.
type PythonStrategy struct {
	BaseStrategy
	strategiesDir string
}

// NewPythonStrategy creates a new Python strategy.
func NewPythonStrategy() *PythonStrategy {
	return &PythonStrategy{
		BaseStrategy:  BaseStrategy{name: "python"},
		strategiesDir: "strategies",
	}
}

// Detect runs the Python detection script.
func (s *PythonStrategy) Detect(projectPath string) (int, string, error) {
	confidence, evidence, err := runDetectScript(s.strategiesDir, "python", projectPath)
	if err != nil {
		return 0, "", FormatError("python", "detect", err)
	}
	return confidence, evidence, nil
}

// Volumes returns the Docker volumes needed for Python.
func (s *PythonStrategy) Volumes(hash string) []VolumeMount {
	return []VolumeMount{
		{Name: fmt.Sprintf("claude-yolo-%s-pyenv", hash), Target: "/home/claude/.pyenv/versions"},
	}
}

// EnvVars returns the environment variables needed for Python.
func (s *PythonStrategy) EnvVars(projectPath string) ([]EnvVar, error) {
	pythonVersion, err := detectPythonVersion(projectPath)
	if err != nil {
		return nil, FormatError("python", "detect python version", err)
	}

	return []EnvVar{
		{Key: "PYTHON_VERSION", Value: pythonVersion},
	}, nil
}

// DefaultPorts returns the default port mappings for Python (macOS only).
func (s *PythonStrategy) DefaultPorts() []PortMapping {
	return []PortMapping{
		{Host: 8000, Container: 8000},
	}
}

// InfoMessage returns the info message to display when starting Python container.
func (s *PythonStrategy) InfoMessage(projectPath string) (string, error) {
	pythonVersion, err := detectPythonVersion(projectPath)
	if err != nil {
		return "", FormatError("python", "detect python version", err)
	}

	return fmt.Sprintf("Python %s · pip", pythonVersion), nil
}

// detectPythonVersion detects the Python version from project files.
func detectPythonVersion(projectPath string) (string, error) {
	// Check .python-version
	pythonVersionFile := filepath.Join(projectPath, ".python-version")
	if data, err := os.ReadFile(pythonVersionFile); err == nil {
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
			if strings.HasPrefix(line, "python ") {
				fields := strings.Fields(line)
				if len(fields) >= 2 {
					return fields[1], nil
				}
			}
		}
	}

	// Check pyproject.toml
	pyprojectFile := filepath.Join(projectPath, "pyproject.toml")
	if data, err := os.ReadFile(pyprojectFile); err == nil {
		lines := strings.Split(string(data), "\n")
		re := regexp.MustCompile(`requires-python\s*=\s*"?>=?\s*([0-9]+\.[0-9]+)`)
		for _, line := range lines {
			if matches := re.FindStringSubmatch(line); len(matches) > 1 {
				return matches[1], nil
			}
		}
	}

	// Default version
	return "3.12", nil
}
