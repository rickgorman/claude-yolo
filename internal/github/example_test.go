package github_test

import (
	"fmt"
	"log"

	"github.com/rickgorman/claude-yolo/internal/github"
)

// Example demonstrates how to find, validate, and check a GitHub token.
func Example() {
	// Find a token from multiple sources
	result, err := github.FindToken("/workspace")
	if err != nil {
		log.Printf("Token not found: %v", err)
		return
	}

	fmt.Printf("Found token from: %s\n", result.Source)

	// Validate the token
	valid, err := github.ValidateToken(result.Token)
	if err != nil {
		log.Printf("Validation error: %v", err)
		return
	}

	if !valid {
		log.Printf("Token is invalid")
		return
	}

	fmt.Println("Token is valid")

	// Check for dangerous scopes
	scopeResult, err := github.CheckScopes(result.Token)
	if err != nil {
		log.Printf("Scope check error: %v", err)
		return
	}

	if len(scopeResult.BroadScopes) > 0 {
		fmt.Printf("Warning: Token has dangerous scopes: %v\n", scopeResult.BroadScopes)
	} else {
		fmt.Println("Token has safe scopes")
	}
}
