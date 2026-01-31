#!/usr/bin/env bash
# Don't use 'set -e' - we want to continue testing even if one platform fails

# Developer script to run ukiryu tests across multiple Docker platforms
# Usage: ./docker-test-all.sh [options] [platforms]
#
# Platforms: alpine ubuntu-22 ubuntu-24 debian-bookworm debian-trixie (default: all)
#
# Options:
#   --build, -b        Force rebuild Docker images
#   --verbose, -v      Enable verbose output
#   --fast             Skip build if image exists (default)
#   --register, -r     Custom register path
#   --help, -h         Show this help
#
# Examples:
#   ./docker-test-all.sh                          # Test all platforms
#   ./docker-test-all.sh alpine ubuntu-22        # Test only alpine and ubuntu 22
#   ./docker-test-all.sh --build                  # Rebuild and test all
#   ./docker-test-all.sh -v debian-bookworm       # Verbose test on debian bookworm

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UKIRYU_DIR="$(cd "$SCRIPT_DIR" && pwd)"
REGISTER_DIR="$(cd "$SCRIPT_DIR/../register" && pwd 2>/dev/null || echo "")"

# Fallback to sibling register directory if not found
if [ -z "$REGISTER_DIR" ] || [ ! -d "$REGISTER_DIR" ]; then
    REGISTER_DIR="$(cd "$SCRIPT_DIR/../register" && pwd 2>/dev/null || echo "/Users/mulgogi/src/ukiryu/register")"
fi

# Default platforms to test (all platforms)
PLATFORMS=("alpine" "ubuntu-22" "ubuntu-24" "debian-bookworm" "debian-trixie")
PLATFORMS_SPECIFIED=false

# Platform name mapping (script name -> Dockerfile suffix)
declare -A PLATFORM_DOCKERFILES=(
    ["alpine"]="alpine"
    ["ubuntu-22"]="ubuntu-22.04"
    ["ubuntu-24"]="ubuntu-24.04"
    ["debian-bookworm"]="debian-bookworm"
    ["debian-trixie"]="debian-trixie"
)

# Platform name mapping (script name -> display name)
declare -A PLATFORM_DISPLAY=(
    ["alpine"]="Alpine"
    ["ubuntu-22"]="Ubuntu 22.04"
    ["ubuntu-24"]="Ubuntu 24.04"
    ["debian-bookworm"]="Debian Bookworm"
    ["debian-trixie"]="Debian Trixie"
)

# Parse arguments
BUILD=false
VERBOSE=false
FAST=true
REGISTER_PATH=""
RSPEC_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --build|-b)
      BUILD=true
      FAST=false
      shift
      ;;
    --verbose|-v)
      VERBOSE=true
      shift
      ;;
    --fast)
      FAST=true
      shift
      ;;
    --register|-r)
      REGISTER_PATH="$2"
      shift 2
      ;;
    --help|-h)
      sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# //g' | sed 's/^#//g'
      exit 0
      ;;
    alpine|ubuntu-22|ubuntu-24|debian-bookworm|debian-trixie)
      # If first platform argument, reset to only that platform
      if [ "$PLATFORMS_SPECIFIED" = false ]; then
        PLATFORMS=("$1")
        PLATFORMS_SPECIFIED=true
      else
        PLATFORMS+=("$1")
      fi
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Run --help for usage"
      exit 1
      ;;
  esac
done

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Results tracking
declare -A RESULTS
declare -A TIMES

# Function to print header
print_header() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

# Function to print platform header
print_platform_header() {
    local platform=$1
    local display_name="${PLATFORM_DISPLAY[$platform]}"
    echo ""
    echo -e "${MAGENTA}══════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}Testing Platform: ${BLUE}${display_name}${NC}"
    echo -e "${MAGENTA}══════════════════════════════════════════${NC}"
}

# Function to print success
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to print error
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Function to print warning
print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Function to test a single platform
test_platform() {
    local platform=$1
    local dockerfile_suffix="${PLATFORM_DOCKERFILES[$platform]}"
    local display_name="${PLATFORM_DISPLAY[$platform]}"
    local image_name="ukiryu-test:${dockerfile_suffix}"
    local dockerfile="$UKIRYU_DIR/docker/Dockerfile.${dockerfile_suffix}"
    local container_name="ukiryu-${dockerfile_suffix}-test-runner"

    print_platform_header "$platform"

    # Check if dockerfile exists
    if [ ! -f "$dockerfile" ]; then
        print_error "Dockerfile not found: $dockerfile"
        RESULTS[$platform]="FAILED (Dockerfile not found)"
        return 1
    fi

    # Build image if needed
    if [ "$BUILD" = true ] || [ "$FAST" = false ] || ! docker image inspect "$image_name" &>/dev/null; then
        echo -e "${BLUE}Building Docker image...${NC}"
        if docker build -f "$dockerfile" -t "$image_name" "$UKIRYU_DIR" > /tmp/docker-build-${platform}.log 2>&1; then
            print_success "Build completed"
        else
            print_error "Build failed"
            echo "Check log: /tmp/docker-build-${platform}.log"
            RESULTS[$platform]="FAILED (Build error)"
            return 1
        fi
    else
        print_success "Using existing image (use --build to rebuild)"
    fi

    # Prepare docker run options
    # Note: Using writable mounts so tests can create temporary fixture files
    DOCKER_OPTS=(
        --rm
        -v "$UKIRYU_DIR:/ukiryu"
        -v "$REGISTER_DIR:/register:ro"
        -e UKIRYU_REGISTER="/register"
        --name "$container_name"
    )

    # Override register if specified
    if [ -n "$REGISTER_PATH" ]; then
        DOCKER_OPTS+=(-v "$REGISTER_PATH:/register:ro" -e UKIRYU_REGISTER="/register")
    fi

    # Add verbose flag for RSpec output (not UKIRYU_DEBUG which breaks test output)
    if [ "$VERBOSE" = true ]; then
        RSPEC_ARGS+=(--format documentation)
        echo -e "${YELLOW}Running with verbose RSpec output...${NC}"
    fi

    # Run tests
    echo -e "${BLUE}Running tests...${NC}"
    local start_time=$(date +%s)

    if docker run "${DOCKER_OPTS[@]}" "$image_name" bundle exec rspec "${RSPEC_ARGS[@]}" > /tmp/docker-test-${platform}.log 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        RESULTS[$platform]="PASSED"
        TIMES[$platform]="${duration}s"
        print_success "All tests passed (${duration}s)"
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        RESULTS[$platform]="FAILED"
        TIMES[$platform]="${duration}s"
        print_error "Tests failed (${duration}s)"
        echo -e "\n${YELLOW}Full RSpec output:${NC}"
        cat /tmp/docker-test-${platform}.log
    fi

    # Cleanup
    docker rm -f "$container_name" &>/dev/null || true
}

# Function to check if Docker is available and running
check_docker() {
    if ! command -v docker &>/dev/null; then
        print_error "Docker not found. Please install Docker Desktop:"
        echo "  https://www.docker.com/products/docker-desktop/"
        exit 1
    fi

    if ! docker info &>/dev/null; then
        print_error "Docker daemon is not running. Please start Docker Desktop:"
        echo "  - macOS: Open Docker Desktop from Applications"
        echo "  - Linux: sudo systemctl start docker"
        echo "  - Windows: Start Docker Desktop from Start Menu"
        exit 1
    fi
}

# Main execution
main() {
    # Check Docker availability first
    check_docker

    print_header "Ukiryu Multi-Platform Docker Test Runner"

    local display_platforms=()
    for p in "${PLATFORMS[@]}"; do
        display_platforms+=("${PLATFORM_DISPLAY[$p]}")
    done
    echo -e "Testing platforms: ${BLUE}${display_platforms[*]}${NC}"
    echo "Build mode: $([ "$BUILD" = true ] && echo "Force rebuild" || echo "Fast (use existing)")"
    echo ""

    local start_time=$(date +%s)

    # Test each platform
    for platform in "${PLATFORMS[@]}"; do
        test_platform "$platform"
    done

    local total_time=$(date +%s)
    local total_duration=$((total_time - start_time))

    # Print summary
    echo ""
    print_header "Test Summary"

    local passed=0
    local failed=0

    for platform in "${PLATFORMS[@]}"; do
        local result="${RESULTS[$platform]:-SKIPPED}"
        local time="${TIMES[$platform]:-N/A}"
        local display_name="${PLATFORM_DISPLAY[$platform]}"

        if [ "$result" = "PASSED" ]; then
            echo -e "${GREEN}✓${NC} ${display_name}: ${GREEN}${result}${NC} (${time})"
            ((passed++))
        else
            echo -e "${RED}✗${NC} ${display_name}: ${RED}${result}${NC} (${time})"
            ((failed++))
        fi
    done

    echo ""
    echo -e "Total time: ${BLUE}${total_duration}s${NC}"
    echo -e "Results: ${GREEN}${passed} passed${NC}, ${RED}${failed} failed${NC}"

    if [ $failed -gt 0 ]; then
        echo ""
        print_error "Some platforms failed tests"
        echo "Check logs in /tmp/docker-test-*.log"
        exit 1
    else
        echo ""
        print_success "All platforms passed!"
        exit 0
    fi
}

# Run main
main "$@"
