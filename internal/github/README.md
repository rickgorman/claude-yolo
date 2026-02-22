# github Package

This package provides GitHub token detection, validation, and scope checking for the claude-yolo Go rewrite.

## Features

- **Token Detection**: Automatically finds GitHub tokens from multiple sources
- **Token Validation**: Validates tokens against the GitHub API
- **Scope Checking**: Detects dangerous scopes that could allow destructive operations

## Token Sources

The package searches for GitHub tokens in the following order:

1. `GH_TOKEN` environment variable
2. `GITHUB_TOKEN` environment variable
3. `.env` file in the project directory
4. `~/.env` file
5. `~/.config/gh/hosts.yml` (or `$XDG_CONFIG_HOME/gh/hosts.yml`)

## Usage

### Finding a Token

```go
import "github.com/rickgorman/claude-yolo/internal/github"

result, err := github.FindToken("/path/to/project")
if err != nil {
    log.Fatal(err)
}

fmt.Printf("Found token from: %s\n", result.Source)
fmt.Printf("Token: %s\n", result.Token)
```

### Validating a Token

```go
valid, err := github.ValidateToken(token)
if err != nil {
    log.Fatal(err)
}

if !valid {
    log.Fatal("Invalid token")
}
```

### Checking Token Scopes

```go
result, err := github.CheckScopes(token)
if err != nil {
    log.Fatal(err)
}

if !result.Valid {
    log.Fatal("Invalid token")
}

if len(result.BroadScopes) > 0 {
    fmt.Printf("Warning: Token has dangerous scopes: %v\n", result.BroadScopes)
}
```

## Dangerous Scopes

The following scopes are considered dangerous and will trigger warnings:

- `delete_repo` - Can delete repositories
- `admin:org` - Full organization admin access
- `admin:enterprise` - Full enterprise admin access
- `admin:gpg_key` - Can manage GPG keys
- `admin:public_key` - Can manage SSH public keys
- `admin:ssh_signing_key` - Can manage SSH signing keys

## Fine-Grained Tokens

Fine-grained GitHub tokens do not return an `X-OAuth-Scopes` header and are considered safe by design. The package automatically detects these and allows them without warnings.

## .env File Format

The package supports the following formats in `.env` files:

```bash
GH_TOKEN=ghp_your_token_here
GITHUB_TOKEN=ghp_your_token_here
export GH_TOKEN=ghp_your_token_here
export GITHUB_TOKEN="ghp_your_token_here"
GH_TOKEN='ghp_your_token_here'
```

## Files

- **env.go**: Parse `.env` files to extract GitHub tokens
- **token.go**: Find tokens from multiple sources
- **validation.go**: Validate tokens and check for dangerous scopes

## Testing

Run tests with:

```bash
go test ./internal/github/...
```

All tests are comprehensive and cover:
- Token extraction from various `.env` formats
- Token discovery from multiple sources
- Scope detection and validation
- Error handling
