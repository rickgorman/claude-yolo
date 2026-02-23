// Package ui provides terminal output formatting for claude-yolo.
//
// This package handles all user-facing output with consistent styling:
//   - Colored output (cyan, green, red, yellow)
//   - Headers and footers with box-drawing characters
//   - Info, success, failure, and warning messages
//   - Dimmed text for secondary information
//   - Interactive prompts (yes/no, choice selection, string input)
//
// All output goes to ui.Out (defaults to os.Stdout) to allow
// testing and output redirection.
//
// Example usage:
//
//	ui.Header()
//	ui.Info("Starting container...")
//	ui.Success("Container started successfully")
//	ui.Footer()
//
//	// Interactive prompts
//	if ui.AskYesNo("Continue?", true) {
//	    choice := ui.AskChoice("Select option", 1, 3)
//	}
//
// Output styling:
//   - Info:    → Cyan arrow
//   - Success: ✔ Green checkmark
//   - Fail:    ✘ Red X
//   - Warn:    ○ Yellow circle
package ui
