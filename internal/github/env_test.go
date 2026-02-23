package github

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseEnvFile(t *testing.T) {
	tests := []struct {
		name    string
		content string
		want    string
		wantErr bool
	}{
		{
			name:    "GH_TOKEN simple",
			content: "GH_TOKEN=ghp_test123",
			want:    "ghp_test123",
		},
		{
			name:    "GITHUB_TOKEN simple",
			content: "GITHUB_TOKEN=ghp_test456",
			want:    "ghp_test456",
		},
		{
			name:    "export GH_TOKEN",
			content: "export GH_TOKEN=ghp_export123",
			want:    "ghp_export123",
		},
		{
			name:    "GH_TOKEN with double quotes",
			content: `GH_TOKEN="ghp_quoted123"`,
			want:    "ghp_quoted123",
		},
		{
			name:    "GH_TOKEN with single quotes",
			content: `GH_TOKEN='ghp_singlequote123'`,
			want:    "ghp_singlequote123",
		},
		{
			name:    "export with quotes",
			content: `export GH_TOKEN="ghp_exportquoted123"`,
			want:    "ghp_exportquoted123",
		},
		{
			name: "multiple lines GH_TOKEN first",
			content: `# Comment
GH_TOKEN=ghp_first
GITHUB_TOKEN=ghp_second`,
			want: "ghp_first",
		},
		{
			name: "multiple lines GITHUB_TOKEN first",
			content: `# Comment
GITHUB_TOKEN=ghp_second
GH_TOKEN=ghp_first`,
			want: "ghp_second",
		},
		{
			name: "with comments and blank lines",
			content: `# This is a comment

GH_TOKEN=ghp_withcomments
# Another comment`,
			want: "ghp_withcomments",
		},
		{
			name: "empty file",
			content: `# Just comments
`,
			want: "",
		},
		{
			name:    "no token",
			content: "OTHER_VAR=value",
			want:    "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tmpDir := t.TempDir()
			envFile := filepath.Join(tmpDir, ".env")

			err := os.WriteFile(envFile, []byte(tt.content), 0644)
			if err != nil {
				t.Fatalf("Failed to create test file: %v", err)
			}

			got, err := parseEnvFile(envFile)
			if (err != nil) != tt.wantErr {
				t.Errorf("parseEnvFile() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if got != tt.want {
				t.Errorf("parseEnvFile() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestParseEnvFileNotExist(t *testing.T) {
	_, err := parseEnvFile("/nonexistent/path/.env")
	if err == nil {
		t.Error("parseEnvFile() expected error for nonexistent file, got nil")
	}
}

func TestExtractTokenFromLine(t *testing.T) {
	tests := []struct {
		name string
		line string
		key  string
		want string
	}{
		{
			name: "simple GH_TOKEN",
			line: "GH_TOKEN=ghp_test",
			key:  "GH_TOKEN",
			want: "ghp_test",
		},
		{
			name: "simple GITHUB_TOKEN",
			line: "GITHUB_TOKEN=ghp_test",
			key:  "GITHUB_TOKEN",
			want: "ghp_test",
		},
		{
			name: "export prefix",
			line: "export GH_TOKEN=ghp_test",
			key:  "GH_TOKEN",
			want: "ghp_test",
		},
		{
			name: "double quotes",
			line: `GH_TOKEN="ghp_test"`,
			key:  "GH_TOKEN",
			want: "ghp_test",
		},
		{
			name: "single quotes",
			line: `GH_TOKEN='ghp_test'`,
			key:  "GH_TOKEN",
			want: "ghp_test",
		},
		{
			name: "export with quotes",
			line: `export GH_TOKEN="ghp_test"`,
			key:  "GH_TOKEN",
			want: "ghp_test",
		},
		{
			name: "wrong key",
			line: "OTHER_TOKEN=value",
			key:  "GH_TOKEN",
			want: "",
		},
		{
			name: "empty value",
			line: "GH_TOKEN=",
			key:  "GH_TOKEN",
			want: "",
		},
		{
			name: "whitespace around value",
			line: "GH_TOKEN=  ghp_test  ",
			key:  "GH_TOKEN",
			want: "ghp_test",
		},
		{
			name: "export with whitespace",
			line: "export   GH_TOKEN  =  ghp_test  ",
			key:  "GH_TOKEN",
			want: "ghp_test",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := extractTokenFromLine(tt.line, tt.key)
			if got != tt.want {
				t.Errorf("extractTokenFromLine(%q, %q) = %q, want %q", tt.line, tt.key, got, tt.want)
			}
		})
	}
}
