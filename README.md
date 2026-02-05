# claude-yolo

Run Claude Code in an isolated Docker container with `--dangerously-skip-permissions`.

## Quick Start

```bash
# In any Rails project
cc --yolo
```

## What it does

When you pass `--yolo`, the script:

1. Detects your project's Ruby version from `.ruby-version` or `Gemfile`
2. Starts Chrome with remote debugging (if not already running)
3. Launches a Docker container with:
   - Host network access (for Postgres and Chrome CDP)
   - Your project mounted at `/workspace`
   - Persistent volumes for gems, node_modules, and Claude auth
4. Runs `claude --dangerously-skip-permissions` inside the container

Without `--yolo`, it passes through to the native `claude` command.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ Host Machine                                        │
│  ┌─────────────┐  ┌─────────────┐                   │
│  │ Chrome      │  │ Postgres    │                   │
│  │ :9222 (CDP) │  │ :5432       │                   │
│  └──────▲──────┘  └──────▲──────┘                   │
│         │                │                          │
│  ───────┴────────────────┴───────── host network    │
│                                                     │
│  ┌─────────────────────────────────────────────┐    │
│  │ Docker Container (--network=host)           │    │
│  │                                             │    │
│  │  Claude Code + Ruby/Rails/Node              │    │
│  │                                             │    │
│  │  Mounts:                                    │    │
│  │   - /workspace (bind: worktree path)        │    │
│  │   - ~/.claude (named volume for auth)       │    │
│  │   - gems cache (named volume)               │    │
│  │   - node_modules (named volume)             │    │
│  └─────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

## Container Naming

Each git worktree gets its own container and volumes, named by a hash of the worktree path:

- Container: `claude-yolo-a1b2c3d4`
- Volumes: `claude-yolo-a1b2c3d4-home`, `claude-yolo-a1b2c3d4-gems`, etc.

If a container is already running for your worktree, `cc --yolo` attaches to it.

## Installation

1. Clone this repo:
   ```bash
   git clone git@github.com:rickgorman/claude-yolo.git ~/work/claude-yolo
   ```

2. Update your shell alias (in `~/.aliases.local` or similar):
   ```bash
   alias cc="~/work/claude-yolo/bin/claude-yolo"
   ```

3. Reload your shell:
   ```bash
   source ~/.zshrc  # or ~/.bashrc
   ```

## Requirements

- Docker
- Chrome (for CDP support)
- PostgreSQL running on localhost:5432

## Scope (v1)

- Rails projects only
- Unit/request specs (no Capybara/headless Chrome in container)
- Host Postgres via localhost
- Chrome on host with remote debugging

## License

Private repository - not for redistribution.
