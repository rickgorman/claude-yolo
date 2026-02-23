.PHONY: build test lint install clean test-unit test-integration test-all install-hooks bench bench-all build-all build-darwin-amd64 build-darwin-arm64 build-linux-amd64 build-linux-arm64

# Go binary name
BINARY=claude-yolo
BUILD_DIR=bin

# Go build flags
GO_BUILD_FLAGS=-ldflags="-s -w"

# Detect current platform
GOOS=$(shell go env GOOS)
GOARCH=$(shell go env GOARCH)

build:
	@echo "Building $(BINARY) for $(GOOS)/$(GOARCH)..."
	@mkdir -p $(BUILD_DIR)
	@go build $(GO_BUILD_FLAGS) -o $(BUILD_DIR)/$(BINARY) ./cmd/claude-yolo
	@echo "✓ Built: $(BUILD_DIR)/$(BINARY)"

build-dev:
	@echo "Building $(BINARY) (dev mode)..."
	@mkdir -p $(BUILD_DIR)
	@go build -o $(BUILD_DIR)/$(BINARY) ./cmd/claude-yolo

# Cross-platform builds
build-darwin-amd64:
	@echo "Building $(BINARY) for macOS (Intel)..."
	@mkdir -p $(BUILD_DIR)
	@GOOS=darwin GOARCH=amd64 go build $(GO_BUILD_FLAGS) -o $(BUILD_DIR)/$(BINARY)-darwin-amd64 ./cmd/claude-yolo
	@echo "✓ Built: $(BUILD_DIR)/$(BINARY)-darwin-amd64"

build-darwin-arm64:
	@echo "Building $(BINARY) for macOS (Apple Silicon)..."
	@mkdir -p $(BUILD_DIR)
	@GOOS=darwin GOARCH=arm64 go build $(GO_BUILD_FLAGS) -o $(BUILD_DIR)/$(BINARY)-darwin-arm64 ./cmd/claude-yolo
	@echo "✓ Built: $(BUILD_DIR)/$(BINARY)-darwin-arm64"

build-linux-amd64:
	@echo "Building $(BINARY) for Linux (amd64)..."
	@mkdir -p $(BUILD_DIR)
	@GOOS=linux GOARCH=amd64 go build $(GO_BUILD_FLAGS) -o $(BUILD_DIR)/$(BINARY)-linux-amd64 ./cmd/claude-yolo
	@echo "✓ Built: $(BUILD_DIR)/$(BINARY)-linux-amd64"

build-linux-arm64:
	@echo "Building $(BINARY) for Linux (ARM64)..."
	@mkdir -p $(BUILD_DIR)
	@GOOS=linux GOARCH=arm64 go build $(GO_BUILD_FLAGS) -o $(BUILD_DIR)/$(BINARY)-linux-arm64 ./cmd/claude-yolo
	@echo "✓ Built: $(BUILD_DIR)/$(BINARY)-linux-arm64"

build-all: build-darwin-amd64 build-darwin-arm64 build-linux-amd64 build-linux-arm64
	@echo "✓ All platform builds complete!"
	@ls -lh $(BUILD_DIR)/$(BINARY)-*

test:
	@echo "Running Go unit tests..."
	@go test -v -race -coverprofile=coverage.out ./...

test-unit-legacy:
	@echo "Running legacy bash unit tests..."
	@./test/run-unit-tests.sh

test-integration:
	@echo "Running integration tests..."
	@./test/run-integration-tests.sh

test-all: test test-unit-legacy test-integration

lint:
	@echo "Running golangci-lint..."
	@golangci-lint run ./...

install:
	@echo "Installing to $$GOPATH/bin..."
	@go install ./cmd/claude-yolo

clean:
	@rm -f $(BUILD_DIR)/$(BINARY)
	@rm -f coverage.out
	@go clean

# Development helpers
fmt:
	@go fmt ./...

vet:
	@go vet ./...

deps:
	@go mod download
	@go mod tidy

# Show test coverage
cover: test
	@go tool cover -html=coverage.out

# Install git hooks
install-hooks:
	@echo "Installing git hooks..."
	@./.git-hooks/install.sh

# Run benchmarks
bench:
	@echo "Running key benchmarks..."
	@./scripts/benchmark.sh

bench-all:
	@echo "Running all benchmarks..."
	@./scripts/benchmark.sh --all
