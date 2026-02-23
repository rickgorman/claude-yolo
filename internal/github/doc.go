// Package github provides GitHub token detection, validation, and scope checking.
//
// This package is part of the claude-yolo Go rewrite and handles all GitHub token
// operations, including:
//
//   - Finding tokens from multiple sources (env vars, .env files, gh CLI config)
//   - Validating tokens against the GitHub API
//   - Detecting dangerous scopes that could allow destructive operations
//
// Token Search Order:
//
//  1. GH_TOKEN environment variable
//  2. GITHUB_TOKEN environment variable
//  3. .env file in project directory
//  4. ~/.env file
//  5. ~/.config/gh/hosts.yml (or $XDG_CONFIG_HOME/gh/hosts.yml)
//
// Example usage:
//
//	// Find a token
//	result, err := github.FindToken("/workspace")
//	if err != nil {
//	    log.Fatal(err)
//	}
//
//	// Validate the token
//	valid, err := github.ValidateToken(result.Token)
//	if err != nil || !valid {
//	    log.Fatal("Invalid token")
//	}
//
//	// Check for dangerous scopes
//	scopeResult, err := github.CheckScopes(result.Token)
//	if err != nil {
//	    log.Fatal(err)
//	}
//
//	if len(scopeResult.BroadScopes) > 0 {
//	    log.Printf("Warning: Token has dangerous scopes: %v", scopeResult.BroadScopes)
//	}
package github
