# .yolo/ Configuration Examples

The `.yolo/` directory allows you to customize how claude-yolo runs for your project.

## Directory Structure

```
.yolo/
├── strategy      # Override strategy detection (optional)
├── Dockerfile    # Custom Dockerfile (optional)
├── env           # Environment variables (optional)
└── ports         # Port mappings (optional)
```

## Configuration Files

### `strategy`

Override automatic strategy detection with a specific strategy:

```
rails
```

Available strategies: `rails`, `node`, `python`, `go`, `rust`, `android`, `jekyll`, `generic`

### `Dockerfile`

Provide a custom Dockerfile instead of using the strategy's default:

```dockerfile
FROM ruby:3.2

# Your custom build steps
RUN apt-get update && apt-get install -y postgresql-client
WORKDIR /workspace

# Custom entrypoint
CMD ["bash"]
```

### `env`

Define environment variables for your container:

```bash
# Development settings
NODE_ENV=development
DEBUG=true

# API keys (make sure to .gitignore .yolo/env!)
API_KEY=your_key_here
DATABASE_URL=postgresql://localhost/myapp_dev
```

Format supports:
- `KEY=VALUE` pairs
- `export KEY=VALUE` syntax
- Comments with `#`
- Quoted values: `KEY="value with spaces"`

### `ports`

Override default port mappings:

```
3000:3000
5432:5432
6379:6379
```

Format: `HOST_PORT:CONTAINER_PORT`

## Security

**Important**: .yolo/ configurations can execute arbitrary code via Dockerfiles and environment variables.

When you first use a `.yolo/` directory, claude-yolo will:
1. Show you what's in the configuration
2. Ask if you trust it
3. Store a hash in `~/.claude/.yolo-trusted`

To bypass the prompt:
```bash
claude-yolo --yolo --trust-yolo
```

## Examples

See the subdirectories for complete examples:
- `minimal/` - Just strategy override
- `rails/` - Rails app with custom ports
- `node/` - Node app with environment variables
- `python/` - Python app with custom Dockerfile
- `multi-service/` - App with multiple services (db, cache)

## Use Cases

### Force a Strategy

If auto-detection picks the wrong strategy:

```bash
echo "node" > .yolo/strategy
```

### Custom Ports

Avoid port conflicts by mapping to different host ports:

```bash
cat > .yolo/ports <<EOF
8080:3000
5433:5432
EOF
```

### Development Environment Variables

Set environment without cluttering your shell:

```bash
cat > .yolo/env <<EOF
NODE_ENV=development
LOG_LEVEL=debug
ENABLE_EXPERIMENTAL_FEATURES=true
EOF
```

### Custom Build Steps

Add dependencies not in the default Dockerfile:

```dockerfile
# .yolo/Dockerfile
FROM node:20

RUN apt-get update && apt-get install -y \
    imagemagick \
    ffmpeg

WORKDIR /workspace
```

## Tips

- **Version Control**: Commit `.yolo/strategy` and `.yolo/ports`, but add `.yolo/env` to `.gitignore` if it contains secrets
- **Team Sharing**: Share configurations with your team to ensure consistent development environments
- **Testing**: Use `--trust-yolo` in CI/CD pipelines to skip the trust prompt
- **Debugging**: Run with `--verbose` to see which .yolo/ settings are being applied
