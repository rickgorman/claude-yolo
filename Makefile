.PHONY: build test lint install clean test-unit test-integration test-all

# Go binary name
BINARY=claude-yolo
BUILD_DIR=bin

# Go build flags
GO_BUILD_FLAGS=-ldflags="-s -w"

build:
	@echo "Building $(BINARY)..."
	@mkdir -p $(BUILD_DIR)
	@go build $(GO_BUILD_FLAGS) -o $(BUILD_DIR)/$(BINARY) ./cmd/claude-yolo

build-dev:
	@echo "Building $(BINARY) (dev mode)..."
	@mkdir -p $(BUILD_DIR)
	@go build -o $(BUILD_DIR)/$(BINARY) ./cmd/claude-yolo

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
