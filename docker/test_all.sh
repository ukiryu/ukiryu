#!/bin/bash
# Test ukiryu on all platform Docker images

set -e

echo "========================================"
echo "Testing ukiryu on all platforms"
echo "========================================"

# Test Alpine
echo ""
echo "========================================"
echo "Testing Alpine..."
echo "========================================"
docker run --rm ukiryu-test:alpine

echo ""
echo "========================================"
echo "Alpine tests passed!"
echo "========================================"

# Test Ubuntu
echo ""
echo "========================================"
echo "Testing Ubuntu..."
echo "========================================"
docker run --rm ukiryu-test:ubuntu

echo ""
echo "========================================"
echo "Ubuntu tests passed!"
echo "========================================"

# Test Debian
echo ""
echo "========================================"
echo "Testing Debian..."
echo "========================================"
docker run --rm ukiryu-test:debian

echo ""
echo "========================================"
echo "Debian tests passed!"
echo "========================================"

echo ""
echo "========================================"
echo "All platform tests passed!"
echo "========================================"
