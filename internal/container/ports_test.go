package container

import (
	"testing"
)

func TestParsePortMapping(t *testing.T) {
	tests := []struct {
		input     string
		wantHost  int
		wantCont  int
		wantError bool
	}{
		{"3000:3000", 3000, 3000, false},
		{"8080:80", 8080, 80, false},
		{"3000", 3000, 3000, false},
		{"  5000:5000  ", 5000, 5000, false},
		{"invalid", 0, 0, true},
		{"3000:invalid", 0, 0, true},
		{"3000:3000:3000", 0, 0, true},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			got, err := ParsePortMapping(tt.input)

			if tt.wantError {
				if err == nil {
					t.Errorf("ParsePortMapping(%q) expected error, got nil", tt.input)
				}
				return
			}

			if err != nil {
				t.Errorf("ParsePortMapping(%q) unexpected error: %v", tt.input, err)
				return
			}

			if got.Host != tt.wantHost {
				t.Errorf("ParsePortMapping(%q) host = %d, want %d", tt.input, got.Host, tt.wantHost)
			}

			if got.Container != tt.wantCont {
				t.Errorf("ParsePortMapping(%q) container = %d, want %d", tt.input, got.Container, tt.wantCont)
			}
		})
	}
}

func TestGetCDPHost(t *testing.T) {
	tests := []struct {
		name           string
		useHostNetwork bool
		want           string
	}{
		{"host network", true, "localhost"},
		{"bridge network", false, "host.docker.internal"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := GetCDPHost(tt.useHostNetwork)
			if got != tt.want {
				t.Errorf("GetCDPHost(%v) = %q, want %q", tt.useHostNetwork, got, tt.want)
			}
		})
	}
}

func TestApplyPortRemapping(t *testing.T) {
	portMappings := []PortMapping{
		{Host: 3000, Container: 3000},
		{Host: 8080, Container: 80},
		{Host: 5000, Container: 5000},
	}

	conflicts := []PortConflict{
		{Port: 3000, Suggestion: 4000},
		{Port: 8080, Suggestion: 8081},
	}

	result := applyPortRemapping(portMappings, conflicts)

	if result[0].Host != 4000 {
		t.Errorf("Expected port 3000 to be remapped to 4000, got %d", result[0].Host)
	}

	if result[1].Host != 8081 {
		t.Errorf("Expected port 8080 to be remapped to 8081, got %d", result[1].Host)
	}

	if result[2].Host != 5000 {
		t.Errorf("Expected port 5000 to remain unchanged, got %d", result[2].Host)
	}
}
