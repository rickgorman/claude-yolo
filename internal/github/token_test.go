package github

import (
	"os"
	"path/filepath"
	"testing"
)

func TestFindToken(t *testing.T) {
	// Save original env vars
	origGHToken := os.Getenv("GH_TOKEN")
	origGitHubToken := os.Getenv("GITHUB_TOKEN")
	origXDGConfig := os.Getenv("XDG_CONFIG_HOME")
	defer func() {
		setOrUnset("GH_TOKEN", origGHToken)
		setOrUnset("GITHUB_TOKEN", origGitHubToken)
		setOrUnset("XDG_CONFIG_HOME", origXDGConfig)
	}()

	t.Run("finds GH_TOKEN env var", func(t *testing.T) {
		os.Setenv("GH_TOKEN", "ghp_from_env")
		os.Unsetenv("GITHUB_TOKEN")

		result, err := FindToken("/tmp/test")
		if err != nil {
			t.Fatalf("FindToken() error = %v", err)
		}
		if result.Token != "ghp_from_env" {
			t.Errorf("FindToken() token = %q, want %q", result.Token, "ghp_from_env")
		}
		if result.Source != "GH_TOKEN env var" {
			t.Errorf("FindToken() source = %q, want %q", result.Source, "GH_TOKEN env var")
		}
	})

	t.Run("finds GITHUB_TOKEN env var", func(t *testing.T) {
		os.Unsetenv("GH_TOKEN")
		os.Setenv("GITHUB_TOKEN", "ghp_from_github_token")

		result, err := FindToken("/tmp/test")
		if err != nil {
			t.Fatalf("FindToken() error = %v", err)
		}
		if result.Token != "ghp_from_github_token" {
			t.Errorf("FindToken() token = %q, want %q", result.Token, "ghp_from_github_token")
		}
		if result.Source != "GITHUB_TOKEN env var" {
			t.Errorf("FindToken() source = %q, want %q", result.Source, "GITHUB_TOKEN env var")
		}
	})

	t.Run("prefers GH_TOKEN over GITHUB_TOKEN", func(t *testing.T) {
		os.Setenv("GH_TOKEN", "ghp_from_gh_token")
		os.Setenv("GITHUB_TOKEN", "ghp_from_github_token")

		result, err := FindToken("/tmp/test")
		if err != nil {
			t.Fatalf("FindToken() error = %v", err)
		}
		if result.Token != "ghp_from_gh_token" {
			t.Errorf("FindToken() should prefer GH_TOKEN, got %q", result.Token)
		}
	})

	t.Run("finds token in project .env", func(t *testing.T) {
		os.Unsetenv("GH_TOKEN")
		os.Unsetenv("GITHUB_TOKEN")

		tmpDir := t.TempDir()
		envFile := filepath.Join(tmpDir, ".env")
		err := os.WriteFile(envFile, []byte("GH_TOKEN=ghp_from_project_env"), 0644)
		if err != nil {
			t.Fatalf("Failed to create test .env: %v", err)
		}

		result, err := FindToken(tmpDir)
		if err != nil {
			t.Fatalf("FindToken() error = %v", err)
		}
		if result.Token != "ghp_from_project_env" {
			t.Errorf("FindToken() token = %q, want %q", result.Token, "ghp_from_project_env")
		}
		if result.Source != envFile {
			t.Errorf("FindToken() source = %q, want %q", result.Source, envFile)
		}
	})

	t.Run("finds token in home .env", func(t *testing.T) {
		os.Unsetenv("GH_TOKEN")
		os.Unsetenv("GITHUB_TOKEN")

		homeDir, err := os.UserHomeDir()
		if err != nil {
			t.Skip("Cannot get home directory")
		}

		homeEnv := filepath.Join(homeDir, ".env")
		tmpProjectDir := t.TempDir()

		// Create temporary home .env (cleanup after test)
		err = os.WriteFile(homeEnv, []byte("GH_TOKEN=ghp_from_home_env"), 0644)
		if err != nil {
			t.Skip("Cannot write to home .env")
		}
		defer os.Remove(homeEnv)

		result, err := FindToken(tmpProjectDir)
		if err != nil {
			t.Fatalf("FindToken() error = %v", err)
		}
		if result.Token != "ghp_from_home_env" {
			t.Errorf("FindToken() token = %q, want %q", result.Token, "ghp_from_home_env")
		}
		if result.Source != homeEnv {
			t.Errorf("FindToken() source = %q, want %q", result.Source, homeEnv)
		}
	})

	t.Run("returns error when no token found", func(t *testing.T) {
		os.Unsetenv("GH_TOKEN")
		os.Unsetenv("GITHUB_TOKEN")

		tmpDir := t.TempDir()

		_, err := FindToken(tmpDir)
		if err == nil {
			t.Error("FindToken() expected error when no token found, got nil")
		}
	})
}

func TestParseGHHostsYAML(t *testing.T) {
	tests := []struct {
		name    string
		content string
		want    string
	}{
		{
			name: "simple oauth_token",
			content: `github.com:
    oauth_token: ghp_test123
    user: testuser`,
			want: "ghp_test123",
		},
		{
			name: "with extra whitespace",
			content: `github.com:
    oauth_token:    ghp_test456
    user: testuser`,
			want: "ghp_test456",
		},
		{
			name: "multiple hosts",
			content: `github.com:
    oauth_token: ghp_first
    user: user1
enterprise.github.com:
    oauth_token: ghp_second
    user: user2`,
			want: "ghp_first",
		},
		{
			name: "no oauth_token",
			content: `github.com:
    user: testuser`,
			want: "",
		},
		{
			name:    "empty file",
			content: "",
			want:    "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tmpDir := t.TempDir()
			hostsFile := filepath.Join(tmpDir, "hosts.yml")

			err := os.WriteFile(hostsFile, []byte(tt.content), 0644)
			if err != nil {
				t.Fatalf("Failed to create test file: %v", err)
			}

			got, err := parseGHHostsYAML(hostsFile)
			if err != nil {
				t.Fatalf("parseGHHostsYAML() error = %v", err)
			}
			if got != tt.want {
				t.Errorf("parseGHHostsYAML() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestGetGHConfigPath(t *testing.T) {
	origXDGConfig := os.Getenv("XDG_CONFIG_HOME")
	defer setOrUnset("XDG_CONFIG_HOME", origXDGConfig)

	t.Run("uses XDG_CONFIG_HOME when set", func(t *testing.T) {
		os.Setenv("XDG_CONFIG_HOME", "/custom/config")
		got := getGHConfigPath()
		want := "/custom/config/gh/hosts.yml"
		if got != want {
			t.Errorf("getGHConfigPath() = %q, want %q", got, want)
		}
	})

	t.Run("falls back to ~/.config when XDG_CONFIG_HOME not set", func(t *testing.T) {
		os.Unsetenv("XDG_CONFIG_HOME")
		got := getGHConfigPath()
		homeDir, _ := os.UserHomeDir()
		want := filepath.Join(homeDir, ".config", "gh", "hosts.yml")
		if got != want {
			t.Errorf("getGHConfigPath() = %q, want %q", got, want)
		}
	})
}

// Helper function to set or unset environment variables
func setOrUnset(key, value string) {
	if value == "" {
		os.Unsetenv(key)
	} else {
		os.Setenv(key, value)
	}
}
