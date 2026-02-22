# Security Audit

This document covers the security analysis of claude-yolo and recommendations for secure usage.

## Executive Summary

✅ **Overall Assessment**: The codebase follows good security practices with proper input handling and no critical vulnerabilities found.

⚠️ **Areas for Improvement**: Some defense-in-depth enhancements recommended for sensitive file permissions and volume mount isolation.

## Security Analysis

### 1. Command Injection Risks ✅ SECURE

**Analysis**: All command execution uses `exec.Command()` with separate arguments rather than shell interpolation.

**Examples**:
```go
// SECURE: Arguments passed separately, not concatenated into shell string
cmd := exec.Command(scriptPath, projectPath)
cmd := exec.Command("docker", "ps", "--filter", "name="+containerName)
```

**Verdict**: ✅ No command injection vulnerabilities found. All external inputs are passed as separate arguments to `exec.Command`, preventing shell injection.

### 2. Path Traversal Risks ✅ MOSTLY SECURE

**Analysis**: File paths are constructed using `filepath.Join()` which handles path separators correctly.

**Potential Concerns**:
- User-provided paths in `--env-file` flag could reference sensitive files
- `.yolo/` directory files are read without strict validation

**Mitigations**:
- Project paths come from `git rev-parse --show-toplevel` (trusted source)
- `.yolo/` directory has explicit trust mechanism requiring user approval
- File reads use `os.ReadFile()` which doesn't follow symlinks by default

**Recommendations**:
1. ⚠️ Consider validating that `.yolo/` files don't contain symlinks to sensitive locations
2. ⚠️ Add bounds checking for `--env-file` to prevent reading arbitrary system files

### 3. Credential Handling ✅ SECURE

**Analysis**: GitHub tokens and credentials are handled carefully.

**Good Practices Observed**:
- Tokens are never logged or printed (only source location is shown)
- Token validation happens before usage
- Broad scope detection warns users about overly permissive tokens
- Tokens passed to Docker via API, not shell commands
- Option to skip GitHub token requirement (`CLAUDE_YOLO_NO_GITHUB=1`)

**File Permission Concerns**:
```go
// .env files may contain secrets but permissions aren't checked
token, err := parseEnvFile(projectEnv)  // No permission validation
```

**Recommendations**:
1. ⚠️ Check `.env` file permissions and warn if world-readable (mode > 0600)
2. ⚠️ Document best practices for `.env` file permissions in README
3. ✅ Consider adding `--no-github-token` flag as alternative to env var

**Example Security Warning Code**:
```go
func warnInsecurePermissions(path string) {
    info, err := os.Stat(path)
    if err != nil {
        return
    }

    mode := info.Mode().Perm()
    if mode&0044 != 0 { // World or group readable
        ui.Warn("File %s is readable by others (permissions: %o)", path, mode)
        ui.Info("Recommended: chmod 600 %s", path)
    }
}
```

### 4. Docker Security ✅ SECURE WITH CAVEATS

**Container Isolation**:
- Each project gets isolated container with unique name
- Volume names are project-specific using path hash
- No `--privileged` flag usage
- No host network mode

**Volume Mounts**:
```go
// Home directory mounted with full access
volumes = append(volumes, homeDir+"/.claude:/home/claude/.claude")
```

**Concerns**:
- `~/.claude` directory mounted read-write gives container full access to Claude config
- Worktree mounted read-write could allow container to modify source

**Recommendations**:
1. ⚠️ Consider mounting `~/.claude` read-only for most operations
2. ⚠️ Document that containers have write access to source code
3. ✅ Add `--read-only-workspace` flag for audit/review workflows

### 5. Input Validation ✅ GOOD

**CLI Argument Parsing**:
- All flags have proper validation
- Required arguments are checked before use
- Invalid values produce clear error messages

**Port Handling**:
- Ports validated as integers
- Port conflicts detected and resolved
- Privileged port usage (< 1024) allowed but could be restricted

**Strategy Names**:
- Validated against known strategies before use
- Invalid strategies produce helpful error with available options

### 6. Secrets in .yolo/ Configuration ⚠️ NEEDS DOCUMENTATION

**Current State**:
- `.yolo/env` can contain secrets
- Trust mechanism prevents arbitrary `.yolo/` execution
- No automatic `.gitignore` entries

**Recommendations**:
1. ⚠️ Add `.yolo/env` to project `.gitignore` automatically
2. ⚠️ Provide `.yolo/env.example` template in examples
3. ⚠️ Warn if `.yolo/env` is tracked in git
4. ✅ Document secret management best practices

### 7. File Permission on Sensitive Files ⚠️ IMPROVEMENT NEEDED

**Trust File**:
```go
trustFile := filepath.Join(homeDir, ".claude", ".yolo-trusted")
file, err := os.OpenFile(trustFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
```

**Issue**: Trust file created with mode `0644` (world-readable), allowing other users to see which `.yolo/` configs you've trusted.

**Fix**:
```go
// Create with mode 0600 (user-only read/write)
file, err := os.OpenFile(trustFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
```

**Recommendation**: ⚠️ Change trust file permissions to `0600`

## Security Best Practices for Users

### 1. GitHub Token Scope

Use minimal scopes for your GitHub token:
```bash
# Good: repo-only access
gh auth login --scopes repo

# Bad: admin:org, delete_repo, etc.
```

### 2. .env File Permissions

Protect files containing secrets:
```bash
# Set restrictive permissions
chmod 600 .env
chmod 600 .yolo/env

# Add to .gitignore
echo ".yolo/env" >> .gitignore
```

### 3. .yolo/ Configuration Review

Before trusting a `.yolo/` directory:
```bash
# Review all files
cat .yolo/strategy
cat .yolo/env
cat .yolo/ports
cat .yolo/Dockerfile

# Check for suspicious commands or secrets
grep -r "curl\|wget\|chmod\|eval" .yolo/
```

### 4. Container Isolation

Understand what containers can access:
- ✅ Your source code (read-write)
- ✅ Your `~/.claude` config (read-write)
- ✅ Your git credentials
- ❌ Other files on your system (not mounted)

### 5. Untrusted Projects

When working with untrusted code:
```bash
# Review .yolo/ configuration before trusting
cd untrusted-project
cat .yolo/Dockerfile  # Check for malicious build steps
cat .yolo/env         # Check for credential exfiltration

# Don't use --trust-yolo with untrusted projects
claude-yolo --yolo  # Prompts for review first
```

## Known Limitations

1. **Container Escape**: Containers are not a security boundary. A determined attacker could escape the container.
2. **Source Modification**: Containers have write access to your source code.
3. **Network Access**: Containers have network access and could exfiltrate data.
4. **Shared Docker Socket**: If Docker socket is mounted (not currently done), containers could control Docker host.

## Threat Model

**Trusted Scenarios** (Current design):
- Working on your own code
- Collaborating with trusted team members
- Using vetted `.yolo/` configurations

**Untrusted Scenarios** (Use with caution):
- Cloning unknown repositories
- Running code from unverified sources
- Executing arbitrary `.yolo/Dockerfile` without review

**Not Protected Against**:
- Malicious code in your project's dependencies
- Compromised npm/gem/pip packages
- Container escape exploits
- Docker daemon vulnerabilities

## Security Disclosures

If you discover a security vulnerability in claude-yolo, please report it via:
- GitHub Security Advisories: https://github.com/rickgorman/claude-yolo/security/advisories
- Email: [security contact TBD]

Please do not open public issues for security vulnerabilities.

## Changelog

- **2025-02-22**: Initial security audit (v2.0.0-dev)
  - Analyzed command injection risks: ✅ Secure
  - Analyzed credential handling: ✅ Secure with recommendations
  - Analyzed file permissions: ⚠️ Improvements recommended
  - Analyzed Docker isolation: ✅ Secure with documentation needed
