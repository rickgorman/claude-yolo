package strategy

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
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

// Detect checks for Android project indicators using pure Go.
func (s *AndroidStrategy) Detect(projectPath string) (confidence int, message string, err error) {
	evidence := []string{}

	// Check both the root and an android/ subdirectory
	androidDir, hasSubdir := findAndroidDir(projectPath)
	if hasSubdir {
		evidence = append(evidence, "android/ subdir")
	}

	// Root build.gradle(.kts)
	if androidDir != "" {
		confidence += 15
		evidence = append(evidence, "build.gradle")
	}

	// settings.gradle(.kts)
	if androidDir != "" && hasSettingsGradle(androidDir) {
		confidence += 10
		evidence = append(evidence, "settings.gradle")
	}

	// app/build.gradle(.kts) - strong Android signal
	if androidDir != "" && hasAppBuildGradle(androidDir) {
		confidence += 20
		evidence = append(evidence, "app/build.gradle")
	}

	// AndroidManifest.xml anywhere in the tree (up to 5 levels deep)
	if findManifest(projectPath) {
		confidence += 25
		evidence = append(evidence, "AndroidManifest.xml")
	}

	// gradlew (in root or android/)
	if hasGradlew(projectPath, androidDir) {
		confidence += 10
		evidence = append(evidence, "gradlew")
	}

	// Android plugin in build files
	if androidDir != "" && hasAndroidPlugin(androidDir) {
		confidence += 20
		evidence = append(evidence, "com.android plugin")
	}

	// Cap at 100
	if confidence > 100 {
		confidence = 100
	}

	return confidence, strings.Join(evidence, ", "), nil
}

// findAndroidDir locates the Android project directory
func findAndroidDir(projectPath string) (androidDir string, hasSubdir bool) {
	if fileExists(filepath.Join(projectPath, "build.gradle")) ||
		fileExists(filepath.Join(projectPath, "build.gradle.kts")) {
		return projectPath, false
	}
	if fileExists(filepath.Join(projectPath, "android", "build.gradle")) ||
		fileExists(filepath.Join(projectPath, "android", "build.gradle.kts")) {
		return filepath.Join(projectPath, "android"), true
	}
	return "", false
}

// hasSettingsGradle checks for settings.gradle or settings.gradle.kts
func hasSettingsGradle(androidDir string) bool {
	return fileExists(filepath.Join(androidDir, "settings.gradle")) ||
		fileExists(filepath.Join(androidDir, "settings.gradle.kts"))
}

// hasAppBuildGradle checks for app/build.gradle or app/build.gradle.kts
func hasAppBuildGradle(androidDir string) bool {
	return fileExists(filepath.Join(androidDir, "app", "build.gradle")) ||
		fileExists(filepath.Join(androidDir, "app", "build.gradle.kts"))
}

// findManifest searches for AndroidManifest.xml up to 5 levels deep
func findManifest(projectPath string) bool {
	found := false
	_ = filepath.Walk(projectPath, func(path string, info os.FileInfo, err error) error {
		if err != nil || found {
			return filepath.SkipDir
		}
		rel, _ := filepath.Rel(projectPath, path)
		depth := strings.Count(rel, string(filepath.Separator))
		if depth > 5 {
			return filepath.SkipDir
		}
		if !info.IsDir() && info.Name() == "AndroidManifest.xml" {
			found = true
			return filepath.SkipDir
		}
		return nil
	})
	return found
}

// hasGradlew checks for gradlew in root or android directory
func hasGradlew(projectPath, androidDir string) bool {
	return fileExists(filepath.Join(projectPath, "gradlew")) ||
		(androidDir != "" && fileExists(filepath.Join(androidDir, "gradlew")))
}

// hasAndroidPlugin checks for com.android plugin in build files
func hasAndroidPlugin(androidDir string) bool {
	buildFiles := []string{
		filepath.Join(androidDir, "build.gradle"),
		filepath.Join(androidDir, "build.gradle.kts"),
		filepath.Join(androidDir, "app", "build.gradle"),
		filepath.Join(androidDir, "app", "build.gradle.kts"),
	}
	for _, buildFile := range buildFiles {
		if data, err := os.ReadFile(buildFile); err == nil {
			if strings.Contains(string(data), "com.android") {
				return true
			}
		}
	}
	return false
}

// fileExists checks if a file exists
func fileExists(path string) bool {
	if info, err := os.Stat(path); err == nil && !info.IsDir() {
		return true
	}
	return false
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
