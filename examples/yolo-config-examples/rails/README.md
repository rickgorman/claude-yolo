# Rails Example

A typical Rails application configuration with custom ports and environment variables.

## Structure

```
.yolo/
├── strategy     # Force Rails strategy
├── ports        # Custom port mappings
└── env          # Environment variables
```

## Files

### `strategy`
```
rails
```

### `ports`
```
3001:3000    # Rails server (avoiding conflict with local Rails)
5433:5432    # PostgreSQL (avoiding conflict with local Postgres)
6380:6379    # Redis (avoiding conflict with local Redis)
```

### `env`
```bash
RAILS_ENV=development
DATABASE_URL=postgresql://postgres:password@localhost:5432/myapp_development
REDIS_URL=redis://localhost:6379/0
RAILS_LOG_LEVEL=debug
```

## Use Case

You're running a Rails app with Postgres and Redis. You already have local instances of these services, so you map to different host ports to avoid conflicts.

## Copy This Example

```bash
# Create .yolo directory
mkdir -p .yolo

# Copy files
cp examples/yolo-config-examples/rails/* .yolo/

# Customize for your app
nano .yolo/env  # Edit database name, etc.
```

## Security Note

Add `.yolo/env` to `.gitignore` if it contains secrets:

```bash
echo ".yolo/env" >> .gitignore
```

## Testing

Start claude-yolo and verify port mappings:

```bash
claude-yolo --yolo --trust-yolo

# In container, Rails will be on port 3000
# On host, access via http://localhost:3001
```
