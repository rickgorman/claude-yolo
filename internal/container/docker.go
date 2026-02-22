// Package container handles Docker operations, port conflict resolution, and volume management.
package container

import (
	"context"
	"io"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/api/types/image"
	"github.com/docker/docker/client"
)

// Client wraps the Docker client with our operations.
type Client struct {
	cli *client.Client
}

// NewClient creates a new Docker client wrapper.
func NewClient() (*Client, error) {
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		return nil, err
	}
	return &Client{cli: cli}, nil
}

// Close closes the underlying Docker client.
func (c *Client) Close() error {
	return c.cli.Close()
}

// ImageExists checks if an image exists locally.
func (c *Client) ImageExists(ctx context.Context, imageName string) (bool, error) {
	_, _, err := c.cli.ImageInspectWithRaw(ctx, imageName+":latest")
	if err != nil {
		if client.IsErrNotFound(err) {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

// ImageAge returns the age of an image in days.
func (c *Client) ImageAge(ctx context.Context, imageName string) (int, error) {
	inspect, _, err := c.cli.ImageInspectWithRaw(ctx, imageName+":latest")
	if err != nil {
		return 0, err
	}

	created, err := parseDockerTimestamp(inspect.Created)
	if err != nil {
		return 0, err
	}

	return daysSince(created), nil
}

// BuildImage builds a Docker image.
func (c *Client) BuildImage(ctx context.Context, buildContext io.Reader, opts types.ImageBuildOptions) error {
	resp, err := c.cli.ImageBuild(ctx, buildContext, opts)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	// Stream build output to stdout
	_, err = io.Copy(io.Discard, resp.Body)
	return err
}

// FindRunningContainer finds a running container by name prefix.
func (c *Client) FindRunningContainer(ctx context.Context, namePrefix string) (string, error) {
	containers, err := c.cli.ContainerList(ctx, container.ListOptions{})
	if err != nil {
		return "", err
	}

	for _, ctr := range containers {
		for _, name := range ctr.Names {
			// Docker container names start with "/"
			if len(name) > 0 && name[0] == '/' {
				name = name[1:]
			}
			if matchesPrefix(name, namePrefix) {
				return name, nil
			}
		}
	}

	return "", nil
}

// FindStoppedContainer finds a stopped container by name prefix.
func (c *Client) FindStoppedContainer(ctx context.Context, namePrefix string) (string, error) {
	containers, err := c.cli.ContainerList(ctx, container.ListOptions{
		All: true,
		Filters: mustNewFilter(map[string][]string{
			"status": {"exited"},
		}),
	})
	if err != nil {
		return "", err
	}

	for _, ctr := range containers {
		for _, name := range ctr.Names {
			// Docker container names start with "/"
			if len(name) > 0 && name[0] == '/' {
				name = name[1:]
			}
			if matchesPrefix(name, namePrefix) {
				return name, nil
			}
		}
	}

	return "", nil
}

// RemoveImage removes a Docker image.
func (c *Client) RemoveImage(ctx context.Context, imageName string) error {
	_, err := c.cli.ImageRemove(ctx, imageName+":latest", image.RemoveOptions{Force: true})
	return err
}

// VolumeExists checks if a volume exists.
func (c *Client) VolumeExists(ctx context.Context, volumeName string) (bool, error) {
	_, err := c.cli.VolumeInspect(ctx, volumeName)
	if err != nil {
		if client.IsErrNotFound(err) {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

// CreateVolume creates a Docker volume.
func (c *Client) CreateVolume(ctx context.Context, volumeName string) error {
	_, err := c.cli.VolumeCreate(ctx, volumeCreateBody(volumeName))
	return err
}
