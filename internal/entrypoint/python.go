package entrypoint

import (
	"fmt"
	"os"
	"path/filepath"
)

func runPythonEntrypoint(args []string, log func(string)) error {
	home := os.Getenv("HOME")

	// Initialize pyenv
	pyenvRoot := filepath.Join(home, ".pyenv")
	pyenvBin := filepath.Join(pyenvRoot, "bin")
	pyenvShims := filepath.Join(pyenvRoot, "shims")
	path := pyenvBin + ":" + pyenvShims + ":" + os.Getenv("PATH")
	os.Setenv("PATH", path)
	os.Setenv("PYENV_ROOT", pyenvRoot)

	// Install Python if PYTHON_VERSION is set and not already installed
	pythonVersion := os.Getenv("PYTHON_VERSION")
	if pythonVersion != "" {
		if !versionInstalled("pyenv", pythonVersion) {
			log(fmt.Sprintf("Installing Python %s (this may take a few minutes on first run)...", pythonVersion))
			// Run pyenv install with shell initialization
			installScript := fmt.Sprintf(`
				export PYENV_ROOT="$HOME/.pyenv"
				export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
				eval "$(pyenv init -)"
				pyenv install %s
			`, pythonVersion)
			if err := runInShell(installScript); err != nil {
				return fmt.Errorf("failed to install Python %s: %w", pythonVersion, err)
			}
		}
		// Set global version
		globalScript := fmt.Sprintf(`
			export PYENV_ROOT="$HOME/.pyenv"
			export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
			eval "$(pyenv init -)"
			pyenv global %s
		`, pythonVersion)
		if err := runInShell(globalScript); err != nil {
			return fmt.Errorf("failed to set Python version: %w", err)
		}
		log(fmt.Sprintf("Using Python %s", pythonVersion))
	}

	// Install pip packages if requirements.txt exists
	requirements := filepath.Join("/workspace", "requirements.txt")
	if fileExists(requirements) {
		log("Running pip install...")
		pipScript := `
			export PYENV_ROOT="$HOME/.pyenv"
			export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
			eval "$(pyenv init -)"
			pip install -r /workspace/requirements.txt
		`
		if err := runInShell(pipScript); err != nil {
			// Don't fail on pip install errors, just log
			log("Warning: pip install failed, continuing anyway")
		}
	}

	// Execute the command with pyenv environment
	execScript := fmt.Sprintf(`
		export PYENV_ROOT="$HOME/.pyenv"
		export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
		eval "$(pyenv init -)"
		exec %s
	`, shellEscape(args))

	return runInShell(execScript)
}
