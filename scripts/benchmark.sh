#!/bin/bash
# Run Go benchmarks for claude-yolo
# Usage: ./scripts/benchmark.sh [package]

set -e

echo "Running Go Benchmarks for claude-yolo"
echo "======================================"
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default benchmark flags
BENCH_FLAGS="-benchmem -benchtime=1s"

if [ "$1" = "--all" ]; then
    echo -e "${BLUE}Running all benchmarks...${NC}"
    go test -bench=. $BENCH_FLAGS ./...
elif [ "$1" = "--compare" ]; then
    echo -e "${BLUE}Running benchmarks with comparison baseline...${NC}"

    # Run benchmarks and save to file
    echo "Creating baseline..."
    go test -bench=. $BENCH_FLAGS ./... > /tmp/bench-baseline.txt

    echo ""
    echo "Make your changes, then run:"
    echo "  go test -bench=. $BENCH_FLAGS ./... > /tmp/bench-new.txt"
    echo "  benchcmp /tmp/bench-baseline.txt /tmp/bench-new.txt"
    echo ""
    echo "Install benchcmp: go install golang.org/x/tools/cmd/benchcmp@latest"

elif [ "$1" = "--cpu" ]; then
    echo -e "${BLUE}Running CPU profiling benchmarks...${NC}"
    go test -bench=. -cpuprofile=cpu.prof ./pkg/hash
    echo ""
    echo "View profile: go tool pprof cpu.prof"

elif [ "$1" = "--mem" ]; then
    echo -e "${BLUE}Running memory profiling benchmarks...${NC}"
    go test -bench=. -memprofile=mem.prof ./pkg/hash
    echo ""
    echo "View profile: go tool pprof mem.prof"

elif [ -n "$1" ]; then
    echo -e "${BLUE}Running benchmarks for $1...${NC}"
    go test -bench=. $BENCH_FLAGS "$1"
else
    echo -e "${BLUE}Running key benchmarks...${NC}"
    echo ""

    echo -e "${GREEN}Hash Package:${NC}"
    go test -bench=. $BENCH_FLAGS ./pkg/hash
    echo ""

    echo -e "${GREEN}Strategy Detection:${NC}"
    go test -bench=. $BENCH_FLAGS ./internal/strategy
    echo ""

    echo -e "${GREEN}Config Loading:${NC}"
    go test -bench=. $BENCH_FLAGS ./internal/yoloconfig
    echo ""

    echo -e "${GREEN}Port Management:${NC}"
    go test -bench=. $BENCH_FLAGS ./internal/container
    echo ""
fi

echo ""
echo -e "${GREEN}✓ Benchmarks complete${NC}"
echo ""
echo "Usage:"
echo "  ./scripts/benchmark.sh              # Run key benchmarks"
echo "  ./scripts/benchmark.sh --all        # Run all benchmarks"
echo "  ./scripts/benchmark.sh --compare    # Create comparison baseline"
echo "  ./scripts/benchmark.sh --cpu        # CPU profiling"
echo "  ./scripts/benchmark.sh --mem        # Memory profiling"
echo "  ./scripts/benchmark.sh ./pkg/hash   # Run specific package"
