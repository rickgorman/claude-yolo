# AGENTS.md - AI Agent Playbook for claude-yolo

This document contains procedures and playbooks for AI agents working on claude-yolo.

## Table of Contents

- [CI Watch-Fix Loop](#ci-watch-fix-loop)
- [Go Development Workflow](#go-development-workflow)
- [Adding New Strategies](#adding-new-strategies)
- [Testing Procedures](#testing-procedures)
- [Release Process](#release-process)

---

## CI Watch-Fix Loop

### Purpose
Monitor GitHub Actions CI and automatically fix failures until all checks pass green.

### Procedure

1. **Monitor CI Status**
   ```bash
   gh run list --branch BRANCH_NAME --limit 1
   gh run view RUN_ID
   ```

2. **Identify Failures**
   ```bash
   gh run view RUN_ID --log-failed
   ```

3. **Categorize Failures**

   **A. Linting Failures** (Shellcheck, golangci-lint)
   - Read error output
   - Fix code issues
   - Commit: `Fix lint: [description]`
   - Push and re-monitor

   **B. Unit Test Failures**
   - Check if bash tests need Go binary adaptation
   - Check if Go tests have actual bugs
   - Fix code or update tests
   - Commit: `Fix tests: [description]`
   - Push and re-monitor

   **C. Integration Test Failures**
   - Check Docker build issues
   - Check strategy detection issues
   - Fix underlying code
   - Commit: `Fix integration: [description]`
   - Push and re-monitor

   **D. Build Failures**
   - Check compilation errors
   - Check missing dependencies
   - Fix `go.mod` or code
   - Commit: `Fix build: [description]`
   - Push and re-monitor

4. **Iterate Until Green**
   - Each fix should be atomic (one issue per commit)
   - Re-run CI after each push
   - Don't stop until all checks are ✅

5. **Success Criteria**
   - All jobs show ✅ green checkmark
   - No ❌ failures
   - PR shows "All checks have passed"

### Common Fixes

**Shellcheck trying to lint binary**:
```yaml
# .github/workflows/test.yml
- name: Lint bin/claude-yolo-bash  # Not bin/claude-yolo
  run: shellcheck -x -S warning -e SC1090 bin/claude-yolo-bash
```

**Tests expecting bash script**:
```bash
# test/lib/common.sh - Auto-detect binary vs script
if file "$CLI" 2>/dev/null | grep -q "executable"; then
  _cli_to_source="$CLI_BASH"  # Use bash version for sourcing
fi
```

**Go compilation errors**:
```bash
# Check missing imports
go mod tidy
go build ./...
```

---

## Go Development Workflow

### Adding a New Package

1. **Create package structure**
   ```bash
   mkdir -p internal/newpackage
   cd internal/newpackage
   ```

2. **Create doc.go with package docs**
   ```go
   // Package newpackage provides [description].
   //
   // [Detailed explanation]
   package newpackage
   ```

3. **Implement functionality**
   - Use clear interfaces
   - Proper error handling
   - Idiomatic Go patterns

4. **Add tests**
   ```bash
   # Create test file
   touch newpackage_test.go

   # Write tests
   # Run tests
   go test ./internal/newpackage/...
   ```

5. **Update imports**
   ```bash
   go mod tidy
   ```

### Code Quality Checklist

- [ ] All exported functions have comments
- [ ] Error returns are checked (errcheck)
- [ ] No unnecessary abstractions
- [ ] Tests cover main paths
- [ ] golangci-lint passes
- [ ] go fmt applied
- [ ] go vet passes

### Git Hooks

**Install pre-commit hooks** for automatic quality checks:

```bash
make install-hooks
```

The pre-commit hook runs before each commit:
- ✅ Checks code formatting (`gofmt`)
- ✅ Runs `go vet` for common mistakes
- ✅ Runs `golangci-lint` if available
- ⚠️ Warns about debug statements (`fmt.Print`, `TODO`, etc.)
- ✅ Ensures code builds
- ✅ Runs quick tests (`go test -short`)

**Bypass when needed**:
```bash
git commit --no-verify  # Use sparingly!
```

**Troubleshooting**:
```bash
# Reinstall hooks
rm .git/hooks/pre-commit
make install-hooks

# Test hook manually
bash -x .git-hooks/pre-commit
```

See [.git-hooks/README.md](.git-hooks/README.md) for full documentation.

---

## Adding New Strategies

### Overview
Strategies detect and configure different project types (Rails, Node, Python, etc.).

### Procedure

1. **Create strategy directory**
   ```bash
   mkdir -p strategies/mynewenv
   cd strategies/mynewenv
   ```

2. **Create detect.sh script**
   ```bash
   #!/bin/bash
   # Detection script for mynewenv
   # Outputs: confidence(0-100) evidence

   confidence=0
   evidence=""

   # Check for strong signals
   if [[ -f "mynewenv.config" ]]; then
     confidence=90
     evidence="mynewenv.config found"
   fi

   echo "$confidence $evidence"
   ```

3. **Create Dockerfile**
   ```dockerfile
   FROM ubuntu:22.04

   # Install mynewenv runtime
   RUN apt-get update && apt-get install -y mynewenv

   # Set working directory
   WORKDIR /workspace

   # Install Claude CLI
   RUN curl -fsSL https://anthropic.com/install.sh | sh

   CMD ["claude", "chat"]
   ```

4. **Create entrypoint.sh** (if needed)
   ```bash
   #!/bin/bash
   # Custom entrypoint for mynewenv

   exec "$@"
   ```

5. **Implement Go strategy**
   ```go
   // internal/strategy/mynewenv.go
   package strategy

   type MyNewEnvStrategy struct {
       BaseStrategy
   }

   func NewMyNewEnvStrategy() *MyNewEnvStrategy {
       return &MyNewEnvStrategy{
           BaseStrategy: BaseStrategy{name: "mynewenv"},
       }
   }

   // Implement Strategy interface methods
   // - Detect()
   // - Volumes()
   // - EnvVars()
   // - DefaultPorts()
   // - InfoMessage()
   ```

6. **Register in detector**
   ```go
   // internal/strategy/detector.go
   func (d *Detector) GetStrategy(name string) (Strategy, error) {
       switch name {
       // ... existing cases ...
       case "mynewenv":
           return NewMyNewEnvStrategy(), nil
       }
   }
   ```

7. **Test the strategy**
   ```bash
   # Create test project
   mkdir /tmp/test-mynewenv
   touch /tmp/test-mynewenv/mynewenv.config

   # Test detection
   ./bin/claude-yolo --detect /tmp/test-mynewenv
   # Should output: mynewenv
   ```

---

## Testing Procedures

### Running Tests

**Go unit tests**:
```bash
make test
# or
go test ./...
```

**Specific package**:
```bash
go test ./internal/github/... -v
```

**With coverage**:
```bash
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out
```

**Bash integration tests**:
```bash
./test/run-integration-tests.sh
./test/run-unit-tests.sh
./test/run-all-tests.sh
```

**Specific test**:
```bash
./test/test-strategy-detection.sh
./test/test-ports.sh
```

### Writing New Tests

**Go unit test pattern**:
```go
func TestMyFunction(t *testing.T) {
    tests := []struct {
        name    string
        input   string
        want    string
        wantErr bool
    }{
        {"valid input", "foo", "bar", false},
        {"invalid input", "", "", true},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got, err := MyFunction(tt.input)
            if (err != nil) != tt.wantErr {
                t.Errorf("MyFunction() error = %v, wantErr %v", err, tt.wantErr)
                return
            }
            if got != tt.want {
                t.Errorf("MyFunction() = %v, want %v", got, tt.want)
            }
        })
    }
}
```

---

## Release Process

### Version Bumping

1. **Update version constant**
   ```go
   // cmd/claude-yolo/main.go
   const version = "2.1.0"
   ```

2. **Update CHANGELOG.md**
   ```markdown
   ## [2.1.0] - 2026-02-XX

   ### Added
   - New feature X

   ### Changed
   - Improved Y

   ### Fixed
   - Bug Z
   ```

3. **Commit and tag**
   ```bash
   git add cmd/claude-yolo/main.go CHANGELOG.md
   git commit -m "Bump version to 2.1.0"
   git tag -a v2.1.0 -m "Release v2.1.0"
   git push && git push --tags
   ```

### Build for Release

```bash
# Build optimized binary
make build

# Test binary
./bin/claude-yolo --version

# Cross-compile if needed
GOOS=darwin GOARCH=amd64 go build -o bin/claude-yolo-darwin-amd64 ./cmd/claude-yolo
GOOS=linux GOARCH=amd64 go build -o bin/claude-yolo-linux-amd64 ./cmd/claude-yolo
```

---

## Common Troubleshooting

### "Cannot execute binary file"
- Bash tests trying to source Go binary
- Solution: Tests should use `bin/claude-yolo-bash` for sourcing functions

### "Package not found"
```bash
go mod tidy
go mod download
```

### "Linter errors"
```bash
golangci-lint run ./...
# Fix reported issues
```

### "Docker build fails"
```bash
# Check Dockerfile syntax
cd strategies/rails && docker build .

# Test with verbose output
docker build --progress=plain .
```

### "Tests fail in CI but pass locally"
- Check for environment differences
- Check for timing issues
- Add debug output to CI logs

---

## Best Practices

### Commits
- ✅ Small, focused commits
- ✅ Clear commit messages
- ✅ One logical change per commit
- ❌ Don't mix refactoring with features
- ❌ Don't commit WIP code to main

### Code Review
- ✅ Run all tests before PR
- ✅ Run linter before PR
- ✅ Update documentation
- ✅ Add tests for new features
- ❌ Don't merge failing CI

### Performance
- ✅ Profile before optimizing
- ✅ Benchmark critical paths
- ✅ Use `go test -bench`
- ❌ Don't premature optimize

---

## Agent-Specific Notes

### For Autonomous Agents

**When CI fails**:
1. Never stop - always fix and retry
2. Read full logs, don't guess
3. Make minimal fixes
4. Test locally before pushing
5. Document non-obvious fixes

**When unsure**:
1. Check existing code for patterns
2. Read package documentation
3. Run locally to verify
4. Ask for clarification if truly stuck (rare)

**Time management**:
1. Prioritize high-impact tasks
2. Batch related changes
3. Use parallel agents for big tasks
4. Don't get stuck on edge cases

---

## Future Enhancements

### Planned Improvements
- [ ] Automated performance regression detection
- [ ] Fuzzing integration
- [ ] Security scanning automation
- [ ] Automatic dependency updates
- [ ] Release notes generation
- [ ] Benchmark tracking over time

### Ideas for Agents
- Auto-fix common test failures
- Suggest performance optimizations
- Generate missing test cases
- Identify code coverage gaps
- Propose architectural improvements

---

**Last Updated**: 2026-02-22
**Maintained By**: Autonomous AI Agents + Human Maintainers
