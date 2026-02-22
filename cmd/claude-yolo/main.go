package main

import (
	"archive/tar"
	"bytes"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/docker/docker/api/types"
	"github.com/rickgorman/claude-yolo/internal/cli"
	"github.com/rickgorman/claude-yolo/internal/chrome"
	"github.com/rickgorman/claude-yolo/internal/container"
	"github.com/rickgorman/claude-yolo/internal/git"
	"github.com/rickgorman/claude-yolo/internal/github"
	"github.com/rickgorman/claude-yolo/internal/session"
	"github.com/rickgorman/claude-yolo/internal/strategy"
	"github.com/rickgorman/claude-yolo/internal/ui"
	"github.com/rickgorman/claude-yolo/internal/yoloconfig"
	"github.com/rickgorman/claude-yolo/pkg/hash"
)

const version = "2.0.0-dev"

func main() {
	// Parse arguments
	args, err := cli.Parse(os.Args)
	if err != nil {
		if err.Error() == "show_help" {
			showHelp()
			os.Exit(0)
		}
		if err.Error() == "show_version" {
			fmt.Printf("claude-yolo %s (Go rewrite)\n", version)
			os.Exit(0)
		}
		ui.Fail("Error parsing arguments: %v", err)
		ui.Info("Run %s for usage information", ui.Bold("claude-yolo --help"))
		os.Exit(1)
	}

	// --detect mode: non-interactive strategy detection
	if args.DetectOnlyPath != "" {
		handleDetectMode(args.DetectOnlyPath)
		return
	}

	// Normal mode without --yolo: pass through to native claude
	if !args.YoloMode {
		passthroughToNativeClaude(args.ClaudeArgs)
		return
	}

	// YOLO mode - full Docker container workflow
	handleYoloMode(args)
}

func handleDetectMode(path string) {
	detector := strategy.NewDetector(getStrategiesDir())
	strategyName, err := detector.DetectBestStrategy(path)
	if err == nil && strategyName != "" {
		fmt.Println(strategyName)
	}
	// Silent exit if no strategy detected
}

func passthroughToNativeClaude(claudeArgs []string) {
	cmd := exec.Command("claude", claudeArgs...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			os.Exit(exitErr.ExitCode())
		}
		os.Exit(1)
	}
}

func handleYoloMode(args *cli.Args) {
	// Check dependencies
	checkDependencies()

	// Print header
	ui.Header()

	// Get worktree path
	worktreePath, err := git.GetWorktreePath()
	if err != nil {
		ui.Fail("Failed to get worktree path: %v", err)
		ui.Info("Make sure you're running claude-yolo from inside a Git repository")
		ui.Footer()
		os.Exit(1)
	}

	// Generate path hash for container/volume names
	pathHash := hash.PathHash(worktreePath)
	containerName := "yolo-" + pathHash

	// Create Docker client
	ctx := context.Background()
	dockerClient, err := container.NewClient()
	if err != nil {
		ui.Fail("Failed to connect to Docker: %v", err)
		ui.Footer()
		os.Exit(1)
	}
	defer dockerClient.Close()

	// Handle --reset: remove existing containers
	if args.ResetMode {
		if err := dockerClient.Remove(ctx, containerName, true); err != nil {
			ui.Warn("Failed to remove container: %v", err)
		} else {
			ui.Info("Removed existing container(s)")
		}
		args.ForceBuild = true
	}

	// Migrate legacy yolo sessions
	session.MigrateYoloSessions()

	// Check for already-running container
	running, err := dockerClient.IsRunning(ctx, containerName)
	if err != nil {
		ui.Warn("Failed to check for running container: %v", err)
	}
	if running {
		ui.Success("Reconnecting to existing session")
		attachToContainer(dockerClient, containerName, args.ClaudeArgs)
		return
	}

	// Check for stopped container
	exists, err := dockerClient.Exists(ctx, containerName)
	if err != nil {
		ui.Warn("Failed to check for stopped container: %v", err)
	}
	if exists {
		ui.Info("Starting stopped container")
		if err := startContainer(ctx, dockerClient, containerName, args.ClaudeArgs); err != nil {
			ui.Fail("Failed to start container: %v", err)
			ui.Footer()
			os.Exit(1)
		}
		return
	}

	// Handle --setup-token
	if args.SetupTokenMode {
		ui.Fail("--setup-token not yet implemented in Go version")
		ui.Footer()
		os.Exit(1)
	}

	// Load .yolo/ configuration
	yoloConfig, err := yoloconfig.Load(worktreePath, args.TrustYolo)
	if err != nil {
		ui.Warn(".yolo/ config error: %v", err)
	}

	// Determine strategy
	strategyName := determineStrategy(args, yoloConfig, worktreePath)
	if strategyName == "" {
		ui.Fail("No strategy selected")
		ui.Info("Try: %s or set one in .yolo/config", ui.Bold("claude-yolo --yolo --strategy <name>"))
		ui.Info("Available strategies: rails, node, python, go, rust, android, jekyll, generic")
		ui.Footer()
		os.Exit(1)
	}

	// Get strategy instance
	detector := strategy.NewDetector(getStrategiesDir())
	strat, err := detector.GetStrategy(strategyName)
	if err != nil {
		ui.Fail("Invalid strategy: %s", strategyName)
		ui.Info("Available strategies: rails, node, python, go, rust, android, jekyll, generic")
		ui.Footer()
		os.Exit(1)
	}

	// Ensure GitHub token (unless user opted out)
	if os.Getenv("CLAUDE_YOLO_NO_GITHUB") != "1" {
		if err := ensureGitHubToken(worktreePath, args.TrustGitHubToken); err != nil {
			ui.Fail("%v", err)
			ui.Footer()
			os.Exit(1)
		}
	}

	// Check for .yolo/ trust and prompt if needed
	if yoloConfig != nil && !yoloConfig.Trusted {
		if !promptYoloTrust(yoloConfig) {
			yoloConfig = nil // User declined
		}
	}

	// Build image if needed
	imageName := buildImageIfNeeded(ctx, dockerClient, strat, pathHash, yoloConfig, args)
	if imageName == "" {
		ui.Fail("Failed to build image")
		ui.Footer()
		os.Exit(1)
	}

	// Start Chrome if --chrome flag
	cdpPort := hash.CDPPortForHash(pathHash)
	if args.ChromeMode {
		if err := chrome.EnsureRunning(cdpPort, getRepoDir()); err != nil {
			ui.Fail("Chrome startup failed: %v", err)
			ui.Footer()
			os.Exit(1)
		}
	}

	// Run container
	runContainer(ctx, dockerClient, strat, imageName, containerName, pathHash, worktreePath, yoloConfig, args)
}

func ensureGitHubToken(worktreePath string, trustGitHubToken bool) error {
	// Find token
	tokenResult, err := github.FindToken(worktreePath)
	if err != nil {
		return err
	}

	ui.Info("Found GitHub token (%s)", ui.Dim(tokenResult.Source))

	// Validate and check scopes
	validation, err := github.CheckScopes(tokenResult.Token)
	if err != nil {
		return fmt.Errorf("failed to validate token: %w", err)
	}

	if !validation.Valid {
		return fmt.Errorf(github.FormatError(err, tokenResult.Source))
	}

	// Warn about broad scopes
	if len(validation.BroadScopes) > 0 && !trustGitHubToken {
		ui.Warn("%s", github.FormatBroadScopesWarning(validation.BroadScopes, tokenResult.Source))
		return fmt.Errorf("token has broad scopes - use --trust-github-token to proceed")
	}

	return nil
}

func buildImageIfNeeded(ctx context.Context, dockerClient *container.Client, strat strategy.Strategy, pathHash string, yoloConfig *yoloconfig.Config, args *cli.Args) string {
	imageName := "yolo-" + pathHash

	// Check if image exists
	exists, err := dockerClient.ImageExists(ctx, imageName)
	if err != nil {
		ui.Warn("Failed to check image existence: %v", err)
	}

	// Determine if we need to build
	needsBuild := args.ForceBuild || !exists

	if exists && !args.ForceBuild {
		// Check image age - rebuild if older than 7 days
		age, err := dockerClient.ImageAge(ctx, imageName)
		if err == nil && age > 7 {
			ui.Info("Image is %d days old, rebuilding...", age)
			needsBuild = true
		}
	}

	if !needsBuild {
		ui.Info("Using existing image: %s", imageName)
		return imageName
	}

	// Build new image
	ui.Info("Building image: %s", imageName)

	// Get Dockerfile path
	dockerfilePath := filepath.Join(getStrategiesDir(), strat.Name(), "Dockerfile")
	if yoloConfig != nil && yoloConfig.Dockerfile != "" {
		dockerfilePath = yoloConfig.Dockerfile
	}

	// Create build context
	buildContext, err := createTarContext(dockerfilePath)
	if err != nil {
		ui.Fail("Failed to create build context: %v", err)
		return ""
	}

	// Build image
	buildOpts := types.ImageBuildOptions{
		Tags:       []string{imageName + ":latest"},
		Dockerfile: "Dockerfile",
		Remove:     true,
		NoCache:    args.ForceBuild,
	}

	if err := dockerClient.BuildImage(ctx, buildContext, buildOpts); err != nil {
		ui.Fail("Failed to build image: %v", err)
		return ""
	}

	ui.Success("Image built: %s", imageName)
	return imageName
}

func createTarContext(dockerfilePath string) (io.Reader, error) {
	var buf bytes.Buffer
	tw := tar.NewWriter(&buf)

	// Read Dockerfile content
	content, err := os.ReadFile(dockerfilePath)
	if err != nil {
		return nil, err
	}

	// Add Dockerfile to tar
	header := &tar.Header{
		Name: "Dockerfile",
		Size: int64(len(content)),
		Mode: 0644,
	}

	if err := tw.WriteHeader(header); err != nil {
		return nil, err
	}

	if _, err := tw.Write(content); err != nil {
		return nil, err
	}

	if err := tw.Close(); err != nil {
		return nil, err
	}

	return &buf, nil
}

func runContainer(ctx context.Context, dockerClient *container.Client, strat strategy.Strategy, imageName, containerName, pathHash, worktreePath string, yoloConfig *yoloconfig.Config, args *cli.Args) {
	// Build environment variables
	env := buildEnvironment(strat, worktreePath, yoloConfig, args)

	// Build volume mounts
	volumes := buildVolumes(strat, pathHash, worktreePath)

	// Build port mappings
	ports := buildPortMappings(strat, pathHash, yoloConfig, args)

	// Check for port conflicts
	conflicts := container.DetectPortConflicts(ports)
	if len(conflicts) > 0 {
		ui.BlankLine()
		ui.Warn("Port conflicts detected:")
		for _, conflict := range conflicts {
			ui.DimMsg("  Port %d in use by %s (PID %s)", conflict.Port, conflict.ProcessName, conflict.ProcessPID)
			if conflict.Suggestion > 0 {
				ui.DimMsg("  Suggestion: Use port %d instead", conflict.Suggestion)
			}
		}
		ui.BlankLine()
		ui.Fail("Please free the conflicting ports or use different ports")
		ui.Footer()
		os.Exit(1)
	}

	// Create run configuration
	runConfig := container.RunConfig{
		Name:         containerName,
		Image:        imageName,
		WorkDir:      "/workspace",
		Env:          env,
		Volumes:      volumes,
		NetworkMode:  "host",
		PortMappings: ports,
		Interactive:  true,
		TTY:          true,
		AutoRemove:   false,
	}

	// Start container
	ui.Info("Starting container...")
	containerID, err := dockerClient.Run(ctx, runConfig)
	if err != nil {
		ui.Fail("Failed to start container: %v", err)
		ui.Footer()
		os.Exit(1)
	}

	ui.Success("Container started")
	ui.Footer()

	// Attach to container
	if err := dockerClient.Attach(ctx, containerID, true); err != nil {
		ui.Warn("Container exited: %v", err)
	}
}

func attachToContainer(dockerClient *container.Client, containerName string, claudeArgs []string) {
	ctx := context.Background()

	// Show uptime
	uptime, err := dockerClient.Uptime(ctx, containerName)
	if err == nil {
		ui.Info("Container running for %s", uptime)
	}

	ui.Footer()

	// Attach
	if err := dockerClient.Attach(ctx, containerName, true); err != nil {
		ui.Warn("Container exited: %v", err)
	}
}

func startContainer(ctx context.Context, dockerClient *container.Client, containerName string, claudeArgs []string) error {
	// For now, we'll just attach - the container package handles starting
	ui.Footer()
	return dockerClient.Attach(ctx, containerName, true)
}

func buildEnvironment(strat strategy.Strategy, worktreePath string, yoloConfig *yoloconfig.Config, args *cli.Args) []string {
	var env []string

	// Get strategy environment variables
	stratEnvVars, err := strat.EnvVars(worktreePath)
	if err == nil {
		for _, ev := range stratEnvVars {
			env = append(env, ev.Key+"="+ev.Value)
		}
	}

	// Add git config
	gitConfig, err := git.ExtractUserConfig()
	if err == nil {
		if gitConfig.Name != "" {
			env = append(env, "GIT_AUTHOR_NAME="+gitConfig.Name, "GIT_COMMITTER_NAME="+gitConfig.Name)
		}
		if gitConfig.Email != "" {
			env = append(env, "GIT_AUTHOR_EMAIL="+gitConfig.Email, "GIT_COMMITTER_EMAIL="+gitConfig.Email)
		}
	}

	// Add GitHub token
	if tokenResult, err := github.FindToken(worktreePath); err == nil {
		env = append(env, "GH_TOKEN="+tokenResult.Token, "GITHUB_TOKEN="+tokenResult.Token)
	}

	// Add .yolo/ env vars
	if yoloConfig != nil {
		for k, v := range yoloConfig.Env {
			env = append(env, k+"="+v)
		}
	}

	// Add extra env from args
	env = append(env, args.ExtraEnv...)

	return env
}

func buildVolumes(strat strategy.Strategy, pathHash, worktreePath string) []string {
	var volumes []string

	// Get strategy volumes
	stratVolumes := strat.Volumes(pathHash)
	for _, vol := range stratVolumes {
		volumes = append(volumes, vol.Name+":"+vol.Target)
	}

	// Add worktree bind mount
	volumes = append(volumes, worktreePath+":/workspace")

	// Add home directory volume for Claude config
	homeDir, err := os.UserHomeDir()
	if err == nil {
		volumes = append(volumes, homeDir+"/.claude:/home/claude/.claude")
	}

	return volumes
}

func buildPortMappings(strat strategy.Strategy, pathHash string, yoloConfig *yoloconfig.Config, args *cli.Args) []container.PortMapping {
	var mappings []container.PortMapping

	// Get strategy ports
	stratPorts := strat.DefaultPorts()

	// Override with .yolo/ ports if present
	if yoloConfig != nil && len(yoloConfig.Ports) > 0 {
		// .yolo/ports file has string port numbers, convert them
		mappings = []container.PortMapping{} // Clear strategy ports
		for _, portStr := range yoloConfig.Ports {
			var port int
			fmt.Sscanf(portStr, "%d", &port)
			if port > 0 {
				mappings = append(mappings, container.PortMapping{
					Host:      port,
					Container: port,
				})
			}
		}
	} else {
		// Use strategy default ports
		for _, pm := range stratPorts {
			mappings = append(mappings, container.PortMapping{
				Host:      pm.Host,
				Container: pm.Container,
			})
		}
	}

	// Add CDP port if --chrome mode
	if args.ChromeMode {
		cdpPort := hash.CDPPortForHash(pathHash)
		mappings = append(mappings, container.PortMapping{
			Host:      cdpPort,
			Container: 9222,
		})
	}

	return mappings
}

func determineStrategy(args *cli.Args, yoloConfig *yoloconfig.Config, worktreePath string) string {
	// .yolo/strategy override
	if yoloConfig != nil && yoloConfig.Strategy != "" {
		ui.Info("Using strategy: %s (.yolo/strategy)", ui.Bold(yoloConfig.Strategy))
		return yoloConfig.Strategy
	}

	// --strategy flag
	if args.Strategy != "" {
		ui.Info("Using strategy: %s (--strategy flag)", ui.Bold(args.Strategy))
		return args.Strategy
	}

	// Auto-detection with user choice
	detector := strategy.NewDetector(getStrategiesDir())
	results, err := detector.RunDetection(worktreePath)
	if err != nil || len(results) == 0 {
		// Try deep detection in subdirectories
		results, _ = detector.RunDetectionDeep(worktreePath)
	}

	if len(results) == 0 {
		return chooseFromFullList(detector)
	}

	// Single high-confidence match
	if len(results) == 1 && results[0].Confidence >= 80 {
		top := results[0]
		ui.Success("Detected: %s (%d%%)", ui.Bold(top.Strategy), top.Confidence)
		ui.DimMsg(top.Evidence)
		return top.Strategy
	}

	// Multiple matches - show menu
	return showStrategyMenu(results, detector)
}

func showStrategyMenu(results []strategy.DetectionResult, detector *strategy.Detector) string {
	ui.BlankLine()
	fmt.Fprintln(ui.Out, "  Detected:")

	for i, result := range results {
		glyph := "○"
		color := ui.Yellow
		if result.Confidence >= 80 {
			glyph = "●"
			color = ui.Green
		}

		fmt.Fprintf(ui.Out, "    %s  %s %-10s %s%3d%% %s%s%s\n",
			ui.Bold(fmt.Sprintf("%d", i+1)),
			color(glyph),
			result.Strategy,
			ui.Dim(""),
			result.Confidence,
			ui.Dim("%   "),
			ui.Dim(result.Evidence),
			ui.Dim(""))
	}

	otherChoice := len(results) + 1
	fmt.Fprintf(ui.Out, "    %s  ○ %-10s        %s\n",
		ui.Bold(fmt.Sprintf("%d", otherChoice)),
		"other",
		ui.Dim("see all supported / generate new"))
	ui.BlankLine()

	topStrategy := results[0].Strategy
	choice := ui.AskChoice(fmt.Sprintf("Press ENTER for %s, or select [1-%d]", topStrategy, otherChoice), 1, otherChoice)

	if choice == -1 || choice == 0 {
		return topStrategy
	}

	if choice == len(results) {
		return chooseFromFullList(detector)
	}

	return results[choice].Strategy
}

func chooseFromFullList(detector *strategy.Detector) string {
	strategies := detector.ListStrategies()

	ui.BlankLine()
	ui.Warn("No environment auto-detected")
	ui.BlankLine()
	fmt.Fprintln(ui.Out, "  Select an environment:")

	for i, name := range strategies {
		fmt.Fprintf(ui.Out, "    %s  %-12s\n", ui.Bold(fmt.Sprintf("%d", i+1)), name)
	}

	otherChoice := len(strategies) + 1
	fmt.Fprintf(ui.Out, "    %s  %-12s %s\n",
		ui.Bold(fmt.Sprintf("%d", otherChoice)),
		"other",
		ui.Dim("generate prompt for new strategy"))
	ui.BlankLine()

	choice := ui.AskChoice("▸", 0, otherChoice)

	if choice == -1 {
		return ""
	}

	if choice == len(strategies) {
		// TODO: Generate unknown prompt
		return ""
	}

	return strategies[choice]
}

func promptYoloTrust(config *yoloconfig.Config) bool {
	ui.BlankLine()
	ui.Warn("This project has a %s configuration directory", ui.Bold(".yolo/"))

	// List files
	entries, _ := os.ReadDir(config.Dir)
	ui.DimMsg("Files:")
	for _, entry := range entries {
		if !entry.IsDir() {
			ui.DimMsg("  " + entry.Name())
		}
	}
	ui.BlankLine()

	response := ui.AskViewOrApply("Apply .yolo/ config?")

	if response == "cancel" {
		return false
	}

	if response == "view" {
		// Show file contents
		for _, entry := range entries {
			if entry.IsDir() {
				continue
			}
			ui.BlankLine()
			ui.DimMsg("── " + entry.Name() + " ──")
			data, _ := os.ReadFile(filepath.Join(config.Dir, entry.Name()))
			for _, line := range strings.Split(string(data), "\n") {
				ui.DimMsg("    " + line)
			}
		}
		ui.BlankLine()

		return ui.AskYesNo("Apply .yolo/ config?", true)
	}

	return true // "apply"
}

func checkDependencies() {
	missing := []string{}

	if !commandExists("docker") {
		missing = append(missing, "docker")
	}
	if !commandExists("git") {
		missing = append(missing, "git")
	}
	if !commandExists("curl") {
		missing = append(missing, "curl")
	}
	if !commandExists("tmux") {
		missing = append(missing, "tmux")
	}

	if len(missing) > 0 {
		ui.Fail("Missing required dependencies: %s", ui.Bold(strings.Join(missing, " ")))
		ui.BlankLine()

		if runtime.GOOS == "darwin" {
			ui.DimMsg("Install with: brew install " + strings.Join(missing, " "))
		} else {
			ui.DimMsg("Install with: sudo apt-get install " + strings.Join(missing, " "))
		}

		os.Exit(1)
	}

	// Check Docker is running
	cmd := exec.Command("docker", "info")
	cmd.Stdout = nil
	cmd.Stderr = nil
	if err := cmd.Run(); err != nil {
		ui.Fail("Docker is not running. Start Docker Desktop and try again.")
		os.Exit(1)
	}
}

func commandExists(cmd string) bool {
	_, err := exec.LookPath(cmd)
	return err == nil
}

func getRepoDir() string {
	exe, err := os.Executable()
	if err != nil {
		return "."
	}
	// Assume binary is in bin/, repo is parent
	return filepath.Dir(filepath.Dir(exe))
}

func getStrategiesDir() string {
	return filepath.Join(getRepoDir(), "strategies")
}

func showHelp() {
	help := `claude-yolo - AI pair programming in isolated Docker containers

USAGE:
    claude-yolo [OPTIONS] [CLAUDE_ARGS...]

OPTIONS:
    --yolo                 Enable containerized mode
    --headless             Run without interactive prompts
    --strategy NAME        Force a specific strategy (rails, node, python, etc.)
    --force-build          Force rebuild of Docker image
    --chrome               Start Chrome with CDP for browser automation
    --setup-token          Interactive GitHub token setup
    --reset                Remove existing containers before starting
    --detect PATH          Detect and print strategy for given path
    --trust-yolo           Trust .yolo/ config without prompting
    --trust-github-token   Accept GitHub tokens with broad scopes
    -e KEY=VALUE           Add environment variable to container
    -h, --help             Show this help message
    --version              Show version information

EXAMPLES:
    # Auto-detect environment and start containerized session
    claude-yolo --yolo

    # Force specific strategy
    claude-yolo --yolo --strategy rails

    # Rebuild image from scratch
    claude-yolo --yolo --force-build

    # Enable Chrome browser automation
    claude-yolo --yolo --chrome

    # Pass arguments through to native claude
    claude-yolo chat "hello world"

ENVIRONMENT VARIABLES:
    GH_TOKEN                GitHub token for API access
    GITHUB_TOKEN            Alternative GitHub token variable
    CLAUDE_YOLO_NO_GITHUB   Set to 1 to skip GitHub token check

DOCUMENTATION:
    https://github.com/rickgorman/claude-yolo
`
	fmt.Print(help)
}
