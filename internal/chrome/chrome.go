package chrome

import (
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"time"
)

// Manager handles Chrome CDP lifecycle
type Manager struct {
	Port         int
	UserDataDir  string
	ChromeBinary string
	pidFile      string
}

// NewManager creates a Chrome manager for the specified CDP port
func NewManager(port int) *Manager {
	tmpDir := os.Getenv("TMPDIR")
	if tmpDir == "" {
		tmpDir = "/tmp"
	}

	userDataDir := os.Getenv("CHROME_USER_DATA_DIR")
	if userDataDir == "" {
		homeDir, _ := os.UserHomeDir()
		userDataDir = filepath.Join(homeDir, fmt.Sprintf(".claude-yolo-chrome-%d", port))
	}

	return &Manager{
		Port:        port,
		UserDataDir: userDataDir,
		pidFile:     filepath.Join(tmpDir, fmt.Sprintf("claude-yolo-chrome-%d.pid", port)),
	}
}

// DetectChrome finds Chrome binary on the system
func (m *Manager) DetectChrome() error {
	// Check YOLO_CHROME_BINARY environment variable
	if chromeBinary, exists := os.LookupEnv("YOLO_CHROME_BINARY"); exists {
		if chromeBinary == "" {
			return fmt.Errorf("YOLO_CHROME_BINARY is set but empty (Chrome detection disabled)")
		}
		if _, err := os.Stat(chromeBinary); err == nil {
			if isExecutable(chromeBinary) {
				m.ChromeBinary = chromeBinary
				return nil
			}
		}
		return fmt.Errorf("YOLO_CHROME_BINARY=%s is not executable", chromeBinary)
	}

	// Try common Chrome paths
	paths := []string{
		// macOS
		"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
		"/Applications/Chromium.app/Contents/MacOS/Chromium",
		// Linux
		"/usr/bin/google-chrome",
		"/usr/bin/google-chrome-stable",
		"/usr/bin/chromium",
		"/usr/bin/chromium-browser",
	}

	for _, path := range paths {
		if _, err := os.Stat(path); err == nil {
			if isExecutable(path) {
				m.ChromeBinary = path
				return nil
			}
		}
	}

	return fmt.Errorf("Chrome not found")
}

// isExecutable checks if a file is executable
func isExecutable(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	return info.Mode()&0111 != 0
}

// IsRunning checks if Chrome CDP is responding on the configured port
func (m *Manager) IsRunning() bool {
	client := &http.Client{
		Timeout: 1 * time.Second,
	}

	resp, err := client.Get(fmt.Sprintf("http://localhost:%d/json/version", m.Port))
	if err != nil {
		return false
	}
	defer func() { _ = resp.Body.Close() }()

	return resp.StatusCode == http.StatusOK
}

// Start launches Chrome with remote debugging enabled
func (m *Manager) Start() error {
	// Check if already running
	if m.IsRunning() {
		fmt.Fprintf(os.Stderr, "[chrome] Chrome CDP already running on port %d\n", m.Port)
		return nil
	}

	// Detect Chrome binary if not set
	if m.ChromeBinary == "" {
		if err := m.DetectChrome(); err != nil {
			return fmt.Errorf("Chrome detection failed: %w", err)
		}
	}

	fmt.Fprintf(os.Stderr, "[chrome] Starting Chrome with remote debugging on port %d...\n", m.Port)

	// Create user data directory
	if err := os.MkdirAll(m.UserDataDir, 0755); err != nil {
		return fmt.Errorf("failed to create user data dir: %w", err)
	}

	// Build Chrome command
	cmd := exec.Command(m.ChromeBinary,
		"--headless=new",
		fmt.Sprintf("--remote-debugging-port=%d", m.Port),
		fmt.Sprintf("--user-data-dir=%s", m.UserDataDir),
		"--no-first-run",
		"--no-default-browser-check",
		"--disable-background-networking",
		"--disable-client-side-phishing-detection",
		"--disable-default-apps",
		"--disable-extensions",
		"--disable-hang-monitor",
		"--disable-popup-blocking",
		"--disable-prompt-on-repost",
		"--disable-sync",
		"--disable-translate",
		"--metrics-recording-only",
		"--safebrowsing-disable-auto-update",
	)

	// Discard output
	cmd.Stdout = nil
	cmd.Stderr = nil

	// Start Chrome
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("failed to start Chrome: %w", err)
	}

	// Write PID file
	if err := os.WriteFile(m.pidFile, []byte(strconv.Itoa(cmd.Process.Pid)), 0644); err != nil {
		return fmt.Errorf("failed to write PID file: %w", err)
	}

	// Wait for CDP to become available
	for attempts := 0; attempts < 20; attempts++ {
		if m.IsRunning() {
			fmt.Fprintf(os.Stderr, "[chrome] Chrome CDP ready on port %d\n", m.Port)
			return nil
		}
		time.Sleep(500 * time.Millisecond)
	}

	return fmt.Errorf("Chrome CDP not available after startup")
}

// Stop terminates the Chrome process
func (m *Manager) Stop() error {
	// Read PID file
	pidData, err := os.ReadFile(m.pidFile)
	if err != nil {
		if os.IsNotExist(err) {
			return nil // No PID file means Chrome not running
		}
		return fmt.Errorf("failed to read PID file: %w", err)
	}

	// Parse PID
	pid, err := strconv.Atoi(string(pidData))
	if err != nil {
		return fmt.Errorf("invalid PID in file: %w", err)
	}

	// Find process
	process, err := os.FindProcess(pid)
	if err != nil {
		// Process doesn't exist, clean up PID file
		_ = os.Remove(m.pidFile)
		return nil
	}

	// Kill process
	if err := process.Kill(); err != nil {
		// Process might already be dead
		_ = os.Remove(m.pidFile)
		return nil
	}

	fmt.Fprintf(os.Stderr, "[chrome] Stopped Chrome (PID %d, port %d)\n", pid, m.Port)

	// Remove PID file
	_ = os.Remove(m.pidFile)

	return nil
}

// EnsureRunning ensures Chrome CDP is running on the specified port
// This is called from the main CLI when --chrome flag is used
func EnsureRunning(port int, _ string) error {
	mgr := NewManager(port)

	// Check if already running
	if mgr.IsRunning() {
		return nil
	}

	// Start Chrome
	return mgr.Start()
}
