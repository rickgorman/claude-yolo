package git

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
)

// UserConfig represents git user configuration.
type UserConfig struct {
	Name  string
	Email string
}

// ExtractUserConfig reads git user.name and user.email from ~/.gitconfig
// and any included config files.
func ExtractUserConfig() (*UserConfig, error) {
	config := &UserConfig{}

	homeDir, err := os.UserHomeDir()
	if err != nil {
		return config, err
	}

	gitconfig := filepath.Join(homeDir, ".gitconfig")
	if _, err := os.Stat(gitconfig); os.IsNotExist(err) {
		return config, nil
	}

	// Process gitconfig and included files
	visited := make(map[string]bool)
	queue := []string{gitconfig}

	for len(queue) > 0 && len(visited) < 10 { // Max depth 10 to prevent loops
		current := queue[0]
		queue = queue[1:]

		if visited[current] {
			continue
		}
		visited[current] = true

		file, err := os.Open(current)
		if err != nil {
			continue
		}

		scanner := bufio.NewScanner(file)
		for scanner.Scan() {
			line := strings.TrimSpace(scanner.Text())

			// Parse user.name
			if strings.HasPrefix(line, "name =") && config.Name == "" {
				config.Name = strings.TrimSpace(strings.TrimPrefix(line, "name ="))
			}

			// Parse user.email
			if strings.HasPrefix(line, "email =") && config.Email == "" {
				config.Email = strings.TrimSpace(strings.TrimPrefix(line, "email ="))
			}

			// Parse include.path
			if strings.HasPrefix(line, "path =") {
				includePath := strings.TrimSpace(strings.TrimPrefix(line, "path ="))
				// Expand ~
				if strings.HasPrefix(includePath, "~/") {
					includePath = filepath.Join(homeDir, includePath[2:])
				}
				if _, err := os.Stat(includePath); err == nil {
					queue = append(queue, includePath)
				}
			}
		}
		_ = file.Close()
	}

	return config, nil
}
