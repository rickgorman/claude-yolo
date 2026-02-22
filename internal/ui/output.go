// Package ui provides user interface utilities for formatted terminal output.
package ui

import (
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/fatih/color"
)

const (
	BoxWidth = 46
)

var (
	// Color/style functions
	Bold   = color.New(color.Bold).SprintFunc()
	Dim    = color.New(color.Faint).SprintFunc()
	Green  = color.New(color.FgGreen).SprintFunc()
	Cyan   = color.New(color.FgCyan).SprintFunc()
	Yellow = color.New(color.FgYellow).SprintFunc()
	Red    = color.New(color.FgRed).SprintFunc()

	// Output destination (defaults to stderr to match bash script)
	Out io.Writer = os.Stderr
)

// Header prints the top border with "claude·yolo" branding.
func Header() {
	border := strings.Repeat("─", BoxWidth-14)
	fmt.Fprintf(Out, "  %s┌%s %sclaude·yolo%s %s%s\n",
		Dim(""), Dim(""), Bold(""), Dim(""), Dim(border), Dim(""))
}

// Footer prints the bottom border.
func Footer() {
	border := strings.Repeat("─", BoxWidth-1)
	fmt.Fprintf(Out, "  %s└%s%s\n", Dim(""), Dim(border), Dim(""))
}

// Info prints an informational message with a cyan arrow.
func Info(format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	fmt.Fprintf(Out, "  %s→%s %s\n", Cyan(""), Dim(""), msg)
}

// Success prints a success message with a green checkmark.
func Success(format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	fmt.Fprintf(Out, "  %s✔%s %s\n", Green(""), Dim(""), msg)
}

// Fail prints an error message with a red X.
func Fail(format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	fmt.Fprintf(Out, "  %s✘%s %s\n", Red(""), Dim(""), msg)
}

// Warn prints a warning message with a yellow circle.
func Warn(format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	fmt.Fprintf(Out, "  %s○%s %s\n", Yellow(""), Dim(""), msg)
}

// Dim prints a dimmed message.
func DimMsg(format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	fmt.Fprintf(Out, "  %s\n", Dim(msg))
}

// BlankLine prints a blank line to stderr.
func BlankLine() {
	fmt.Fprintln(Out, "")
}
