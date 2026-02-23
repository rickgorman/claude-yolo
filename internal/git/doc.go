// Package git provides Git repository operations for claude-yolo.
//
// This package handles:
//   - Worktree path detection (finding the root of the Git repository)
//   - User configuration extraction from ~/.gitconfig
//   - Support for gitconfig include.path directives
//
// The extracted user.name and user.email are used to configure
// Git identity inside Docker containers, ensuring commits made
// within the container are properly attributed.
//
// Example usage:
//
//	// Get repository root
//	worktreePath, err := git.GetWorktreePath()
//
//	// Get Git user config
//	config, err := git.ExtractUserConfig()
//	if err == nil {
//	    env = append(env, "GIT_AUTHOR_NAME="+config.Name)
//	    env = append(env, "GIT_AUTHOR_EMAIL="+config.Email)
//	}
package git
