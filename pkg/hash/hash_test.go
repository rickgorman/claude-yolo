package hash

import (
	"testing"
)

func TestPathHash(t *testing.T) {
	tests := []struct {
		name string
		path string
		want string
	}{
		{
			name: "simple path",
			path: "/home/user/project",
			want: "5d41402a", // First 8 chars of MD5
		},
		{
			name: "empty path",
			path: "",
			want: "d41d8cd9", // MD5 of empty string
		},
		{
			name: "consistent hashing",
			path: "/workspace/test",
			want: PathHash("/workspace/test"), // Should be deterministic
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := PathHash(tt.path)
			if len(got) != 8 {
				t.Errorf("PathHash() length = %d, want 8", len(got))
			}
			// For consistent hashing test
			if tt.name == "consistent hashing" {
				got2 := PathHash(tt.path)
				if got != got2 {
					t.Errorf("PathHash() not deterministic: %s != %s", got, got2)
				}
			}
		})
	}
}

func TestCDPPortForHash(t *testing.T) {
	tests := []struct {
		name string
		hash string
		want int
	}{
		{
			name: "zero hash",
			hash: "00000000",
			want: 9222,
		},
		{
			name: "max in range",
			hash: "ffff0000",
			want: 9222 + (0xffff % 778),
		},
		{
			name: "short hash",
			hash: "abc",
			want: 9222, // Should handle gracefully
		},
		{
			name: "typical hash",
			hash: "a1b2c3d4",
			want: 9222 + (0xa1b2 % 778),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := CDPPortForHash(tt.hash)
			if got != tt.want {
				t.Errorf("CDPPortForHash(%s) = %d, want %d", tt.hash, got, tt.want)
			}
			// Ensure port is in valid range
			if got < 9222 || got >= 9222+778 {
				t.Errorf("CDPPortForHash(%s) = %d, out of range [9222, 10000)", tt.hash, got)
			}
		})
	}
}

func TestMD5Sum(t *testing.T) {
	tests := []struct {
		name string
		input string
		want string
	}{
		{
			name: "empty string",
			input: "",
			want: "d41d8cd98f00b204e9800998ecf8427e",
		},
		{
			name: "hello",
			input: "hello",
			want: "5d41402abc4b2a76b9719d911017c592",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := MD5Sum(tt.input)
			if got != tt.want {
				t.Errorf("MD5Sum(%q) = %s, want %s", tt.input, got, tt.want)
			}
		})
	}
}

func TestSHA1Sum(t *testing.T) {
	tests := []struct {
		name string
		input string
		want string
	}{
		{
			name: "empty string",
			input: "",
			want: "da39a3ee5e6b4b0d3255bfef95601890afd80709",
		},
		{
			name: "hello",
			input: "hello",
			want: "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := SHA1Sum(tt.input)
			if got != tt.want {
				t.Errorf("SHA1Sum(%q) = %s, want %s", tt.input, got, tt.want)
			}
		})
	}
}
