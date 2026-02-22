// Package cli provides command-line argument parsing for claude-yolo.
//
// This package handles all CLI flag parsing and validation, converting
// command-line arguments into a structured Args type that the main
// application can use.
//
// Supported flags include:
//   - --yolo: Enable containerized mode
//   - --strategy: Force a specific environment strategy
//   - --chrome: Enable Chrome with CDP
//   - --reset: Remove existing containers
//   - --force-build: Force Docker image rebuild
//   - --trust-yolo: Trust .yolo/ config without prompting
//   - --trust-github-token: Accept GitHub tokens with broad scopes
//   - -e: Add environment variables
//
// Example usage:
//
//	args, err := cli.Parse(os.Args)
//	if err != nil {
//	    if err.Error() == "show_help" {
//	        showHelp()
//	        os.Exit(0)
//	    }
//	    log.Fatal(err)
//	}
//
//	if args.YoloMode {
//	    // Run in containerized mode
//	}
package cli
