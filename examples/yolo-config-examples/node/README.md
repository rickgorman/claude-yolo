# Node.js Example

A Node.js application with environment-based configuration.

## Structure

```
.yolo/
├── strategy     # Force Node strategy
├── env          # Environment variables
└── ports        # Port mappings
```

## Files

### `strategy`
```
node
```

### `env`
```bash
NODE_ENV=development
PORT=3000
API_BASE_URL=https://api.example.com
ENABLE_DEBUG=true
MONGODB_URI=mongodb://localhost:27017/myapp
```

### `ports`
```
3000:3000
27017:27017
```

## Use Case

You have a Node.js application that reads configuration from environment variables. Instead of passing them via `--env` flags every time, you define them in `.yolo/env` for convenient development.

## Copy This Example

```bash
mkdir -p .yolo
cp examples/yolo-config-examples/node/* .yolo/
nano .yolo/env  # Customize for your app
```

## Usage

The environment variables will be available in your Node app:

```javascript
// In your Node app
const port = process.env.PORT || 3000;
const apiUrl = process.env.API_BASE_URL;
const debug = process.env.ENABLE_DEBUG === 'true';
```

## Security Note

If you add API keys or secrets to `.yolo/env`, make sure to:

1. Add to `.gitignore`:
   ```bash
   echo ".yolo/env" >> .gitignore
   ```

2. Document required variables in a `.yolo/env.example`:
   ```bash
   cp .yolo/env .yolo/env.example
   # Remove sensitive values from .yolo/env.example
   git add .yolo/env.example
   ```
