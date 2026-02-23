# Container Package Integration Guide

This guide shows how to integrate the container package into the main claude-yolo application.

## Overview

The container package replaces the Docker-related bash functions in `/workspace/bin/claude-yolo` (lines 209-437) with idiomatic Go code.

## Main Application Flow

Here's how the main application should use the container package:

### 1. Initialize Docker Client

```go
import (
    "context"
    "github.com/rickgorman/claude-yolo/internal/container"
)

func main() {
    ctx := context.Background()

    // Create Docker client
    dockerClient, err := container.NewClient()
    if err != nil {
        ui.Fail("Failed to connect to Docker: %v", err)
        os.Exit(1)
    }
    defer dockerClient.Close()
}
```

### 2. Check for Existing Containers

```go
// Generate container name based on project hash
containerName := fmt.Sprintf("claude-yolo-%s-%s", hash, timestamp)

// Check if container already exists
exists, err := dockerClient.Exists(ctx, containerName)
if err != nil {
    ui.Fail("Failed to check container: %v", err)
    os.Exit(1)
}

if exists {
    running, err := dockerClient.IsRunning(ctx, containerName)
    if err != nil {
        ui.Fail("Failed to check container status: %v", err)
        os.Exit(1)
    }

    if running {
        uptime, _ := dockerClient.Uptime(ctx, containerName)
        ui.Info("Container already running (uptime: %s)", uptime)

        // Attach to existing container
        err = dockerClient.Attach(ctx, containerName, true)
        if err != nil {
            ui.Fail("Failed to attach: %v", err)
            os.Exit(1)
        }
        return
    }
}
```

### 3. Build Port Mappings

```go
import "runtime"

// Get default ports from strategy
strategy := strategy.NewRailsStrategy() // or detected strategy
defaultPorts := strategy.DefaultPorts()

// Convert to container.PortMapping
var portMappings []container.PortMapping

// On macOS, we need explicit port mappings
if runtime.GOOS == "darwin" && len(defaultPorts) > 0 {
    for _, dp := range defaultPorts {
        portMappings = append(portMappings, container.PortMapping{
            Host:      dp.Host,
            Container: dp.Container,
        })
    }
}

// Override with .yolo/ports file if it exists
if portsFile := filepath.Join(worktreePath, ".yolo", "ports"); fileExists(portsFile) {
    portMappings = loadPortsFromFile(portsFile)
}

// Resolve port conflicts
headlessMode := !isInteractive()
resolvedPorts, err := container.ResolvePortConflicts(portMappings, headlessMode)
if err != nil {
    ui.Fail("Port conflicts: %v", err)
    os.Exit(1)
}
portMappings = resolvedPorts
```

### 4. Prepare Volumes

```go
// Build common volumes
volumes := container.BuildCommonVolumes(worktreePath, hash)

// Add strategy-specific volumes
strategyVolumes := convertStrategyVolumes(strategy.Volumes(hash))
volumes = container.AddStrategyVolumes(volumes, strategyVolumes)

// Prepare volumes (create host directories)
if err := container.PrepareVolumeMounts(volumes); err != nil {
    ui.Fail("Failed to prepare volumes: %v", err)
    os.Exit(1)
}

// Ensure named volumes exist
for _, vol := range volumes {
    if vol.Type == "volume" {
        if err := dockerClient.EnsureVolume(ctx, vol.Source); err != nil {
            ui.Fail("Failed to ensure volume %s: %v", vol.Source, err)
            os.Exit(1)
        }
    }
}
```

### 5. Build Environment Variables

```go
// Get strategy environment variables
strategyEnv, err := strategy.EnvVars(worktreePath)
if err != nil {
    ui.Fail("Failed to get environment: %v", err)
    os.Exit(1)
}

// Build environment variable list
env := []string{
    "TERM=" + os.Getenv("TERM"),
    "COLORTERM=" + os.Getenv("COLORTERM"),
    "DISABLE_AUTOUPDATER=1",
}

// Add Chrome CDP configuration
useHostNetwork := container.ShouldUseHostNetwork(portMappings)
cdpHost := container.GetCDPHost(useHostNetwork)
cdpPort := 9222 // from config or args
env = append(env, fmt.Sprintf("CHROME_CDP_URL=http://%s:%d", cdpHost, cdpPort))

// Add strategy environment
for _, e := range strategyEnv {
    env = append(env, fmt.Sprintf("%s=%s", e.Key, e.Value))
}
```

### 6. Run Container

```go
// Determine TTY flags based on mode
interactive := true
tty := true
if headlessMode {
    interactive = false
    tty = false
} else if !isStdinTerminal() {
    tty = false // stdin is piped
}

// Determine network mode
networkMode := "host"
if !container.ShouldUseHostNetwork(portMappings) {
    networkMode = "bridge"
}

// Build run configuration
cfg := container.RunConfig{
    Name:         containerName,
    Image:        imageName,
    WorkDir:      "/workspace",
    Platform:     "linux/amd64", // or from strategy
    Env:          env,
    Volumes:      container.ToDockerFormat(volumes),
    NetworkMode:  networkMode,
    PortMappings: portMappings,
    Interactive:  interactive,
    TTY:          tty,
    AutoRemove:   false,
}

// Run container
ui.Info("Starting container %s", containerName)
containerID, err := dockerClient.Run(ctx, cfg)
if err != nil {
    ui.Fail("Failed to start container: %v", err)
    os.Exit(1)
}

ui.Success("Container started: %s", containerID[:12])
```

### 7. Attach to Container

```go
// Attach to container (blocks until container exits)
err = dockerClient.Attach(ctx, containerID, interactive)
if err != nil {
    ui.Fail("Attach failed: %v", err)
    os.Exit(1)
}
```

## Helper Functions

### Loading Ports from File

```go
func loadPortsFromFile(filename string) []container.PortMapping {
    file, err := os.Open(filename)
    if err != nil {
        return nil
    }
    defer file.Close()

    var mappings []container.PortMapping
    scanner := bufio.NewScanner(file)

    for scanner.Scan() {
        line := strings.TrimSpace(scanner.Text())

        // Skip empty lines and comments
        if line == "" || strings.HasPrefix(line, "#") {
            continue
        }

        mapping, err := container.ParsePortMapping(line)
        if err != nil {
            ui.Warn("Invalid port mapping: %s", line)
            continue
        }

        mappings = append(mappings, mapping)
    }

    return mappings
}
```

### Converting Strategy Volumes

```go
func convertStrategyVolumes(strategyVols []strategy.VolumeMount) []container.VolumeMount {
    var result []container.VolumeMount

    for _, sv := range strategyVols {
        volumeType := "volume"
        if strings.HasPrefix(sv.Name, "/") || strings.HasPrefix(sv.Name, "~") {
            volumeType = "bind"
        }

        result = append(result, container.VolumeMount{
            Type:   volumeType,
            Source: sv.Name,
            Target: sv.Target,
        })
    }

    return result
}
```

### Checking Terminal State

```go
import "golang.org/x/term"

func isInteractive() bool {
    return term.IsTerminal(int(os.Stdin.Fd()))
}

func isStdinTerminal() bool {
    return term.IsTerminal(int(os.Stdin.Fd()))
}
```

## Command-Line Integration

### Build Command

```go
func buildCommand(imageName, strategyName, worktreePath string) error {
    ctx := context.Background()

    client, err := container.NewClient()
    if err != nil {
        return err
    }
    defer client.Close()

    // Check if image exists
    exists, err := client.ImageExists(ctx, imageName)
    if err != nil {
        return err
    }

    if exists {
        age, err := client.ImageAge(ctx, imageName)
        if err == nil && age > 7 {
            ui.Warn("Image is %d days old", age)
        }
    }

    // Build image...
    // (Implementation depends on how Dockerfiles are structured)

    return nil
}
```

### Remove Command

```go
func removeCommand(containerName string) error {
    ctx := context.Background()

    client, err := container.NewClient()
    if err != nil {
        return err
    }
    defer client.Close()

    exists, err := client.Exists(ctx, containerName)
    if err != nil {
        return err
    }

    if !exists {
        ui.Warn("Container %s does not exist", containerName)
        return nil
    }

    ui.Info("Removing container %s", containerName)
    err = client.Remove(ctx, containerName, true)
    if err != nil {
        return err
    }

    ui.Success("Container removed")
    return nil
}
```

## Error Handling Best Practices

```go
// Always wrap errors with context
if err != nil {
    return fmt.Errorf("failed to start container: %w", err)
}

// Check for specific Docker errors
if client.IsErrNotFound(err) {
    ui.Warn("Container not found")
    return nil
}

// Provide user-friendly messages
if err != nil {
    ui.Fail("Docker error: %v", err)
    ui.DimMsg("  Make sure Docker is running and you have permissions")
    os.Exit(1)
}
```

## Testing Integration

```go
func TestContainerIntegration(t *testing.T) {
    if testing.Short() {
        t.Skip("Skipping integration test")
    }

    ctx := context.Background()
    client, err := container.NewClient()
    if err != nil {
        t.Fatalf("Failed to create client: %v", err)
    }
    defer client.Close()

    // Test full lifecycle
    cfg := container.RunConfig{
        Name:  "test-container",
        Image: "alpine",
        // ... config
    }

    containerID, err := client.Run(ctx, cfg)
    if err != nil {
        t.Fatalf("Failed to run: %v", err)
    }

    defer client.Remove(ctx, containerID, true)

    // Test operations...
}
```

## Migration from Bash

The Go container package directly replaces these bash functions:

- `image_exists()` → `client.ImageExists()`
- `find_running_container()` → `client.FindRunningContainer()`
- `find_stopped_container()` → `client.FindStoppedContainer()`
- `container_uptime()` → `client.Uptime()`
- `image_age_days()` → `client.ImageAge()`
- `check_port_in_use()` → `container.CheckPortInUse()`
- `find_free_port()` → `container.FindFreePort()`
- `resolve_port_conflicts()` → `container.ResolvePortConflicts()`

The global `_RESOLVED_PORT_FLAGS` array is replaced by returning the resolved port mappings from `ResolvePortConflicts()`.
