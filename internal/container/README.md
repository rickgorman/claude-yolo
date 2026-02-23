# Container Package

The `container` package provides Docker operations, port conflict resolution, and volume management for the claude-yolo Go rewrite.

## Features

- **Docker Client Wrapper**: Simplified interface to Docker operations
- **Container Lifecycle**: Build, run, attach, remove, and inspect containers
- **Port Conflict Detection**: Automatic detection and resolution of port conflicts
- **Volume Management**: Bind mounts and named volumes with automatic directory creation
- **Platform Awareness**: macOS vs Linux networking differences

## Package Files

- `docker.go` - Docker client wrapper and basic operations
- `lifecycle.go` - Container lifecycle operations (run, attach, remove, exists, uptime)
- `ports.go` - Port conflict detection, resolution, and interactive prompts
- `volumes.go` - Volume mount management and preparation
- `helpers.go` - Internal utility functions

## Usage Examples

### Creating a Docker Client

```go
import "github.com/rickgorman/claude-yolo/internal/container"

client, err := container.NewClient()
if err != nil {
    log.Fatal(err)
}
defer client.Close()
```

### Running a Container

```go
cfg := container.RunConfig{
    Name:     "my-container",
    Image:    "ubuntu",
    WorkDir:  "/workspace",
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
```

### Port Conflict Resolution

```go
portMappings := []container.PortMapping{
    {Host: 3000, Container: 3000},
    {Host: 8080, Container: 80},
}

// Interactive mode (prompts user)
resolved, err := container.ResolvePortConflicts(portMappings, false)

// Auto-remap mode (headless)
resolved, err := container.ResolvePortConflicts(portMappings, true)
```

The port resolution logic:
1. Detects which ports are in use using `lsof`
2. Finds the process name and PID for conflicting ports
3. Suggests alternatives (base+1000 first, then base+1 to base+100)
4. In interactive mode: prompts user to remap or continue
5. In headless mode: auto-remaps if all ports have alternatives

### Volume Management

```go
// Build common volumes for all containers
volumes := container.BuildCommonVolumes("/home/user/project", "abc123")

// Add strategy-specific volumes
strategyVolumes := []container.VolumeMount{
    {Type: "volume", Source: "node-modules", Target: "/workspace/node_modules"},
}
volumes = container.AddStrategyVolumes(volumes, strategyVolumes)

// Prepare volumes (create host directories)
err := container.PrepareVolumeMounts(volumes)

// Convert to Docker format
dockerVolumes := container.ToDockerFormat(volumes)
```

### Container Lifecycle Operations

```go
// Check if container exists
exists, err := client.Exists(ctx, "my-container")

// Check if container is running
running, err := client.IsRunning(ctx, "my-container")

// Get container uptime
uptime, err := client.Uptime(ctx, "my-container")
fmt.Printf("Uptime: %s\n", uptime) // e.g., "2h 15m"

// Remove container
err := client.Remove(ctx, "my-container", true)
```

### Platform-Specific Networking

```go
// Determine if we should use --network=host
// Returns false on macOS (doesn't support host networking properly)
// Returns false if port mappings are specified
useHostNetwork := container.ShouldUseHostNetwork(portMappings)

// Get the appropriate Chrome CDP host
cdpHost := container.GetCDPHost(useHostNetwork)
// Returns "localhost" for host network
// Returns "host.docker.internal" for bridge network
```

### Image Operations

```go
// Check if image exists
exists, err := client.ImageExists(ctx, "my-image")

// Get image age in days
age, err := client.ImageAge(ctx, "my-image")
if age > 7 {
    fmt.Println("Image is stale, consider rebuilding")
}

// Remove image
err := client.RemoveImage(ctx, "my-image")
```

### Finding Containers

```go
// Find running container by name prefix
name, err := client.FindRunningContainer(ctx, "claude-yolo-abc123-")

// Find stopped container by name prefix
name, err := client.FindStoppedContainer(ctx, "claude-yolo-abc123-")
```

## Port Conflict Detection

The port conflict resolution uses `lsof` to detect listening ports and find process information:

```go
// Check if a port is in use
inUse := container.CheckPortInUse(3000)

// Find a free port (tries base+1000, then base+1..base+100)
freePort, found := container.FindFreePort(3000)
if found {
    fmt.Printf("Use port %d instead\n", freePort)
}

// Get detailed conflict information
conflicts := container.DetectPortConflicts(portMappings)
for _, c := range conflicts {
    fmt.Printf("Port %d in use by %s (pid %s)\n",
        c.Port, c.ProcessName, c.ProcessPID)
    if c.Suggestion > 0 {
        fmt.Printf("  Suggested alternative: %d\n", c.Suggestion)
    }
}
```

## Volume Mounts

### VolumeMount Structure

```go
type VolumeMount struct {
    Type        string // "bind" or "volume"
    Source      string // host path or volume name
    Target      string // container path
    ReadOnly    bool
    CreateHost  bool   // create host directory if it doesn't exist
}
```

### Common Volumes

The package automatically creates these volumes for all containers:

1. **Workspace**: Bind mount of the project directory to `/workspace`
2. **Claude Config**: Bind mount of `~/.claude` to `/home/claude/.claude`
3. **Session Directory**: Project-specific session directory for isolated conversations

```go
volumes := container.BuildCommonVolumes("/home/user/my-project", "abc123")
// Creates:
// - /home/user/my-project:/workspace
// - ~/.claude:/home/claude/.claude
// - ~/.claude/projects/home-user-my-project:/home/claude/.claude/projects/-workspace
```

## Helper Functions

```go
// Parse port mapping strings
pm, err := container.ParsePortMapping("8080:80")  // host:container
pm, err := container.ParsePortMapping("3000")      // same port for both

// Ensure a named volume exists
err := client.EnsureVolume(ctx, "my-volume")
```

## Platform Considerations

### macOS
- Does not support `--network=host` properly
- Always uses explicit port mappings
- Uses `host.docker.internal` for Chrome CDP connection

### Linux
- Can use `--network=host` when no port mappings specified
- Uses `localhost` for Chrome CDP connection when in host network mode

## Integration with Strategy Package

The container package integrates with the strategy package for environment-specific configuration:

```go
import (
    "github.com/rickgorman/claude-yolo/internal/container"
    "github.com/rickgorman/claude-yolo/internal/strategy"
)

// Get default ports from strategy
strategy := strategy.NewRailsStrategy()
defaultPorts := strategy.DefaultPorts()

// Convert to container.PortMapping
var portMappings []container.PortMapping
for _, dp := range defaultPorts {
    portMappings = append(portMappings, container.PortMapping{
        Host:      dp.Host,
        Container: dp.Container,
    })
}

// Resolve conflicts
resolved, err := container.ResolvePortConflicts(portMappings, headless)

// Get strategy volumes
strategyVolumes := strategy.Volumes(hash)
```

## Error Handling

All functions return errors that can be checked and handled:

```go
if err != nil {
    if client.IsErrNotFound(err) {
        // Handle not found
    } else {
        // Handle other errors
        log.Fatal(err)
    }
}
```

## Testing

Run the tests:

```bash
go test ./internal/container/...
```

Run with coverage:

```bash
go test -cover ./internal/container/...
```

## Dependencies

- `github.com/docker/docker/client` - Docker SDK for Go
- `github.com/docker/docker/api/types` - Docker API types
- `github.com/docker/go-connections/nat` - Port binding types
- `github.com/rickgorman/claude-yolo/internal/ui` - UI output functions
