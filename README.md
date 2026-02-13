# claude-yolo

Run Claude Code in an isolated Docker container with `--dangerously-skip-permissions`.

## What it does

When you pass `--yolo`, the script:

1. **Detects your project type** by scanning for key files (Gemfile, build.gradle, etc.)
2. **Presents a menu** if multiple environments match (or auto-selects if confident)
3. Launches a Docker container with:
   - Host network access (for Postgres, Chrome CDP, ADB, etc.)
   - Your project mounted at `/workspace`
   - Persistent volumes for dependencies and Claude auth
4. Bind-mounts `~/.claude/CLAUDE.md` and `~/.claude/commands/` read-only so your global instructions and slash commands are available inside the container
5. Runs `claude --dangerously-skip-permissions` inside the container

Without `--yolo`, it passes through to the native `claude` command.

## Installation

1. Clone this repo:
   ```bash
   git clone git@github.com:rickgorman/claude-yolo.git ~/work/claude-yolo
   ```

2. Add a shell alias to your shell config (`~/.zshrc`, `~/.bashrc`, etc.):
   ```bash
   alias cc="$HOME/work/claude-yolo/bin/claude-yolo"
   ```
   You can name the alias whatever you want — `cc`, `yolo`, `claude-yolo`, etc.
   Without `--yolo`, the alias passes through to the native `claude` CLI.

3. Reload your shell:
   ```bash
   source ~/.zshrc   # or ~/.bashrc
   ```

## Quick Start

```bash
cd your-project/

# Auto-detect environment and launch
cc --yolo

# Skip detection, use a specific strategy
cc --yolo --strategy rails

# Force rebuild the Docker image
cc --yolo --build

# Enable Chrome DevTools MCP for browser automation
cc --yolo --chrome

# Show raw Docker build output instead of the spinner
cc --yolo --verbose
```

## Flags

| Flag | Description |
|------|-------------|
| `--yolo` | Run in Docker container with full permission bypass |
| `--strategy <name>` | Skip auto-detection, use the specified strategy (rails, android, ...) |
| `--build` | Force rebuild the Docker image before running |
| `--verbose` | Show raw Docker build output instead of the spinner |
| `--chrome` | Launch Chrome on the host and inject a `chrome-devtools` MCP server into the container |

## GitHub Token

In `--yolo` mode, claude-yolo requires a valid GitHub token so that `gh` works inside the container. It searches these locations in order:

1. `GH_TOKEN` environment variable
2. `GITHUB_TOKEN` environment variable
3. `.env` file in the project directory
4. `~/.env`
5. `~/.config/gh/hosts.yml` (written by `gh auth login`)
6. `gh auth token` (macOS Keychain / system keyring)

The token is validated against `api.github.com/user` before launching the container.

If you don't use GitHub, skip this check:

```bash
export CLAUDE_YOLO_NO_GITHUB=1
cc --yolo
```

## Supported Environments

### Rails

Detected by: `Gemfile` with rails, `config/application.rb`, `.ruby-version`, `bin/rails`

Container includes:
- Ruby (auto-detected version, installed via rbenv)
- Node.js 20 + Yarn
- PostgreSQL client (`DB_HOST` defaults to `host.docker.internal`)
- GitHub CLI
- Chrome CDP support (with `--chrome`, starts Chrome on host for browser automation)

### Android

Detected by: `build.gradle(.kts)`, `AndroidManifest.xml`, `gradlew`, `com.android` plugin

Container includes:
- OpenJDK 17
- Android SDK (platform 34, build-tools 34.0.0)
- ADB with wireless debugging support
- Node.js 20 (for Claude Code)

**Note:** Android SDK tools require x86_64. On Apple Silicon Macs, the container
runs under Rosetta emulation.

#### Wireless Debugging

To connect to a physical Android device:

1. On the phone: Settings → Developer Options → Wireless Debugging → Enable
2. Tap "Pair device with pairing code" and note the IP:port and pairing code
3. Inside the container: `adb pair <ip>:<pair-port>` (enter the pairing code)
4. Then: `adb connect <ip>:<connect-port>` (the port shown on the main Wireless Debugging screen)

Or set `ANDROID_DEVICE=<ip>:<port>` before running to auto-connect:
```bash
ANDROID_DEVICE=192.168.1.42:5555 cc --yolo
```

### Unknown Projects

If no strategy matches, claude-yolo generates a prompt you can paste into Claude
to have it build a new strategy for your project type.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ Host Machine                                        │
│  ┌─────────────┐  ┌─────────────┐  ┌────────────┐  │
│  │ Chrome      │  │ Postgres    │  │ Android    │  │
│  │ :9222 (CDP) │  │ :5432       │  │ Phone      │  │
│  └──────▲──────┘  └──────▲──────┘  └──────▲─────┘  │
│         │                │                │         │
│  ───────┴────────────────┴────────────────┴── net   │
│                                                     │
│  ┌─────────────────────────────────────────────┐    │
│  │ Docker Container (--network=host)           │    │
│  │                                             │    │
│  │  Claude Code + strategy-specific tools      │    │
│  │                                             │    │
│  │  Mounts:                                    │    │
│  │   - /workspace (bind: worktree path)        │    │
│  │   - ~/.claude (named volume for auth)       │    │
│  │   - ~/.claude/commands (bind: read-only)    │    │
│  │   - strategy-specific dep caches            │    │
│  └─────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

## Container Naming

Each git worktree + strategy combination gets its own container and volumes:

- Container: `claude-yolo-a1b2c3d4-rails`
- Volumes: `claude-yolo-a1b2c3d4-home`, `claude-yolo-a1b2c3d4-gems`, etc.

If a container is already running, `cc --yolo` attaches to it.

## Adding a New Strategy

Each strategy lives in `strategies/<name>/` with:

| File | Purpose |
|------|---------|
| `detect.sh` | Detection heuristics — outputs `CONFIDENCE:<0-100>` and `EVIDENCE:<description>` |
| `Dockerfile` | Container setup with language runtime, tools, and Claude Code |
| `entrypoint.sh` | Dependency installation and env setup, ends with `exec "$@"` |
| `platform` | *(optional)* Required Docker platform, e.g. `linux/amd64` |

## Requirements

- Docker
- Chrome (only needed with `--chrome` flag)
- PostgreSQL on localhost:5432 (for Rails)
- Android device with wireless debugging (for Android)

## License

[MIT](LICENSE)
