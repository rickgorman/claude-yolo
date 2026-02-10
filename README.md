# claude-yolo

Run Claude Code in an isolated Docker container with `--dangerously-skip-permissions`.

## Quick Start

```bash
# In any supported project
cc --yolo
```

## What it does

When you pass `--yolo`, the script:

1. **Detects your project type** by scanning for key files (Gemfile, build.gradle, etc.)
2. **Presents a menu** if multiple environments match (or auto-selects if confident)
3. Launches a Docker container with:
   - Host network access (for Postgres, Chrome CDP, ADB, etc.)
   - Your project mounted at `/workspace`
   - Persistent volumes for dependencies and Claude auth
4. Runs `claude --dangerously-skip-permissions` inside the container

Without `--yolo`, it passes through to the native `claude` command.

## Supported Environments

### Rails

Detected by: `Gemfile` with rails, `config/application.rb`, `.ruby-version`, `bin/rails`

Container includes:
- Ruby (auto-detected version, installed via rbenv)
- Node.js 20 + Yarn
- PostgreSQL client (expects Postgres on host)
- Chrome CDP support (starts Chrome on host for browser automation)

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
│  │   - strategy-specific dep caches            │    │
│  └─────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

## Flags

```
cc --yolo                        # Auto-detect environment
cc --yolo --strategy rails       # Skip detection, use Rails
cc --yolo --strategy android     # Skip detection, use Android
cc --yolo --build                # Force rebuild the Docker image
cc --yolo --build --strategy android   # Rebuild a specific image
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

## Installation

1. Clone this repo:
   ```bash
   git clone git@github.com:rickgorman/claude-yolo.git ~/work/claude-yolo
   ```

2. Update your shell alias:
   ```bash
   alias cc="~/work/claude-yolo/bin/claude-yolo"
   ```

3. Reload your shell:
   ```bash
   source ~/.zshrc
   ```

## Requirements

- Docker
- Chrome (for CDP support, used by Rails strategy)
- PostgreSQL on localhost:5432 (for Rails)
- Android device with wireless debugging (for Android)

## License

Private repository - not for redistribution.
