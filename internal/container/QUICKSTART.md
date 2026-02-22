# Container Package Quick Start

## Installation

The package is already integrated with the proper dependencies in `go.mod`.

## Basic Usage

### 1. Create Docker Client

```go
import "github.com/rickgorman/claude-yolo/internal/container"

client, err := container.NewClient()
if err != nil {
    log.Fatal(err)
}
defer client.Close()
```

### 2. Run a Container

```go
cfg := container.RunConfig{
    Name:     "my-container",
    Image:    "ubuntu",
    WorkDir:  "/workspace",
    Volumes:  []string{"/tmp/workspace:/workspace"},
    PortMappings: []container.PortMapping{
        {Host: 3000, Container: 3000},
    },
    Interactive: true,
    TTY:         true,
}

containerID, err := client.Run(ctx, cfg)
```

### 3. Resolve Port Conflicts

```go
ports := []container.PortMapping{{Host: 3000, Container: 3000}}

// Interactive mode (prompts user)
resolved, err := container.ResolvePortConflicts(ports, false)

// Headless mode (auto-remap)
resolved, err := container.ResolvePortConflicts(ports, true)
```

### 4. Build Volumes

```go
// Common volumes for all containers
volumes := container.BuildCommonVolumes("/path/to/project", "abc123")

// Add strategy-specific volumes
strategyVols := []container.VolumeMount{
    {Type: "volume", Source: "node-modules", Target: "/workspace/node_modules"},
}
volumes = container.AddStrategyVolumes(volumes, strategyVols)

// Prepare (create host directories)
err := container.PrepareVolumeMounts(volumes)

// Convert to Docker format
dockerVolumes := container.ToDockerFormat(volumes)
```

### 5. Check Container Status

```go
// Check if exists
exists, err := client.Exists(ctx, "my-container")

// Check if running
running, err := client.IsRunning(ctx, "my-container")

// Get uptime
uptime, err := client.Uptime(ctx, "my-container")
fmt.Println(uptime) // "2h 15m"
```

## Common Patterns

### Full Container Lifecycle

```go
ctx := context.Background()
client, err := container.NewClient()
if err != nil {
    return err
}
defer client.Close()

// Check if already running
running, _ := client.IsRunning(ctx, "my-container")
if running {
    ui.Info("Container already running")
    return client.Attach(ctx, "my-container", true)
}

// Build configuration
cfg := container.RunConfig{
    Name:        "my-container",
    Image:       "my-image",
    WorkDir:     "/workspace",
    Volumes:     dockerVolumes,
    PortMappings: resolvedPorts,
    Interactive: true,
    TTY:        true,
}

// Run and attach
containerID, err := client.Run(ctx, cfg)
if err != nil {
    return err
}

return client.Attach(ctx, containerID, true)
```

### Port Conflict Handling

```go
// Get default ports from strategy
defaultPorts := []container.PortMapping{
    {Host: 3000, Container: 3000},
    {Host: 8080, Container: 80},
}

// Resolve conflicts
resolved, err := container.ResolvePortConflicts(defaultPorts, headless)
if err != nil {
    ui.Fail("Port conflicts: %v", err)
    return err
}

// Use resolved ports
cfg.PortMappings = resolved
```

### Volume Setup

```go
// Build all volumes
volumes := container.BuildCommonVolumes(worktreePath, hash)

// Add strategy volumes (e.g., node_modules)
volumes = container.AddStrategyVolumes(volumes, strategyVolumes)

// Prepare host directories
if err := container.PrepareVolumeMounts(volumes); err != nil {
    return err
}

// Ensure named volumes exist
for _, vol := range volumes {
    if vol.Type == "volume" {
        if err := client.EnsureVolume(ctx, vol.Source); err != nil {
            return err
        }
    }
}

// Convert for Docker
cfg.Volumes = container.ToDockerFormat(volumes)
```

### Network Configuration

```go
// Determine network mode (macOS vs Linux)
useHostNetwork := container.ShouldUseHostNetwork(portMappings)

if useHostNetwork {
    cfg.NetworkMode = "host"
} else {
    cfg.NetworkMode = "bridge"
}

// Get Chrome CDP host
cdpHost := container.GetCDPHost(useHostNetwork)
env = append(env, fmt.Sprintf("CHROME_CDP_URL=http://%s:9222", cdpHost))
```

## API Reference

### Docker Client

| Function | Description |
|----------|-------------|
| `NewClient()` | Create Docker client |
| `ImageExists(ctx, name)` | Check if image exists |
| `ImageAge(ctx, name)` | Get image age in days |
| `FindRunningContainer(ctx, prefix)` | Find running container |
| `FindStoppedContainer(ctx, prefix)` | Find stopped container |
| `RemoveImage(ctx, name)` | Remove image |
| `CreateVolume(ctx, name)` | Create named volume |
| `EnsureVolume(ctx, name)` | Ensure volume exists |

### Container Lifecycle

| Function | Description |
|----------|-------------|
| `Run(ctx, cfg)` | Create and start container |
| `Attach(ctx, id, interactive)` | Attach to container |
| `Remove(ctx, name, force)` | Remove container |
| `Exists(ctx, name)` | Check if exists |
| `IsRunning(ctx, name)` | Check if running |
| `Uptime(ctx, name)` | Get uptime string |

### Port Management

| Function | Description |
|----------|-------------|
| `CheckPortInUse(port)` | Check if port is listening |
| `FindFreePort(basePort)` | Find free port |
| `DetectPortConflicts(mappings)` | Get conflict details |
| `ResolvePortConflicts(mappings, auto)` | Resolve conflicts |
| `ParsePortMapping(s)` | Parse port string |
| `ShouldUseHostNetwork(mappings)` | Determine network mode |
| `GetCDPHost(useHost)` | Get CDP host |

### Volume Management

| Function | Description |
|----------|-------------|
| `PrepareVolumeMounts(mounts)` | Create host directories |
| `ToDockerFormat(mounts)` | Convert to Docker format |
| `BuildCommonVolumes(path, hash)` | Build common volumes |
| `AddStrategyVolumes(base, strategy)` | Merge volumes |

## Error Handling

Always check errors:

```go
if err != nil {
    ui.Fail("Failed: %v", err)
    return err
}
```

For Docker-specific errors:

```go
if client.IsErrNotFound(err) {
    ui.Warn("Container not found")
    return nil
}
```

## Testing

Run tests:

```bash
# All tests
go test ./internal/container/...

# With coverage
go test -cover ./internal/container/...

# Verbose
go test -v ./internal/container/...

# Specific test
go test -run TestParsePortMapping ./internal/container/
```

## Platform Differences

### macOS
- Does not support `--network=host`
- Always uses explicit port mappings
- Uses `host.docker.internal` for CDP

### Linux
- Supports `--network=host`
- Can use host network when no port mappings
- Uses `localhost` for CDP in host mode

Check platform:

```go
import "runtime"

if runtime.GOOS == "darwin" {
    // macOS-specific code
}
```

## Examples

See:
- `example_test.go` - Usage examples
- `README.md` - Full documentation
- `INTEGRATION.md` - Integration guide

## Common Issues

### "Cannot connect to Docker daemon"
```go
client, err := container.NewClient()
// Error: Cannot connect to the Docker daemon
```
**Solution**: Make sure Docker is running

### "Port already in use"
```go
// Don't handle manually - use ResolvePortConflicts
resolved, err := container.ResolvePortConflicts(ports, false)
```

### "Permission denied" on volumes
```go
// Make sure to prepare volumes first
err := container.PrepareVolumeMounts(volumes)
```

## Performance Tips

- Reuse the Docker client (don't create multiple times)
- Use context for timeouts and cancellation
- Prepare volumes once before running container
- Check if container exists before creating new one

## Next Steps

1. Read INTEGRATION.md for full integration examples
2. Check README.md for comprehensive API documentation
3. Look at example_test.go for working code examples
4. See IMPLEMENTATION.md for architecture details
