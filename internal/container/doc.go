// Package container handles Docker operations, port conflict resolution, and volume management.
//
// The package provides four main components:
//
// 1. Docker Client Wrapper (docker.go)
//    - Simplified interface to Docker SDK
//    - Image and volume operations
//    - Container discovery
//
// 2. Container Lifecycle (lifecycle.go)
//    - Run, attach, and remove containers
//    - Container existence and running state checks
//    - Uptime calculation
//
// 3. Port Management (ports.go)
//    - Port conflict detection using lsof
//    - Automatic port remapping (base+1000, then base+1..base+100)
//    - Interactive prompts or headless auto-remap
//    - Platform-specific networking (macOS vs Linux)
//
// 4. Volume Management (volumes.go)
//    - Bind mounts and named volumes
//    - Automatic host directory creation
//    - Common volume setup for all containers
//
// Basic usage:
//
//	client, err := container.NewClient()
//	if err != nil {
//	    log.Fatal(err)
//	}
//	defer client.Close()
//
//	cfg := container.RunConfig{
//	    Name:     "my-container",
//	    Image:    "ubuntu",
//	    WorkDir:  "/workspace",
//	    Volumes:  []string{"/tmp:/workspace"},
//	    PortMappings: []container.PortMapping{{Host: 3000, Container: 3000}},
//	}
//
//	containerID, err := client.Run(ctx, cfg)
//
// Port conflict resolution:
//
//	portMappings := []container.PortMapping{{Host: 3000, Container: 3000}}
//	resolved, err := container.ResolvePortConflicts(portMappings, false)
//
// The package automatically handles:
//   - Port conflicts with interactive or automatic resolution
//   - macOS vs Linux networking differences (host.docker.internal vs localhost)
//   - Volume mount preparation with directory creation
//   - Container uptime formatting
package container
