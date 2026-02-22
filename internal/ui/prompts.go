package ui

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

// AskYesNo prompts the user with a yes/no question.
// Returns true for yes (Y/y/empty), false for no (N/n).
func AskYesNo(prompt string, defaultYes bool) bool {
	if defaultYes {
		_, _ = fmt.Fprintf(Out, "  %s [Y/n] ", prompt)
	} else {
		_, _ = fmt.Fprintf(Out, "  %s [y/N] ", prompt)
	}

	reader := bufio.NewReader(os.Stdin)
	response, _ := reader.ReadString('\n')
	response = strings.TrimSpace(strings.ToLower(response))

	if response == "" {
		return defaultYes
	}

	return response == "y" || response == "yes"
}

// AskChoice prompts the user to select from numbered options.
// Returns the selected index (0-based) or -1 for invalid choice.
func AskChoice(prompt string, defaultChoice int, maxChoice int) int {
	if defaultChoice > 0 {
		_, _ = fmt.Fprintf(Out, "  %s [1-%d]: ", prompt, maxChoice)
	} else {
		_, _ = fmt.Fprintf(Out, "  %s: ", prompt)
	}

	reader := bufio.NewReader(os.Stdin)
	response, _ := reader.ReadString('\n')
	response = strings.TrimSpace(response)

	if response == "" && defaultChoice > 0 {
		return defaultChoice - 1 // Convert to 0-based
	}

	choice, err := strconv.Atoi(response)
	if err != nil || choice < 1 || choice > maxChoice {
		return -1
	}

	return choice - 1 // Convert to 0-based
}

// AskString prompts the user for a string input.
func AskString(prompt string) string {
	_, _ = fmt.Fprintf(Out, "  %s: ", prompt)

	reader := bufio.NewReader(os.Stdin)
	response, _ := reader.ReadString('\n')
	return strings.TrimSpace(response)
}

// AskViewOrApply prompts whether to view or apply .yolo/ config.
// Returns: "apply", "view", or "cancel"
func AskViewOrApply(prompt string) string {
	_, _ = fmt.Fprintf(Out, "  %s [Y/n/v(iew)] ", prompt)

	reader := bufio.NewReader(os.Stdin)
	response, _ := reader.ReadString('\n')
	response = strings.TrimSpace(strings.ToLower(response))

	switch response {
	case "n":
		return "cancel"
	case "v", "view":
		return "view"
	default:
		return "apply"
	}
}
