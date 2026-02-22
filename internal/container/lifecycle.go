package container

import (
	"context"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/pkg/stdcopy"
)

// RunConfig holds the configuration for running a container.
type RunConfig struct {
	Name          string
	Image         string
	WorkDir       string
	Platform      string
	Env           []string
	Volumes       []string
	NetworkMode   string
	PortMappings  []PortMapping
	Interactive   bool
	TTY           bool
	AutoRemove    bool
	RestartPolicy string
}

// PortMapping represents a port mapping.
type PortMapping struct {
	Host      int
	Container int
}

// Run creates and starts a new container.
func (c *Client) Run(ctx context.Context, cfg RunConfig) (string, error) {
	// Create container
	containerConfig := buildContainerConfig(cfg)
	hostConfig := buildHostConfig(cfg)

	resp, err := c.cli.ContainerCreate(
		ctx,
		containerConfig,
		hostConfig,
		nil,
		nil,
		cfg.Name,
	)
	if err != nil {
		return "", fmt.Errorf("failed to create container: %w", err)
	}

	// Start container
	if err := c.cli.ContainerStart(ctx, resp.ID, container.StartOptions{}); err != nil {
		return "", fmt.Errorf("failed to start container: %w", err)
	}

	return resp.ID, nil
}

// Attach attaches to a running container's stdin/stdout/stderr.
func (c *Client) Attach(ctx context.Context, containerID string, interactive bool) error {
	attachOptions := container.AttachOptions{
		Stream: true,
		Stdin:  interactive,
		Stdout: true,
		Stderr: true,
	}

	hijackedResp, err := c.cli.ContainerAttach(ctx, containerID, attachOptions)
	if err != nil {
		return fmt.Errorf("failed to attach to container: %w", err)
	}
	defer hijackedResp.Close()

	// Handle stdin if interactive
	if interactive {
		go func() {
			io.Copy(hijackedResp.Conn, os.Stdin)
		}()
	}

	// Stream stdout/stderr
	_, err = stdcopy.StdCopy(os.Stdout, os.Stderr, hijackedResp.Reader)
	return err
}

// Remove removes a container.
func (c *Client) Remove(ctx context.Context, nameOrID string, force bool) error {
	options := container.RemoveOptions{
		Force:         force,
		RemoveVolumes: false,
	}

	err := c.cli.ContainerRemove(ctx, nameOrID, options)
	if err != nil && !isNotFoundError(err) {
		return fmt.Errorf("failed to remove container: %w", err)
	}

	return nil
}

// Exists checks if a container exists (running or stopped).
func (c *Client) Exists(ctx context.Context, name string) (bool, error) {
	containers, err := c.cli.ContainerList(ctx, container.ListOptions{All: true})
	if err != nil {
		return false, err
	}

	for _, ctr := range containers {
		for _, ctrName := range ctr.Names {
			// Docker container names start with "/"
			if len(ctrName) > 0 && ctrName[0] == '/' {
				ctrName = ctrName[1:]
			}
			if ctrName == name {
				return true, nil
			}
		}
	}

	return false, nil
}

// IsRunning checks if a container is currently running.
func (c *Client) IsRunning(ctx context.Context, name string) (bool, error) {
	containers, err := c.cli.ContainerList(ctx, container.ListOptions{})
	if err != nil {
		return false, err
	}

	for _, ctr := range containers {
		for _, ctrName := range ctr.Names {
			// Docker container names start with "/"
			if len(ctrName) > 0 && ctrName[0] == '/' {
				ctrName = ctrName[1:]
			}
			if ctrName == name {
				return true, nil
			}
		}
	}

	return false, nil
}

// Uptime returns the uptime of a container as a human-readable string.
func (c *Client) Uptime(ctx context.Context, name string) (string, error) {
	inspect, err := c.cli.ContainerInspect(ctx, name)
	if err != nil {
		return "", fmt.Errorf("failed to inspect container: %w", err)
	}

	if !inspect.State.Running {
		return "", fmt.Errorf("container is not running")
	}

	startedAt, err := time.Parse(time.RFC3339Nano, inspect.State.StartedAt)
	if err != nil {
		return "", fmt.Errorf("failed to parse start time: %w", err)
	}

	return formatUptime(time.Since(startedAt)), nil
}

// formatUptime formats a duration into a human-readable uptime string.
func formatUptime(d time.Duration) string {
	hours := int(d.Hours())
	minutes := int(d.Minutes()) % 60

	if hours > 0 {
		return fmt.Sprintf("%dh %dm", hours, minutes)
	}
	return fmt.Sprintf("%dm", minutes)
}
