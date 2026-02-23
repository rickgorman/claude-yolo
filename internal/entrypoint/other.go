package entrypoint

import (
	"os"
	"path/filepath"
)

func runGoEntrypoint(args []string, log func(string)) error {
	// Go doesn't need version management - uses system Go
	// Just exec the command
	return execCommand(args)
}

func runRustEntrypoint(args []string, log func(string)) error {
	home := os.Getenv("HOME")

	// Initialize rustup/cargo
	cargoHome := filepath.Join(home, ".cargo")
	cargoBin := filepath.Join(cargoHome, "bin")
	path := cargoBin + ":" + os.Getenv("PATH")
	os.Setenv("PATH", path)
	os.Setenv("CARGO_HOME", cargoHome)
	os.Setenv("RUSTUP_HOME", filepath.Join(home, ".rustup"))

	// Rust version is managed by rust-toolchain or rust-toolchain.toml files
	// rustup will automatically install the correct version when needed

	// Execute the command
	return execCommand(args)
}

func runAndroidEntrypoint(args []string, log func(string)) error {
	home := os.Getenv("HOME")

	// Initialize Android environment
	androidHome := os.Getenv("ANDROID_HOME")
	if androidHome == "" {
		androidHome = filepath.Join(home, "Android", "Sdk")
		os.Setenv("ANDROID_HOME", androidHome)
	}

	// Add Android tools to PATH
	toolsBin := filepath.Join(androidHome, "tools", "bin")
	platformTools := filepath.Join(androidHome, "platform-tools")
	path := toolsBin + ":" + platformTools + ":" + os.Getenv("PATH")
	os.Setenv("PATH", path)

	// Initialize Gradle
	gradleHome := filepath.Join(home, ".gradle")
	os.Setenv("GRADLE_USER_HOME", gradleHome)

	// Execute the command
	return execCommand(args)
}

func runJekyllEntrypoint(args []string, log func(string)) error {
	// Jekyll uses rbenv like Rails
	return runRailsEntrypoint(args, log)
}

func runGenericEntrypoint(args []string, log func(string)) error {
	// Generic strategy has no special setup
	return execCommand(args)
}
