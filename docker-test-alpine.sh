#!/usr/bin/env bash
# Wrapper script for backward compatibility
# Usage: ./docker-test-alpine.sh [options]
# This script now uses docker-test-all.sh under the hood

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/docker-test-all.sh" alpine "$@"
