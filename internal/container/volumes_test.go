package container

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestExpandPath(t *testing.T) {
	home, _ := os.UserHomeDir()

	tests := []struct {
		name  string
		input string
		want  string
	}{
		{"home dir", "~", home},
		{"home subdir", "~/test", filepath.Join(home, "test")},
		{"absolute path", "/tmp/test", "/tmp/test"},
		{"relative path", "test", "test"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := expandPath(tt.input)
			if got != tt.want {
				t.Errorf("expandPath(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}

func TestSanitizePath(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"/home/user/project", "home-user-project"},
		{"home/user/project", "home-user-project"},
		{"/project/", "project"},
		{"test", "test"},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			got := sanitizePath(tt.input)
			if got != tt.want {
				t.Errorf("sanitizePath(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}

func TestToDockerFormat(t *testing.T) {
	home, _ := os.UserHomeDir()

	mounts := []VolumeMount{
		{Type: "bind", Source: "/tmp/test", Target: "/workspace"},
		{Type: "volume", Source: "my-volume", Target: "/data"},
		{Type: "bind", Source: "~/config", Target: "/config", ReadOnly: true},
	}

	result := ToDockerFormat(mounts)

	if len(result) != 3 {
		t.Fatalf("Expected 3 volume specs, got %d", len(result))
	}

	if result[0] != "/tmp/test:/workspace" {
		t.Errorf("Expected '/tmp/test:/workspace', got %q", result[0])
	}

	if result[1] != "my-volume:/data" {
		t.Errorf("Expected 'my-volume:/data', got %q", result[1])
	}

	expectedConfig := filepath.Join(home, "config") + ":/config:ro"
	if result[2] != expectedConfig {
		t.Errorf("Expected %q, got %q", expectedConfig, result[2])
	}
}

func TestBuildCommonVolumes(t *testing.T) {
	home, _ := os.UserHomeDir()
	worktreePath := "/home/user/project"
	hash := "abc123"

	volumes := BuildCommonVolumes(worktreePath, hash)

	if len(volumes) != 3 {
		t.Fatalf("Expected 3 volumes, got %d", len(volumes))
	}

	// Check workspace mount
	if volumes[0].Source != worktreePath || volumes[0].Target != "/workspace" {
		t.Errorf("Unexpected workspace mount: %+v", volumes[0])
	}

	// Check claude config mount
	expectedClaudeSource := filepath.Join(home, ".claude")
	if volumes[1].Source != expectedClaudeSource || volumes[1].Target != "/home/claude/.claude" {
		t.Errorf("Unexpected claude config mount: %+v", volumes[1])
	}

	// Check session mount
	if !strings.Contains(volumes[2].Source, ".claude/projects") {
		t.Errorf("Session mount should contain .claude/projects: %+v", volumes[2])
	}
	if volumes[2].Target != "/home/claude/.claude/projects/-workspace" {
		t.Errorf("Unexpected session mount target: %+v", volumes[2])
	}
}

func TestAddStrategyVolumes(t *testing.T) {
	commonVolumes := []VolumeMount{
		{Type: "bind", Source: "/workspace", Target: "/workspace"},
	}

	strategyVolumes := []VolumeMount{
		{Type: "volume", Source: "node-modules", Target: "/workspace/node_modules"},
	}

	result := AddStrategyVolumes(commonVolumes, strategyVolumes)

	if len(result) != 2 {
		t.Fatalf("Expected 2 volumes, got %d", len(result))
	}

	if result[0].Source != "/workspace" {
		t.Errorf("First volume should be common volume")
	}

	if result[1].Source != "node-modules" {
		t.Errorf("Second volume should be strategy volume")
	}
}
