package container

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"

	"github.com/rickgorman/claude-yolo/internal/ui"
)

// PortConflict represents a port that is already in use.
type PortConflict struct {
	Port        int
	ProcessName string
	ProcessPID  string
	Suggestion  int
}

// CheckPortInUse checks if a port is currently in use.
func CheckPortInUse(port int) bool {
	// Use lsof to check if port is listening
	cmd := exec.Command("lsof", "-i", fmt.Sprintf(":%d", port), "-sTCP:LISTEN")
	err := cmd.Run()
	return err == nil // If lsof succeeds, port is in use
}

// FindFreePort finds a free port starting from basePort.
// It tries basePort+1000 first, then basePort+1 to basePort+100.
func FindFreePort(basePort int) (int, bool) {
	// Try base+1000 first (e.g., 3000 -> 4000)
	candidate := basePort + 1000
	if !CheckPortInUse(candidate) {
		return candidate, true
	}

	// Fall back to base+1, base+2, ... base+100
	for offset := 1; offset <= 100; offset++ {
		candidate = basePort + offset
		if !CheckPortInUse(candidate) {
			return candidate, true
		}
	}

	return 0, false
}

// DetectPortConflicts checks for port conflicts and returns conflict details.
func DetectPortConflicts(portMappings []PortMapping) []PortConflict {
	var conflicts []PortConflict

	for _, mapping := range portMappings {
		if CheckPortInUse(mapping.Host) {
			conflict := PortConflict{
				Port: mapping.Host,
			}

			// Get process info using lsof
			if processName, processPID := getPortProcess(mapping.Host); processName != "" {
				conflict.ProcessName = processName
				conflict.ProcessPID = processPID
			}

			// Find a suggested alternative port
			if suggestion, found := FindFreePort(mapping.Host); found {
				conflict.Suggestion = suggestion
			}

			conflicts = append(conflicts, conflict)
		}
	}

	return conflicts
}

// getPortProcess gets the process name and PID using a port.
func getPortProcess(port int) (string, string) {
	cmd := exec.Command("lsof", "-i", fmt.Sprintf(":%d", port), "-sTCP:LISTEN", "-t")
	output, err := cmd.Output()
	if err != nil {
		return "", ""
	}

	pid := strings.TrimSpace(string(output))
	lines := strings.Split(pid, "\n")
	if len(lines) == 0 || lines[0] == "" {
		return "", ""
	}

	pid = lines[0]

	// Get process name using ps
	cmd = exec.Command("ps", "-p", pid, "-o", "comm=")
	output, err = cmd.Output()
	if err != nil {
		return "", pid
	}

	processName := strings.TrimSpace(string(output))
	return processName, pid
}

// ResolvePortConflicts handles port conflicts with interactive prompts or auto-remap.
// Returns the resolved port mappings and any error.
func ResolvePortConflicts(portMappings []PortMapping, autoRemap bool) ([]PortMapping, error) {
	conflicts := DetectPortConflicts(portMappings)

	// No conflicts - return unchanged
	if len(conflicts) == 0 {
		return portMappings, nil
	}

	// Check if all conflicts have suggestions
	allRemappable := true
	for _, c := range conflicts {
		if c.Suggestion == 0 {
			allRemappable = false
			break
		}
	}

	// Display conflicts
	ui.BlankLine()
	ui.Warn("Port conflict detected")
	for _, c := range conflicts {
		if c.ProcessName != "" {
			ui.DimMsg("  Port %d in use by %s (pid %s)", c.Port, c.ProcessName, c.ProcessPID)
		} else {
			ui.DimMsg("  Port %d is already in use", c.Port)
		}
	}
	ui.BlankLine()

	var doRemap bool

	if autoRemap {
		// Headless mode: auto-remap without prompting
		if !allRemappable {
			ui.Fail("Cannot auto-remap all conflicting ports")
			ui.Info("Run interactively without --force-build to resolve manually, or free the conflicting ports")
			return portMappings, fmt.Errorf("port conflicts cannot be auto-resolved")
		}

		doRemap = true
		for _, c := range conflicts {
			ui.Info("Auto-remapped %d → %d", c.Port, c.Suggestion)
		}
	} else {
		// Interactive prompt
		if allRemappable {
			ui.DimMsg("  Suggested remapping:")
			for _, c := range conflicts {
				ui.DimMsg("    %d → %d", c.Port, c.Suggestion)
			}
			ui.BlankLine()
			fmt.Fprintf(ui.Out, "    %s1%s  Remap to suggested ports\n", ui.Bold(""), ui.Dim(""))
			fmt.Fprintf(ui.Out, "    %s2%s  Continue anyway (docker may fail)\n", ui.Bold(""), ui.Dim(""))
			ui.BlankLine()

			choice := promptChoice("  Press ENTER to remap, or select [1-2]: ")

			switch choice {
			case "", "1":
				doRemap = true
				for _, c := range conflicts {
					ui.Success("Remapped %d → %d", c.Port, c.Suggestion)
				}
			default:
				ui.Warn("Continuing with conflicting ports")
			}
		} else {
			ui.Warn("Could not find free alternatives for all ports")
			ui.DimMsg("  Docker may fail to start with these port conflicts.")
		}
	}

	// Apply remapping if requested
	if doRemap {
		return applyPortRemapping(portMappings, conflicts), nil
	}

	return portMappings, nil
}

// applyPortRemapping applies the suggested port remappings.
func applyPortRemapping(portMappings []PortMapping, conflicts []PortConflict) []PortMapping {
	result := make([]PortMapping, len(portMappings))
	copy(result, portMappings)

	for i := range result {
		for _, c := range conflicts {
			if result[i].Host == c.Port && c.Suggestion > 0 {
				result[i].Host = c.Suggestion
				break
			}
		}
	}

	return result
}

// promptChoice prompts the user for input and returns their choice.
func promptChoice(prompt string) string {
	fmt.Fprint(ui.Out, prompt)

	reader := bufio.NewReader(os.Stdin)
	choice, err := reader.ReadString('\n')
	if err != nil {
		return ""
	}

	return strings.TrimSpace(choice)
}

// ShouldUseHostNetwork determines if we should use --network=host.
// On macOS, we can't use host networking, so we need explicit port mappings.
func ShouldUseHostNetwork(portMappings []PortMapping) bool {
	// macOS doesn't support --network=host properly, so always use port mappings
	if runtime.GOOS == "darwin" {
		return false
	}

	// If we have port mappings, don't use host network
	if len(portMappings) > 0 {
		return false
	}

	return true
}

// GetCDPHost returns the appropriate Chrome CDP host based on network mode.
// When using host networking, use "localhost".
// When using bridge networking, use "host.docker.internal" to reach the host.
func GetCDPHost(useHostNetwork bool) string {
	if useHostNetwork {
		return "localhost"
	}
	return "host.docker.internal"
}

// ParsePortMapping parses a port mapping string like "3000:3000" or "3000".
func ParsePortMapping(s string) (PortMapping, error) {
	s = strings.TrimSpace(s)

	if strings.Contains(s, ":") {
		parts := strings.Split(s, ":")
		if len(parts) != 2 {
			return PortMapping{}, fmt.Errorf("invalid port mapping format: %s", s)
		}

		host, err := strconv.Atoi(strings.TrimSpace(parts[0]))
		if err != nil {
			return PortMapping{}, fmt.Errorf("invalid host port: %s", parts[0])
		}

		container, err := strconv.Atoi(strings.TrimSpace(parts[1]))
		if err != nil {
			return PortMapping{}, fmt.Errorf("invalid container port: %s", parts[1])
		}

		return PortMapping{Host: host, Container: container}, nil
	}

	// Single port - use same for host and container
	port, err := strconv.Atoi(s)
	if err != nil {
		return PortMapping{}, fmt.Errorf("invalid port: %s", s)
	}

	return PortMapping{Host: port, Container: port}, nil
}
