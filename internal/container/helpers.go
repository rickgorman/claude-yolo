package container

import (
	"fmt"
	"strings"
	"time"

	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/api/types/filters"
	"github.com/docker/docker/api/types/mount"
	"github.com/docker/docker/api/types/volume"
	"github.com/docker/docker/client"
	"github.com/docker/go-connections/nat"
)

// buildContainerConfig creates a container.Config from RunConfig.
func buildContainerConfig(cfg RunConfig) *container.Config {
	config := &container.Config{
		Image:      cfg.Image + ":latest",
		WorkingDir: cfg.WorkDir,
		Env:        cfg.Env,
		Tty:        cfg.TTY,
		OpenStdin:  cfg.Interactive,
		StdinOnce:  cfg.Interactive,
	}

	// Add exposed ports for port mappings
	if len(cfg.PortMappings) > 0 {
		exposedPorts := make(nat.PortSet)
		for _, pm := range cfg.PortMappings {
			port := nat.Port(fmt.Sprintf("%d/tcp", pm.Container))
			exposedPorts[port] = struct{}{}
		}
		config.ExposedPorts = exposedPorts
	}

	return config
}

// buildHostConfig creates a container.HostConfig from RunConfig.
func buildHostConfig(cfg RunConfig) *container.HostConfig {
	hostConfig := &container.HostConfig{
		AutoRemove: cfg.AutoRemove,
	}

	// Set network mode
	if cfg.NetworkMode != "" {
		hostConfig.NetworkMode = container.NetworkMode(cfg.NetworkMode)
	}

	// Add port mappings
	if len(cfg.PortMappings) > 0 {
		portBindings := make(nat.PortMap)
		for _, pm := range cfg.PortMappings {
			containerPort := nat.Port(fmt.Sprintf("%d/tcp", pm.Container))
			portBindings[containerPort] = []nat.PortBinding{
				{
					HostIP:   "0.0.0.0",
					HostPort: fmt.Sprintf("%d", pm.Host),
				},
			}
		}
		hostConfig.PortBindings = portBindings
	}

	// Add volume mounts
	if len(cfg.Volumes) > 0 {
		mounts := make([]mount.Mount, 0, len(cfg.Volumes))
		for _, v := range cfg.Volumes {
			parts := strings.Split(v, ":")
			if len(parts) >= 2 {
				mountType := mount.TypeBind
				source := parts[0]

				// Check if it's a named volume (doesn't start with / or ~)
				if !strings.HasPrefix(source, "/") && !strings.HasPrefix(source, "~") {
					mountType = mount.TypeVolume
				}

				m := mount.Mount{
					Type:   mountType,
					Source: source,
					Target: parts[1],
				}

				// Check for :ro suffix
				if len(parts) == 3 && parts[2] == "ro" {
					m.ReadOnly = true
				}

				mounts = append(mounts, m)
			}
		}
		hostConfig.Mounts = mounts
	}

	// Set restart policy
	if cfg.RestartPolicy != "" {
		hostConfig.RestartPolicy = container.RestartPolicy{
			Name: container.RestartPolicyMode(cfg.RestartPolicy),
		}
	}

	// Note: Platform is handled via docker.Client PlatformOptions, not HostConfig
	// The Platform field in RunConfig is for reference/documentation

	return hostConfig
}

// volumeCreateBody creates a volume.CreateOptions.
func volumeCreateBody(name string) volume.CreateOptions {
	return volume.CreateOptions{
		Name:   name,
		Driver: "local",
	}
}

// mustNewFilter creates a filter args, panicking on error (should never happen).
func mustNewFilter(kv map[string][]string) filters.Args {
	f := filters.NewArgs()
	for k, values := range kv {
		for _, v := range values {
			f.Add(k, v)
		}
	}
	return f
}

// matchesPrefix checks if a container name matches the expected prefix pattern.
func matchesPrefix(name, prefix string) bool {
	return strings.HasPrefix(name, prefix)
}

// isNotFoundError checks if an error is a "not found" error from Docker.
func isNotFoundError(err error) bool {
	return client.IsErrNotFound(err)
}

// parseDockerTimestamp parses a Docker timestamp string.
func parseDockerTimestamp(ts string) (time.Time, error) {
	// Docker timestamps are in RFC3339Nano format
	return time.Parse(time.RFC3339Nano, ts)
}

// daysSince calculates the number of days since a given time.
func daysSince(t time.Time) int {
	duration := time.Since(t)
	return int(duration.Hours() / 24)
}
