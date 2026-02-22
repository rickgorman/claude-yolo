# Integration Guide

This guide shows how to integrate the `github` package into the main claude-yolo application.

## Complete Example

Here's how to use the package in your main application:

```go
package main

import (
    "fmt"
    "os"

    "github.com/rickgorman/claude-yolo/internal/github"
    "github.com/rickgorman/claude-yolo/internal/ui"
)

func ensureGitHubToken(worktreePath string, trustGitHubToken bool) error {
    // Check if GitHub token check is disabled
    if os.Getenv("CLAUDE_YOLO_NO_GITHUB") != "" {
        ui.DimMsg("GitHub token check skipped (CLAUDE_YOLO_NO_GITHUB)")
        return nil
    }

    // Find token from multiple sources
    result, err := github.FindToken(worktreePath)
    if err != nil {
        ui.Fail("GitHub token not found")
        ui.BlankLine()
        ui.DimMsg("Searched:")
        ui.DimMsg("  • GH_TOKEN environment variable")
        ui.DimMsg("  • GITHUB_TOKEN environment variable")
        ui.DimMsg("  • %s/.env", worktreePath)
        ui.DimMsg("  • ~/.env")
        ui.DimMsg("  • ~/.config/gh/hosts.yml")
        ui.BlankLine()
        ui.DimMsg("Set one with:")
        ui.DimMsg("  export GH_TOKEN=ghp_your_token_here")
        ui.BlankLine()
        ui.DimMsg("Or skip this check entirely:")
        ui.DimMsg("  export CLAUDE_YOLO_NO_GITHUB=1")
        return fmt.Errorf("GitHub token not found")
    }

    // Validate the token
    valid, err := github.ValidateToken(result.Token)
    if err != nil || !valid {
        ui.Fail("GitHub token invalid (%s)", result.Source)
        ui.DimMsg("Verify: GH_TOKEN=$GH_TOKEN gh auth status")
        return fmt.Errorf("GitHub token invalid")
    }

    // Check for dangerous scopes
    scopeResult, err := github.CheckScopes(result.Token)
    if err != nil {
        return fmt.Errorf("failed to check token scopes: %w", err)
    }

    if len(scopeResult.BroadScopes) > 0 {
        scopesList := strings.Join(scopeResult.BroadScopes, ", ")
        ui.Warn("GitHub token has broad scopes: %s", ui.Bold(scopesList))
        ui.DimMsg("These scopes give the AI access to dangerous operations.")
        ui.DimMsg("Token source: %s", result.Source)
        ui.BlankLine()

        if trustGitHubToken {
            ui.DimMsg("Proceeding (--trust-github-token)")
        } else {
            ui.Fail("Refusing to proceed with broad-scope token")
            ui.DimMsg("To accept the risk, re-run with:")
            ui.DimMsg("  cc --yolo --trust-github-token")
            return fmt.Errorf("broad-scope token not trusted")
        }
    }

    ui.Success("GitHub token %s(%s)%s", ui.Dim(""), result.Source, ui.Dim(""))
    return nil
}
```

## Error Handling

The package provides helpful error messages that match the bash script's output:

```go
result, err := github.FindToken("/workspace")
if err != nil {
    // Error includes helpful message with all searched locations
    fmt.Println(err)
    // Output:
    // GitHub token not found
    //
    // Searched:
    //   • GH_TOKEN environment variable
    //   • GITHUB_TOKEN environment variable
    //   • /workspace/.env
    //   • ~/.env
    //   • ~/.config/gh/hosts.yml
    //
    // Set one with:
    //   export GH_TOKEN=ghp_your_token_here
    //
    // Or skip this check entirely:
    //   export CLAUDE_YOLO_NO_GITHUB=1
}
```

## Testing Your Integration

1. **Test with environment variable:**
   ```bash
   export GH_TOKEN=ghp_your_token_here
   ./claude-yolo
   ```

2. **Test with .env file:**
   ```bash
   echo 'GH_TOKEN=ghp_your_token_here' > .env
   ./claude-yolo
   ```

3. **Test with gh CLI config:**
   ```bash
   gh auth login
   ./claude-yolo
   ```

4. **Test skipping the check:**
   ```bash
   export CLAUDE_YOLO_NO_GITHUB=1
   ./claude-yolo
   ```

## Performance Notes

- Token detection is fast - it reads small files sequentially
- Validation makes one HTTP request to GitHub API (with 10s timeout)
- Scope checking reuses the same HTTP request (no extra API calls)
- Fine-grained tokens are automatically detected and allowed

## Migration from Bash

The Go implementation is functionally equivalent to the bash script at `/workspace/bin/claude-yolo` lines 534-699:

| Bash Function | Go Equivalent |
|--------------|---------------|
| `parse_env_file()` | `parseEnvFile()` |
| `find_github_token()` | `FindToken()` |
| `validate_github_token()` | `ValidateToken()` |
| `check_github_token_scopes()` | `CheckScopes()` |
| `ensure_github_token()` | (integrate into main) |

## Type Safety

The Go implementation provides type safety:

```go
// TokenResult clearly shows what's returned
type TokenResult struct {
    Token  string  // The actual token value
    Source string  // Where it was found
}

// ValidationResult provides structured scope information
type ValidationResult struct {
    Valid       bool     // Whether token is valid
    Scopes      string   // Raw scopes from GitHub
    BroadScopes []string // Dangerous scopes found
}
```
