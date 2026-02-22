package container

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// VolumeMount represents a Docker volume mount.
type VolumeMount struct {
	Type        string // "bind" or "volume"
	Source      string // host path or volume name
	Target      string // container path
	ReadOnly    bool
	CreateHost  bool // whether to create host directory if it doesn't exist
}

// EnsureVolume ensures a Docker volume exists, creating it if necessary.
func (c *Client) EnsureVolume(ctx context.Context, volumeName string) error {
	exists, err := c.VolumeExists(ctx, volumeName)
	if err != nil {
		return fmt.Errorf("failed to check volume: %w", err)
	}

	if !exists {
		if err := c.CreateVolume(ctx, volumeName); err != nil {
			return fmt.Errorf("failed to create volume: %w", err)
		}
	}

	return nil
}

// PrepareVolumeMounts prepares volume mounts, creating host directories as needed.
func PrepareVolumeMounts(mounts []VolumeMount) error {
	for _, mount := range mounts {
		if mount.Type == "bind" && mount.CreateHost {
			// Expand home directory if needed
			source := expandPath(mount.Source)

			// Create directory if it doesn't exist
			if err := os.MkdirAll(source, 0755); err != nil {
				return fmt.Errorf("failed to create bind mount directory %s: %w", source, err)
			}
		}
	}

	return nil
}

// ToDockerFormat converts volume mounts to Docker CLI format (e.g., "source:target" or "source:target:ro").
func ToDockerFormat(mounts []VolumeMount) []string {
	var result []string

	for _, mount := range mounts {
		source := mount.Source
		if mount.Type == "bind" {
			source = expandPath(source)
		}

		volumeSpec := fmt.Sprintf("%s:%s", source, mount.Target)
		if mount.ReadOnly {
			volumeSpec += ":ro"
		}

		result = append(result, volumeSpec)
	}

	return result
}

// expandPath expands ~ to home directory in paths.
func expandPath(path string) string {
	if strings.HasPrefix(path, "~/") {
		home, err := os.UserHomeDir()
		if err != nil {
			return path
		}
		return filepath.Join(home, path[2:])
	}

	if path == "~" {
		home, err := os.UserHomeDir()
		if err != nil {
			return path
		}
		return home
	}

	return path
}

// BuildCommonVolumes builds the common volume mounts needed for all containers.
func BuildCommonVolumes(worktreePath, hash string) []VolumeMount {
	home, _ := os.UserHomeDir()

	// Session directory for this specific project
	sessionPath := filepath.Join(home, ".claude", "projects", sanitizePath(worktreePath))

	return []VolumeMount{
		// Workspace bind mount
		{
			Type:       "bind",
			Source:     worktreePath,
			Target:     "/workspace",
			CreateHost: false,
		},
		// Claude config directory
		{
			Type:       "bind",
			Source:     filepath.Join(home, ".claude"),
			Target:     "/home/claude/.claude",
			CreateHost: true,
		},
		// Project-specific session directory
		{
			Type:       "bind",
			Source:     sessionPath,
			Target:     "/home/claude/.claude/projects/-workspace",
			CreateHost: true,
		},
	}
}

// AddStrategyVolumes adds strategy-specific volumes to the mount list.
func AddStrategyVolumes(mounts []VolumeMount, strategyVolumes []VolumeMount) []VolumeMount {
	return append(mounts, strategyVolumes...)
}

// sanitizePath converts a path to a safe directory name.
// Replaces slashes with dashes to create flat namespace.
func sanitizePath(path string) string {
	// Remove leading/trailing slashes
	path = strings.Trim(path, "/")

	// Replace slashes with dashes
	return strings.ReplaceAll(path, "/", "-")
}
