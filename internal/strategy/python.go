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

// Detect checks for Python project indicators using pure Go.
func (s *PythonStrategy) Detect(projectPath string) (confidence int, message string, err error) {
	evidence := []string{}

	// Check for pyproject.toml (strong signal — modern Python)
	if _, err := os.Stat(filepath.Join(projectPath, "pyproject.toml")); err == nil {
		confidence += 35
		evidence = append(evidence, "pyproject.toml")
	}

	// Check for requirements.txt
	if _, err := os.Stat(filepath.Join(projectPath, "requirements.txt")); err == nil {
		confidence += 30
		evidence = append(evidence, "requirements.txt")
	}

	// Check for setup.py (legacy but common)
	if _, err := os.Stat(filepath.Join(projectPath, "setup.py")); err == nil {
		confidence += 20
		evidence = append(evidence, "setup.py")
	}

	// Check for setup.cfg
	if _, err := os.Stat(filepath.Join(projectPath, "setup.cfg")); err == nil {
		confidence += 10
		evidence = append(evidence, "setup.cfg")
	}

	// Check for .python-version (pyenv)
	pythonVersionPath := filepath.Join(projectPath, ".python-version")
	if data, err := os.ReadFile(pythonVersionPath); err == nil {
		pythonVer := strings.TrimSpace(string(data))
		confidence += 15
		evidence = append(evidence, fmt.Sprintf(".python-version (%s)", pythonVer))
	}

	// Check for Pipfile (pipenv)
	if _, err := os.Stat(filepath.Join(projectPath, "Pipfile")); err == nil {
		confidence += 20
		evidence = append(evidence, "Pipfile")
	}

	// Check for poetry.lock
	if _, err := os.Stat(filepath.Join(projectPath, "poetry.lock")); err == nil {
		confidence += 10
		evidence = append(evidence, "poetry.lock")
	}

	// Check for uv.lock (uv package manager)
	if _, err := os.Stat(filepath.Join(projectPath, "uv.lock")); err == nil {
		confidence += 10
		evidence = append(evidence, "uv.lock")
	}

	// Check for tox.ini
	if _, err := os.Stat(filepath.Join(projectPath, "tox.ini")); err == nil {
		confidence += 5
		evidence = append(evidence, "tox.ini")
	}

	// Cap at 100
	if confidence > 100 {
		confidence = 100
	}

	return confidence, strings.Join(evidence, ", "), nil
}

// Volumes returns the Docker volumes needed for Python.
func (s *PythonStrategy) Volumes(hash string) []VolumeMount {
	return []VolumeMount{
		{Name: fmt.Sprintf("claude-yolo-%s-pyenv", hash), Target: "/home/claude/.pyenv/versions"},
	}
}

// EnvVars returns the environment variables needed for Python.
func (s *PythonStrategy) EnvVars(projectPath string) ([]EnvVar, error) {
	pythonVersion := detectPythonVersion(projectPath)

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
	pythonVersion := detectPythonVersion(projectPath)

	return fmt.Sprintf("Python %s · pip", pythonVersion), nil
}

// detectPythonVersion detects the Python version from project files.
func detectPythonVersion(projectPath string) string {
	// Check .python-version
	pythonVersionFile := filepath.Join(projectPath, ".python-version")
	if data, err := os.ReadFile(pythonVersionFile); err == nil {
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
			if strings.HasPrefix(line, "python ") {
				fields := strings.Fields(line)
				if len(fields) >= 2 {
					return fields[1]
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
				return matches[1]
			}
		}
	}

	// Default version
	return "3.12"
}
