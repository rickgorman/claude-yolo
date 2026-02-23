package entrypoint

import (
	"fmt"
	"os"
	"path/filepath"
)

func runRailsEntrypoint(args []string, log func(string)) error {
	home := os.Getenv("HOME")

	// Initialize rbenv
	rbenvBin := filepath.Join(home, ".rbenv", "bin")
	rbenvShims := filepath.Join(home, ".rbenv", "shims")
	path := rbenvBin + ":" + rbenvShims + ":" + os.Getenv("PATH")
	_ = os.Setenv("PATH", path)

	// Install Ruby if RUBY_VERSION is set and not already installed
	rubyVersion := os.Getenv("RUBY_VERSION")
	if rubyVersion != "" {
		if !versionInstalled("rbenv", rubyVersion) {
			log(fmt.Sprintf("Installing Ruby %s (this may take a few minutes on first run)...", rubyVersion))
			if err := runCommand("rbenv", "install", rubyVersion); err != nil {
				return fmt.Errorf("failed to install Ruby %s: %w", rubyVersion, err)
			}
		}
		if err := runCommand("rbenv", "global", rubyVersion); err != nil {
			return fmt.Errorf("failed to set Ruby version: %w", err)
		}
		log(fmt.Sprintf("Using Ruby %s", rubyVersion))
	}

	// Install bundler if not present
	if !commandExists("bundle") {
		log("Installing bundler...")
		if err := runCommand("gem", "install", "bundler", "--no-document"); err != nil {
			return fmt.Errorf("failed to install bundler: %w", err)
		}
	}

	// Run bundle install if Gemfile exists and gems aren't installed
	gemfile := filepath.Join("/workspace", "Gemfile")
	if fileExists(gemfile) {
		// Check if bundle check passes
		cmd := runInShell("bundle check >/dev/null 2>&1")
		if cmd != nil {
			// bundle check failed, need to install
			log("Running bundle install...")
			if err := runCommand("bundle", "install", "--jobs=4", "--retry=3"); err != nil {
				return fmt.Errorf("failed to run bundle install: %w", err)
			}
		}
	}

	// Install npm packages if package.json exists and node_modules is empty
	packageJSON := filepath.Join("/workspace", "package.json")
	nodeModules := filepath.Join("/workspace", "node_modules")
	if fileExists(packageJSON) && dirIsEmpty(nodeModules) {
		yarnLock := filepath.Join("/workspace", "yarn.lock")
		if fileExists(yarnLock) {
			log("Running yarn install...")
			// Try frozen lockfile first, fallback to regular install
			if err := runInShell("yarn install --frozen-lockfile 2>/dev/null || yarn install"); err != nil {
				return fmt.Errorf("failed to run yarn install: %w", err)
			}
		} else {
			log("Running npm install...")
			if err := runCommand("npm", "install"); err != nil {
				return fmt.Errorf("failed to run npm install: %w", err)
			}
		}
	}

	// Execute the command (typically claude)
	return execCommand(args)
}
