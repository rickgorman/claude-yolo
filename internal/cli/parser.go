// Package cli handles command-line argument parsing and execution.
package cli

import (
	"errors"
	"fmt"
	"os"
)

// Args represents parsed command-line arguments.
type Args struct {
	// Mode flags
	YoloMode       bool
	HeadlessMode   bool
	SetupTokenMode bool
	DetectOnlyPath string

	// Container flags
	Strategy       string
	ForceBuild     bool
	Verbose        bool
	ResetMode      bool

	// Environment flags
	ExtraEnv  []string
	EnvFiles  []string

	// Feature flags
	ChromeMode bool

	// Security flags
	TrustGitHubToken bool
	TrustYolo        bool

	// Remaining arguments to pass to Claude
	ClaudeArgs []string
}

// Parse parses command-line arguments into an Args struct.
func Parse(osArgs []string) (*Args, error) {
	args := &Args{
		ExtraEnv:   []string{},
		EnvFiles:   []string{},
		ClaudeArgs: []string{},
	}

	i := 1 // Skip program name
	for i < len(osArgs) {
		arg := osArgs[i]

		switch arg {
		case "-h", "--help":
			return nil, errors.New("show_help")

		case "--version":
			return nil, errors.New("show_version")

		case "--yolo":
			args.YoloMode = true
			i++

		case "--strategy":
			if i+1 >= len(osArgs) {
				return nil, fmt.Errorf("--strategy requires an argument")
			}
			args.Strategy = osArgs[i+1]
			i += 2

		case "--build":
			args.ForceBuild = true
			i++

		case "--verbose":
			args.Verbose = true
			i++

		case "--reset":
			args.ResetMode = true
			i++

		case "--chrome":
			args.ChromeMode = true
			i++

		case "--env":
			if i+1 >= len(osArgs) {
				return nil, fmt.Errorf("--env requires a KEY=VALUE argument")
			}
			args.ExtraEnv = append(args.ExtraEnv, osArgs[i+1])
			i += 2

		case "--env-file":
			if i+1 >= len(osArgs) {
				return nil, fmt.Errorf("--env-file requires a path argument")
			}
			envFile := osArgs[i+1]
			if _, err := os.Stat(envFile); err != nil {
				return nil, fmt.Errorf("--env-file: file not found: %s", envFile)
			}
			args.EnvFiles = append(args.EnvFiles, envFile)
			i += 2

		case "--trust-github-token":
			args.TrustGitHubToken = true
			i++

		case "--trust-yolo":
			args.TrustYolo = true
			i++

		case "--setup-token":
			args.SetupTokenMode = true
			i++

		case "-p", "--print":
			args.HeadlessMode = true
			args.ClaudeArgs = append(args.ClaudeArgs, arg)
			i++

		case "--detect":
			if i+1 >= len(osArgs) {
				return nil, fmt.Errorf("--detect requires a path argument")
			}
			args.DetectOnlyPath = osArgs[i+1]
			i += 2

		default:
			// Unknown flag or Claude argument
			args.ClaudeArgs = append(args.ClaudeArgs, arg)
			i++
		}
	}

	return args, nil
}
