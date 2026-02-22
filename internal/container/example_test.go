package container_test

import (
	"context"
	"fmt"
	"log"
	"runtime"

	"github.com/rickgorman/claude-yolo/internal/container"
)

// ExampleClient_Run demonstrates creating and running a container.
func ExampleClient_Run() {
	ctx := context.Background()

	client, err := container.NewClient()
	if err != nil {
		log.Fatal(err)
	}
	defer client.Close()

	// Configure the container
	cfg := container.RunConfig{
		Name:     "my-container",
		Image:    "ubuntu",
		WorkDir:  "/workspace",
		Platform: "linux/amd64",
		Env: []string{
			"MY_VAR=value",
		},
		Volumes: []string{
			"/tmp/workspace:/workspace",
			"my-volume:/data",
		},
		NetworkMode: "bridge",
		PortMappings: []container.PortMapping{
			{Host: 8080, Container: 80},
		},
		Interactive: true,
		TTY:         true,
	}

	containerID, err := client.Run(ctx, cfg)
	if err != nil {
		log.Fatal(err)
	}

	fmt.Printf("Container created: %s\n", containerID)
}

// ExampleResolvePortConflicts demonstrates port conflict resolution.
func ExampleResolvePortConflicts() {
	portMappings := []container.PortMapping{
		{Host: 3000, Container: 3000},
		{Host: 8080, Container: 80},
	}

	// Auto-remap mode (headless)
	resolved, err := container.ResolvePortConflicts(portMappings, true)
	if err != nil {
		log.Fatal(err)
	}

	for _, pm := range resolved {
		fmt.Printf("Port mapping: %d:%d\n", pm.Host, pm.Container)
	}
}

// ExampleBuildCommonVolumes demonstrates building volume mounts.
func ExampleBuildCommonVolumes() {
	worktreePath := "/home/user/my-project"
	hash := "abc123"

	volumes := container.BuildCommonVolumes(worktreePath, hash)

	for _, vol := range volumes {
		fmt.Printf("Mount: %s -> %s\n", vol.Source, vol.Target)
	}
}

// ExampleGetCDPHost demonstrates determining the Chrome CDP host.
func ExampleGetCDPHost() {
	// On macOS, we typically don't use host networking
	useHostNetwork := runtime.GOOS != "darwin"

	cdpHost := container.GetCDPHost(useHostNetwork)
	fmt.Printf("Chrome CDP URL: http://%s:9222\n", cdpHost)
}

// ExampleClient_Uptime demonstrates getting container uptime.
func ExampleClient_Uptime() {
	ctx := context.Background()

	client, err := container.NewClient()
	if err != nil {
		log.Fatal(err)
	}
	defer client.Close()

	uptime, err := client.Uptime(ctx, "my-container")
	if err != nil {
		log.Fatal(err)
	}

	fmt.Printf("Container uptime: %s\n", uptime)
}

// ExampleParsePortMapping demonstrates parsing port mapping strings.
func ExampleParsePortMapping() {
	// Parse a host:container mapping
	pm1, err := container.ParsePortMapping("8080:80")
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Mapping: %d:%d\n", pm1.Host, pm1.Container)

	// Parse a single port (same for both)
	pm2, err := container.ParsePortMapping("3000")
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Mapping: %d:%d\n", pm2.Host, pm2.Container)

	// Output:
	// Mapping: 8080:80
	// Mapping: 3000:3000
}

// ExampleShouldUseHostNetwork demonstrates network mode selection.
func ExampleShouldUseHostNetwork() {
	// No port mappings - use host network on Linux
	noPortMappings := []container.PortMapping{}
	fmt.Printf("Use host network (no ports): %v\n", container.ShouldUseHostNetwork(noPortMappings))

	// With port mappings - use bridge network
	withPorts := []container.PortMapping{{Host: 3000, Container: 3000}}
	fmt.Printf("Use host network (with ports): %v\n", container.ShouldUseHostNetwork(withPorts))

	// Output varies by platform:
	// On Linux with no ports: true
	// On macOS: always false
}
