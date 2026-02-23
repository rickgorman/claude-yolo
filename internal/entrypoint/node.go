package entrypoint

import (
	"fmt"
	"os"
	"path/filepath"
)

func runNodeEntrypoint(args []string, log func(string)) error {
	home := os.Getenv("HOME")

	// Initialize nvm (requires sourcing nvm.sh)
	nvmDir := filepath.Join(home, ".nvm")
	_ = os.Setenv("NVM_DIR", nvmDir)

	// Install Node if NODE_VERSION is set and not already installed
	nodeVersion := os.Getenv("NODE_VERSION")
	if nodeVersion != "" {
		// Source nvm and install/use version
		nvmScript := fmt.Sprintf(`
			export NVM_DIR="$HOME/.nvm"
			[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
			if ! nvm ls %s >/dev/null 2>&1; then
				echo "[entrypoint:node] Installing Node.js %s (this may take a few minutes on first run)..." >&2
				nvm install %s
			fi
			nvm use %s
			echo "[entrypoint:node] Using Node.js $(node --version)" >&2
		`, nodeVersion, nodeVersion, nodeVersion, nodeVersion)

		if err := runInShell(nvmScript); err != nil {
			return fmt.Errorf("failed to install/use Node %s: %w", nodeVersion, err)
		}
	}

	// Install npm packages if package.json exists and node_modules is empty
	packageJSON := filepath.Join("/workspace", "package.json")
	nodeModules := filepath.Join("/workspace", "node_modules")
	if fileExists(packageJSON) && dirIsEmpty(nodeModules) {
		yarnLock := filepath.Join("/workspace", "yarn.lock")
		pnpmLock := filepath.Join("/workspace", "pnpm-lock.yaml")
		bunLock := filepath.Join("/workspace", "bun.lockb")

		// Source nvm before running package manager
		installScript := `
			export NVM_DIR="$HOME/.nvm"
			[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
		`

		switch {
		case fileExists(bunLock):
			log("Running bun install...")
			installScript += "bun install"
		case fileExists(pnpmLock):
			log("Running pnpm install...")
			installScript += "pnpm install --frozen-lockfile 2>/dev/null || pnpm install"
		case fileExists(yarnLock):
			log("Running yarn install...")
			installScript += "yarn install --frozen-lockfile 2>/dev/null || yarn install"
		default:
			log("Running npm install...")
			installScript += "npm install"
		}

		if err := runInShell(installScript); err != nil {
			return fmt.Errorf("failed to install packages: %w", err)
		}
	}

	// Execute the command with nvm environment
	execScript := fmt.Sprintf(`
		export NVM_DIR="$HOME/.nvm"
		[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
		exec %s
	`, shellEscape(args))

	return runInShell(execScript)
}

// shellEscape escapes arguments for shell execution
func shellEscape(args []string) string {
	escaped := make([]string, len(args))
	for i, arg := range args {
		// Simple shell escaping - wrap in single quotes and escape existing single quotes
		escaped[i] = "'" + shellEscapeSingleQuotes(arg) + "'"
	}
	result := ""
	for i, arg := range escaped {
		if i > 0 {
			result += " "
		}
		result += arg
	}
	return result
}

func shellEscapeSingleQuotes(s string) string {
	result := ""
	for _, char := range s {
		if char == '\'' {
			result += "'\\''"
		} else {
			result += string(char)
		}
	}
	return result
}
