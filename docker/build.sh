#!/bin/bash
# Build Docker images for testing ukiryu on different platforms

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "========================================"
echo "Building Docker images for ukiryu testing"
echo "========================================"

# Build Alpine image
echo ""
echo "Building Alpine image..."
docker build -f docker/Dockerfile.alpine -t ukiryu-test:alpine .

# Build Ubuntu image
echo ""
echo "Building Ubuntu image..."
docker build -f docker/Dockerfile.ubuntu -t ukiryu-test:ubuntu .

# Build Debian image
echo ""
echo "Building Debian image..."
docker build -f docker/Dockerfile.debian -t ukiryu-test:debian .

echo ""
echo "========================================"
echo "All images built successfully!"
echo "========================================"
echo ""
echo "To run tests:"
echo "  Alpine:  docker run --rm ukiryu-test:alpine"
echo "  Ubuntu:  docker run --rm ukiryu-test:ubuntu"
echo "  Debian:  docker run --rm ukiryu-test:debian"
echo ""
echo "Or run all: ./docker/test_all.sh"
