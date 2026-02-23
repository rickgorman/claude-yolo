package main

import (
	"fmt"
	"os"

	"github.com/rickgorman/claude-yolo/internal/entrypoint"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintf(os.Stderr, "Usage: entrypoint <strategy> [args...]\n")
		os.Exit(1)
	}

	strategy := os.Args[1]
	args := os.Args[2:]

	if err := entrypoint.Run(strategy, args); err != nil {
		fmt.Fprintf(os.Stderr, "entrypoint error: %v\n", err)
		os.Exit(1)
	}
}
