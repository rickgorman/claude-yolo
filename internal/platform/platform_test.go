package platform

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

// TestHomeDirectory verifies home directory detection works on all platforms.
func TestHomeDirectory(t *testing.T) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		t.Fatalf("Failed to get home directory: %v", err)
	}

	if homeDir == "" {
		t.Error("Home directory is empty")
	}

	// Verify it's an absolute path
	if !filepath.IsAbs(homeDir) {
		t.Errorf("Home directory is not absolute: %s", homeDir)
	}

	// Verify it exists
	if _, err := os.Stat(homeDir); os.IsNotExist(err) {
		t.Errorf("Home directory does not exist: %s", homeDir)
	}
}

// TestFilePathOperations verifies filepath operations work correctly.
func TestFilePathOperations(t *testing.T) {
	tests := []struct {
		name     string
		parts    []string
		wantUnix string
	}{
		{
			name:     "simple join",
			parts:    []string{"home", "user", "file.txt"},
			wantUnix: "home/user/file.txt",
		},
		{
			name:     "with dots",
			parts:    []string{"home", "..", "other", "file.txt"},
			wantUnix: "home/../other/file.txt",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := filepath.Join(tt.parts...)

			// On Unix systems, should match expected
			if runtime.GOOS != "windows" {
				if result != tt.wantUnix {
					t.Errorf("filepath.Join() = %v, want %v", result, tt.wantUnix)
				}
			}

			// Result should not be empty
			if result == "" {
				t.Error("filepath.Join() returned empty string")
			}
		})
	}
}

// TestTempDirectory verifies temp directory creation works.
func TestTempDirectory(t *testing.T) {
	tmpDir := t.TempDir()

	// Verify it exists
	if _, err := os.Stat(tmpDir); os.IsNotExist(err) {
		t.Errorf("Temp directory does not exist: %s", tmpDir)
	}

	// Verify we can write to it
	testFile := filepath.Join(tmpDir, "test.txt")
	if err := os.WriteFile(testFile, []byte("test"), 0644); err != nil {
		t.Errorf("Failed to write to temp directory: %v", err)
	}

	// Verify we can read from it
	content, err := os.ReadFile(testFile)
	if err != nil {
		t.Errorf("Failed to read from temp directory: %v", err)
	}

	if string(content) != "test" {
		t.Errorf("Read incorrect content: got %q, want %q", string(content), "test")
	}
}

// TestEnvironmentVariables verifies env var operations work.
func TestEnvironmentVariables(t *testing.T) {
	testKey := "CLAUDE_YOLO_TEST_VAR"
	testValue := "test_value_123"

	// Set env var
	if err := os.Setenv(testKey, testValue); err != nil {
		t.Fatalf("Failed to set environment variable: %v", err)
	}
	defer os.Unsetenv(testKey)

	// Get env var
	got := os.Getenv(testKey)
	if got != testValue {
		t.Errorf("os.Getenv() = %v, want %v", got, testValue)
	}

	// Verify case sensitivity (should be case-sensitive on all supported platforms)
	wrongCase := os.Getenv("claude_yolo_test_var")
	if wrongCase == testValue {
		t.Error("Environment variables should be case-sensitive")
	}
}

// TestFilePermissions verifies file permission handling.
func TestFilePermissions(t *testing.T) {
	tmpDir := t.TempDir()
	testFile := filepath.Join(tmpDir, "test.txt")

	// Create file with specific permissions
	if err := os.WriteFile(testFile, []byte("test"), 0600); err != nil {
		t.Fatalf("Failed to create file: %v", err)
	}

	// Verify permissions
	info, err := os.Stat(testFile)
	if err != nil {
		t.Fatalf("Failed to stat file: %v", err)
	}

	mode := info.Mode().Perm()
	expectedMode := os.FileMode(0600)

	if mode != expectedMode {
		t.Errorf("File mode = %o, want %o", mode, expectedMode)
	}
}

// TestExecutablePermissions verifies executable detection.
func TestExecutablePermissions(t *testing.T) {
	tmpDir := t.TempDir()
	scriptFile := filepath.Join(tmpDir, "script.sh")

	// Create executable file
	content := []byte("#!/bin/bash\necho 'test'\n")
	if err := os.WriteFile(scriptFile, content, 0755); err != nil {
		t.Fatalf("Failed to create script: %v", err)
	}

	// Verify it's executable (on Unix systems)
	info, err := os.Stat(scriptFile)
	if err != nil {
		t.Fatalf("Failed to stat script: %v", err)
	}

	if runtime.GOOS != "windows" {
		mode := info.Mode()
		if mode&0111 == 0 {
			t.Error("Script is not executable")
		}
	}
}

// TestPlatformDetection verifies runtime platform detection.
func TestPlatformDetection(t *testing.T) {
	goos := runtime.GOOS
	goarch := runtime.GOARCH

	// Verify GOOS is one of our supported platforms
	supported := map[string]bool{
		"linux":  true,
		"darwin": true,
	}

	if !supported[goos] {
		t.Logf("Warning: Running on unsupported platform: %s", goos)
	}

	// Verify GOARCH is one of our supported architectures
	supportedArch := map[string]bool{
		"amd64": true,
		"arm64": true,
	}

	if !supportedArch[goarch] {
		t.Logf("Warning: Running on unsupported architecture: %s", goarch)
	}

	t.Logf("Platform: %s/%s", goos, goarch)
}

// TestAbsolutePath verifies absolute path handling.
func TestAbsolutePath(t *testing.T) {
	tests := []struct {
		name     string
		path     string
		wantAbs  bool
		platform string
	}{
		{
			name:     "unix absolute",
			path:     "/home/user/file.txt",
			wantAbs:  true,
			platform: "unix",
		},
		{
			name:     "unix relative",
			path:     "home/user/file.txt",
			wantAbs:  false,
			platform: "unix",
		},
		{
			name:     "unix dot relative",
			path:     "./file.txt",
			wantAbs:  false,
			platform: "unix",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Skip Windows-specific tests on Unix
			if tt.platform == "windows" && runtime.GOOS != "windows" {
				t.Skip("Skipping Windows-specific test")
			}

			// Skip Unix-specific tests on Windows
			if tt.platform == "unix" && runtime.GOOS == "windows" {
				t.Skip("Skipping Unix-specific test")
			}

			got := filepath.IsAbs(tt.path)
			if got != tt.wantAbs {
				t.Errorf("filepath.IsAbs(%q) = %v, want %v", tt.path, got, tt.wantAbs)
			}
		})
	}
}

// TestPathCleaning verifies path cleaning works correctly.
func TestPathCleaning(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		wantUnix string
	}{
		{
			name:     "removes double slashes",
			input:    "home//user//file.txt",
			wantUnix: "home/user/file.txt",
		},
		{
			name:     "resolves dot",
			input:    "home/./user/file.txt",
			wantUnix: "home/user/file.txt",
		},
		{
			name:     "resolves dot-dot",
			input:    "home/user/../other/file.txt",
			wantUnix: "home/other/file.txt",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := filepath.Clean(tt.input)

			if runtime.GOOS != "windows" {
				if result != tt.wantUnix {
					t.Errorf("filepath.Clean(%q) = %v, want %v", tt.input, result, tt.wantUnix)
				}
			}
		})
	}
}
