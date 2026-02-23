# Git Hooks for claude-yolo Development

This directory contains Git hooks to maintain code quality during development.

## Available Hooks

### pre-commit

Runs before each commit to ensure code quality:

- ✅ **Code Formatting**: Checks `gofmt` compliance
- ✅ **Go Vet**: Catches common Go mistakes
- ✅ **Linting**: Runs `golangci-lint` if installed
- ⚠️ **Debug Statements**: Warns about `fmt.Print`, `TODO`, etc.
- ✅ **Build Check**: Ensures code compiles
- ✅ **Quick Tests**: Runs `go test -short`

## Installation

### Automatic (Recommended)

```bash
make install-hooks
```

Or manually:

```bash
./git-hooks/install.sh
```

### Manual Installation

Create a symlink to the hook:

```bash
ln -sf ../../.git-hooks/pre-commit .git/hooks/pre-commit
```

## Verification

After installation, verify the hook is active:

```bash
ls -la .git/hooks/pre-commit
# Should show a symlink to ../../.git-hooks/pre-commit
```

Test the hook:

```bash
# Make a small change
echo "// test" >> cmd/claude-yolo/main.go
git add cmd/claude-yolo/main.go

# Try to commit (hook should run)
git commit -m "Test commit"

# Revert the test change
git reset HEAD cmd/claude-yolo/main.go
git checkout -- cmd/claude-yolo/main.go
```

## Bypassing Hooks

In rare cases where you need to bypass the hooks:

```bash
git commit --no-verify
```

**Warning**: Only use `--no-verify` when you're certain the code is correct. Bypassing hooks can introduce bugs or formatting issues.

## Requirements

### Required

- Go 1.22+

### Optional (for full functionality)

- `golangci-lint` - Install with:
  ```bash
  brew install golangci-lint          # macOS
  go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
  ```

## Customization

To modify the checks, edit `.git-hooks/pre-commit` and adjust the checks as needed.

Common modifications:

### Skip Test Run

If tests are slow, comment out the test section:

```bash
# # 6. Run tests (quick)
# echo -n "Running tests... "
# ...
```

### Add Custom Checks

Add your own checks before the final success message:

```bash
# Custom check: ensure CHANGELOG updated
if ! git diff --cached --name-only | grep -q "CHANGELOG.md"; then
    echo -e "${YELLOW}⚠${NC} CHANGELOG.md not updated"
fi
```

### Change Test Timeout

Modify the test command:

```bash
# Run all tests (not just -short)
go test ./...

# Or with a timeout
go test -timeout 30s ./...
```

## Troubleshooting

### Hook doesn't run

```bash
# Check if symlink exists
ls -la .git/hooks/pre-commit

# Reinstall
rm -f .git/hooks/pre-commit
ln -sf ../../.git-hooks/pre-commit .git/hooks/pre-commit
```

### Hook fails immediately

```bash
# Ensure it's executable
chmod +x .git-hooks/pre-commit

# Check for errors
bash -x .git-hooks/pre-commit
```

### Tests fail during commit

```bash
# Run tests manually to see full output
go test ./... -v

# Or skip tests temporarily
git commit --no-verify
```

### golangci-lint takes too long

The hook runs with a 5-minute deadline. If it's still too slow:

```bash
# Edit .git-hooks/pre-commit and reduce scope
golangci-lint run --deadline=2m --fast
```

Or install golangci-lint's cache:

```bash
golangci-lint cache status
```

## CI Integration

The same checks run in GitHub Actions CI. The pre-commit hook helps catch issues before pushing, making the CI feedback loop faster.

See `.github/workflows/test.yml` for the CI configuration.
