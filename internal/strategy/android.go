package strategy

import (
	"fmt"
	"os"
)

// AndroidStrategy implements the Strategy interface for Android projects.
type AndroidStrategy struct {
	BaseStrategy
	strategiesDir string
}

// NewAndroidStrategy creates a new Android strategy.
func NewAndroidStrategy() *AndroidStrategy {
	return &AndroidStrategy{
		BaseStrategy:  BaseStrategy{name: "android"},
		strategiesDir: "strategies",
	}
}

// Detect runs the Android detection script.
func (s *AndroidStrategy) Detect(projectPath string) (int, string, error) {
	confidence, evidence, err := runDetectScript(s.strategiesDir, "android", projectPath)
	if err != nil {
		return 0, "", FormatError("android", "detect", err)
	}
	return confidence, evidence, nil
}

// Volumes returns the Docker volumes needed for Android.
func (s *AndroidStrategy) Volumes(hash string) []VolumeMount {
	return []VolumeMount{
		{Name: fmt.Sprintf("claude-yolo-%s-gradle", hash), Target: "/home/claude/.gradle"},
	}
}

// EnvVars returns the environment variables needed for Android.
func (s *AndroidStrategy) EnvVars(projectPath string) ([]EnvVar, error) {
	envVars := []EnvVar{}

	// Add ANDROID_DEVICE if set
	if device := os.Getenv("ANDROID_DEVICE"); device != "" {
		envVars = append(envVars, EnvVar{Key: "ANDROID_DEVICE", Value: device})
	}

	return envVars, nil
}

// DefaultPorts returns the default port mappings for Android (macOS only).
func (s *AndroidStrategy) DefaultPorts() []PortMapping {
	// Android doesn't have default ports
	return []PortMapping{}
}

// InfoMessage returns the info message to display when starting Android container.
func (s *AndroidStrategy) InfoMessage(projectPath string) (string, error) {
	if device := os.Getenv("ANDROID_DEVICE"); device != "" {
		return fmt.Sprintf("Device    %s", device), nil
	}
	return "Device    set ANDROID_DEVICE=<ip>:<port> to auto-connect", nil
}
