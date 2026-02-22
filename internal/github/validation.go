package github

import (
	"fmt"
	"net/http"
	"strings"
	"time"
)

// BroadScopes lists dangerous token scopes that allow destructive operations.
var BroadScopes = []string{
	"delete_repo",
	"admin:org",
	"admin:enterprise",
	"admin:gpg_key",
	"admin:public_key",
	"admin:ssh_signing_key",
}

// ValidationResult holds the result of token validation.
type ValidationResult struct {
	Valid       bool
	Scopes      string
	BroadScopes []string
}

// ValidateToken checks if the token is valid by making a request to api.github.com/user.
func ValidateToken(token string) (bool, error) {
	client := &http.Client{
		Timeout: 10 * time.Second,
	}

	req, err := http.NewRequest("GET", "https://api.github.com/user", nil)
	if err != nil {
		return false, err
	}

	req.Header.Set("Authorization", "token "+token)

	resp, err := client.Do(req)
	if err != nil {
		return false, err
	}
	defer func() { _ = resp.Body.Close() }()

	return resp.StatusCode == 200, nil
}

// CheckScopes validates the token and checks for broad/dangerous scopes.
// Returns a ValidationResult with:
//   - Valid: whether the token is valid
//   - Scopes: the scopes string from X-OAuth-Scopes header (empty for fine-grained tokens)
//   - BroadScopes: list of dangerous scopes found
//
// Fine-grained tokens have no X-OAuth-Scopes header and are safe by design.
func CheckScopes(token string) (*ValidationResult, error) {
	client := &http.Client{
		Timeout: 10 * time.Second,
	}

	req, err := http.NewRequest("GET", "https://api.github.com/user", nil)
	if err != nil {
		return nil, err
	}

	req.Header.Set("Authorization", "token "+token)

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer func() { _ = resp.Body.Close() }()

	result := &ValidationResult{
		Valid: resp.StatusCode == 200,
	}

	if !result.Valid {
		return result, nil
	}

	// Check for X-OAuth-Scopes header
	scopesHeader := resp.Header.Get("X-OAuth-Scopes")

	// Fine-grained tokens have no X-OAuth-Scopes header — they're safe by design
	if scopesHeader == "" {
		return result, nil
	}

	result.Scopes = scopesHeader

	// Check for dangerous scopes
	result.BroadScopes = findBroadScopes(scopesHeader)

	return result, nil
}

// findBroadScopes searches for dangerous scopes in the scopes header.
// The scopes header is a comma-separated list like "repo, user, delete_repo"
func findBroadScopes(scopesHeader string) []string {
	var found []string

	// Normalize the scopes string for easier matching
	// Add commas at start/end to handle boundary matching
	normalized := "," + scopesHeader + ","
	normalized = strings.ReplaceAll(normalized, " ", "")

	for _, scope := range BroadScopes {
		// Try multiple matching patterns to catch different formats
		patterns := []string{
			"," + scope + ",",                 // exact match with commas
			"," + strings.TrimSpace(scope) + ",", // with trimmed whitespace
		}

		for _, pattern := range patterns {
			if strings.Contains(strings.ToLower(normalized), strings.ToLower(pattern)) {
				found = append(found, scope)
				break
			}
		}
	}

	return found
}

// FormatError formats a validation error message.
func FormatError(err error, source string) string {
	return fmt.Sprintf("GitHub token invalid (%s)\nVerify: GH_TOKEN=$GH_TOKEN gh auth status", source)
}

// FormatBroadScopesWarning formats a warning message for broad-scope tokens.
func FormatBroadScopesWarning(broadScopes []string, source string) string {
	scopesList := strings.Join(broadScopes, ", ")
	return fmt.Sprintf("GitHub token has broad scopes: %s\nThese scopes give the AI access to dangerous operations.\nToken source: %s\n\nTo accept the risk, re-run with:\n  cc --yolo --trust-github-token",
		scopesList, source)
}
