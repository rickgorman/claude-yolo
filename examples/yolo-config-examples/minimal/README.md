# Minimal Example

The simplest `.yolo/` configuration - just override strategy detection.

## Structure

```
.yolo/
└── strategy
```

## Use Case

Your project structure might not match typical patterns, or you want to force a specific strategy regardless of what files are present.

## Copy This Example

```bash
mkdir .yolo
echo "rails" > .yolo/strategy
```

Or for a Node project:

```bash
mkdir .yolo
echo "node" > .yolo/strategy
```

## Available Strategies

- `rails` - Ruby on Rails applications
- `node` - Node.js applications
- `python` - Python applications
- `go` - Go applications
- `rust` - Rust applications
- `android` - Android projects
- `jekyll` - Jekyll static sites
- `generic` - Generic Linux environment
