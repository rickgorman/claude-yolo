# Container Package Overview

## Package Structure

```
internal/container/
├── Core Implementation (4 main files)
│   ├── docker.go          Docker client wrapper, image operations
│   ├── lifecycle.go       Container run/attach/remove/uptime
│   ├── ports.go           Port conflict detection and resolution
│   └── volumes.go         Volume mount management
│
├── Support Files
│   ├── helpers.go         Internal utilities
│   └── doc.go            Package documentation
│
├── Tests
│   ├── ports_test.go      Port management tests
│   ├── volumes_test.go    Volume management tests
│   └── example_test.go    Usage examples
│
└── Documentation
    ├── README.md          Comprehensive API documentation
    ├── INTEGRATION.md     Integration guide with examples
    ├── QUICKSTART.md      Quick reference for developers
    ├── IMPLEMENTATION.md  Implementation details
    └── OVERVIEW.md        This file
```

## Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     Main Application                        │
│                     (cmd/claude-yolo)                       │
└─────────────┬───────────────────────────┬───────────────────┘
              │                           │
              ▼                           ▼
    ┌─────────────────┐         ┌─────────────────┐
    │    Strategy     │         │    Container    │
    │    Package      │────────▶│    Package      │
    └─────────────────┘         └────────┬────────┘
                                         │
                    ┌────────────────────┼────────────────────┐
                    │                    │                    │
                    ▼                    ▼                    ▼
            ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
            │   Docker     │    │    Ports     │    │   Volumes    │
            │   Client     │    │  Management  │    │  Management  │
            └──────┬───────┘    └──────────────┘    └──────────────┘
                   │
                   ▼
         ┌─────────────────────┐
         │  Docker SDK (API)   │
         │  github.com/docker/ │
         └─────────────────────┘
```

## Data Flow

### Container Creation Flow

```
1. Strategy Detection
   └─> strategy.Detect() → Returns strategy name

2. Port Configuration
   ├─> strategy.DefaultPorts() → Get default ports
   ├─> Load .yolo/ports file (if exists)
   ├─> ParsePortMapping() → Parse port strings
   └─> ResolvePortConflicts() → Handle conflicts

3. Volume Setup
   ├─> BuildCommonVolumes() → Workspace, .claude, sessions
   ├─> strategy.Volumes() → Strategy-specific volumes
   ├─> AddStrategyVolumes() → Merge all volumes
   ├─> PrepareVolumeMounts() → Create host directories
   └─> ToDockerFormat() → Convert for Docker

4. Environment Setup
   ├─> strategy.EnvVars() → Get environment variables
   ├─> GetCDPHost() → Determine Chrome CDP host
   └─> Build env array

5. Container Creation
   ├─> NewClient() → Create Docker client
   ├─> client.Run(RunConfig) → Create & start container
   └─> client.Attach() → Attach to stdin/stdout/stderr
```

### Port Conflict Resolution Flow

```
ResolvePortConflicts(ports, autoRemap)
    │
    ├─> DetectPortConflicts()
    │   ├─> CheckPortInUse() [via lsof]
    │   ├─> getPortProcess() [get PID & name]
    │   └─> FindFreePort() [try base+1000, base+1..100]
    │
    ├─> Display conflicts with process info
    │
    ├─> If autoRemap (headless mode)
    │   └─> Auto-apply remapping
    │
    ├─> If interactive mode
    │   ├─> Show suggestions
    │   ├─> Prompt user [1=remap, 2=continue]
    │   └─> Apply based on choice
    │
    └─> Return resolved ports
```

## API Layers

### Layer 1: Docker Client (docker.go)

Low-level Docker operations:
- Image management (exists, age, remove)
- Container discovery (find running/stopped)
- Volume operations (exists, create, ensure)

### Layer 2: Container Lifecycle (lifecycle.go)

Mid-level container operations:
- Run containers with full configuration
- Attach to running containers
- Remove containers
- Check existence and running state
- Calculate uptime

### Layer 3: Port Management (ports.go)

High-level port conflict resolution:
- Detect conflicts with lsof
- Find free alternatives
- Interactive or automatic resolution
- Platform-aware networking

### Layer 4: Volume Management (volumes.go)

High-level volume operations:
- Build standard volumes
- Merge strategy volumes
- Prepare host directories
- Convert to Docker format

## Key Types

```go
// Docker client wrapper
type Client struct {
    cli *client.Client
}

// Container run configuration
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

// Port mapping
type PortMapping struct {
    Host      int
    Container int
}

// Port conflict with resolution info
type PortConflict struct {
    Port        int
    ProcessName string
    ProcessPID  string
    Suggestion  int
}

// Volume mount configuration
type VolumeMount struct {
    Type        string // "bind" or "volume"
    Source      string // host path or volume name
    Target      string // container path
    ReadOnly    bool
    CreateHost  bool   // create host dir if missing
}
```

## Integration Points

### With Strategy Package

```go
// Strategy provides:
strategy.DefaultPorts()    → []strategy.PortMapping
strategy.Volumes(hash)     → []strategy.VolumeMount
strategy.EnvVars(path)     → []strategy.EnvVar

// Container package uses:
container.PortMapping      ← strategy.PortMapping (convert)
container.VolumeMount      ← strategy.VolumeMount (convert)
// EnvVars used directly in RunConfig.Env
```

### With UI Package

```go
// Container package uses ui for output:
ui.Info()    → Informational messages
ui.Success() → Success confirmations
ui.Warn()    → Warnings
ui.Fail()    → Error messages
ui.DimMsg()  → Dimmed details
ui.BlankLine() → Spacing
```

### With Main Application

```go
// Main provides:
- Context for operations
- Configuration (headless mode, etc.)
- Worktree path, hash, strategy

// Container package provides:
- Docker client wrapper
- Container lifecycle management
- Port conflict resolution
- Volume setup
```

## Platform Handling

### macOS Behavior

```go
// Network mode
ShouldUseHostNetwork(ports) → always false (macOS doesn't support)

// CDP host
GetCDPHost(false) → "host.docker.internal"

// Port mappings
// Always required, never use --network=host
```

### Linux Behavior

```go
// Network mode
ShouldUseHostNetwork([]) → true (no port mappings)
ShouldUseHostNetwork(ports) → false (has port mappings)

// CDP host
GetCDPHost(true)  → "localhost" (host network)
GetCDPHost(false) → "host.docker.internal" (bridge)
```

## Error Handling Strategy

```go
// All functions return errors
func Operation() error

// Check for specific errors
if client.IsErrNotFound(err) {
    // Handle not found
}

// Wrap errors with context
return fmt.Errorf("operation failed: %w", err)

// Display user-friendly messages
if err != nil {
    ui.Fail("Operation failed: %v", err)
    return err
}
```

## Testing Strategy

### Unit Tests
- Port parsing (`TestParsePortMapping`)
- Path expansion (`TestExpandPath`)
- Volume building (`TestBuildCommonVolumes`)
- Port remapping logic (`TestApplyPortRemapping`)

### Example Tests
- Usage demonstrations
- Integration patterns
- Best practices

### Future Integration Tests
- Full container lifecycle
- Port conflict scenarios
- Volume mount preparation
- Docker API interactions

## Performance Considerations

1. **Client Reuse**: Create once, reuse throughout lifecycle
2. **Context Propagation**: Support cancellation and timeouts
3. **Lazy Volume Creation**: Only create when needed
4. **Port Check Optimization**: Single lsof call per port
5. **No Global State**: All state in function parameters/returns

## Dependencies

```
container package
├── github.com/docker/docker/client
├── github.com/docker/docker/api/types
├── github.com/docker/go-connections/nat
├── github.com/rickgorman/claude-yolo/internal/ui
└── Standard library (os, fmt, strings, time, etc.)
```

## File Size Summary

| File | Size | Purpose |
|------|------|---------|
| docker.go | 3.6K | Docker client wrapper |
| lifecycle.go | 4.1K | Container lifecycle |
| ports.go | 7.0K | Port management |
| volumes.go | 3.5K | Volume management |
| helpers.go | 3.8K | Internal utilities |
| doc.go | 1.8K | Package docs |
| **Total Code** | **23.8K** | **Core implementation** |
| ports_test.go | 2.2K | Port tests |
| volumes_test.go | 3.4K | Volume tests |
| example_test.go | 3.4K | Examples |
| **Total Tests** | **9.0K** | **Test coverage** |
| README.md | 7.8K | API documentation |
| INTEGRATION.md | 9.9K | Integration guide |
| QUICKSTART.md | 7.4K | Quick reference |
| IMPLEMENTATION.md | 10K | Implementation details |
| **Total Docs** | **35K** | **Documentation** |

## Quick Reference

### Most Common Operations

```go
// 1. Create client
client, _ := container.NewClient()
defer client.Close()

// 2. Check if running
running, _ := client.IsRunning(ctx, "name")

// 3. Resolve ports
resolved, _ := container.ResolvePortConflicts(ports, headless)

// 4. Build volumes
volumes := container.BuildCommonVolumes(path, hash)

// 5. Run container
cfg := container.RunConfig{Name: "name", Image: "image", ...}
id, _ := client.Run(ctx, cfg)

// 6. Attach
client.Attach(ctx, id, true)
```

## Next Steps

1. **For Users**: Start with QUICKSTART.md
2. **For Integration**: Read INTEGRATION.md
3. **For API Details**: See README.md
4. **For Architecture**: This file (OVERVIEW.md)
5. **For Implementation**: IMPLEMENTATION.md
