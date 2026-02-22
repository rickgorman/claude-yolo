// Package session manages Claude session directories for claude-yolo.
//
// This package handles:
//   - Session directory creation in ~/.claude/projects/
//   - Path hash-based session naming for isolation
//   - Migration from legacy yolo-sessions format
//   - .worktree-path file management
//
// Each project gets its own session directory based on the MD5 hash
// of its worktree path. This ensures different projects don't share
// session data while allowing the same project to reconnect to its
// existing session.
//
// Example usage:
//
//	// Ensure session directory exists
//	sessionDir, err := session.EnsureSessionDir(pathHash, worktreePath)
//
//	// Migrate legacy sessions (one-time)
//	session.MigrateYoloSessions()
//
// Session directories are created at:
//
//	~/.claude/projects/{hash}/
//
// Where {hash} is the first 8 characters of MD5(worktreePath).
package session
