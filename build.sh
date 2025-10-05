#!/bin/bash
# Build script for ScopeFinder 2.0 Docker image

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="scopefinder"
DOCKERFILE="Dockerfile"

echo -e "${GREEN}=== ScopeFinder 2.0 Docker Build ===${NC}"
echo ""

# Check if docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    exit 1
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --help, -h      Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0              # Build for local architecture"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Detect the host architecture
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    DOCKER_ARCH="amd64"
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    DOCKER_ARCH="arm64"
else
    # Fallback to dpkg if available
    if command -v dpkg &> /dev/null; then
        DOCKER_ARCH=$(dpkg --print-architecture)
    else
        echo -e "${YELLOW}Warning: Could not detect architecture, defaulting to amd64${NC}"
        DOCKER_ARCH="amd64"
    fi
fi

echo -e "${YELLOW}Building for local architecture...${NC}"
echo "Host architecture: $ARCH"
echo "Docker architecture: $DOCKER_ARCH"
echo ""

# Always disable Docker BuildKit
export DOCKER_BUILDKIT=0

# Build command with architecture argument
BUILD_CMD="docker build --build-arg TARGETARCH=${DOCKER_ARCH} -t ${IMAGE_NAME} -f ${DOCKERFILE} ."

echo "Running: $BUILD_CMD"
echo ""

# Run the build
if $BUILD_CMD; then
    echo ""
    echo -e "${GREEN}=== Build completed successfully ===${NC}"
    echo ""
    echo "Docker image created: ${IMAGE_NAME}"
    echo ""
    echo -e "${YELLOW}=== Setup Instructions ===${NC}"
    echo ""
    echo "1. Add these environment variables to your shell configuration (~/.bashrc or ~/.zshrc):"
    echo ""
    echo "# SCOPEFINDER Configuration"
    echo 'export URLSCAN_API_KEY="your_urlscan_api_key_here"'
    echo 'export VIRUSTOTAL_API_KEY="your_virustotal_api_key_here"'
    echo 'export SHODAN_API_KEY="your_shodan_api_key_here"'
    echo 'export DEHASHED_API_KEY="your_dehashed_api_key_here"'
    echo 'export DEHASHED_EMAIL="your_dehashed_email_here"'
    echo 'export HUNTERIO_API_KEY="your_hunterio_api_key_here"'
    echo 'export PDCP_API_KEY="your_pdcp_api_key_here"'
    echo 'export WPSCAN_API_KEY="your_wpscan_api_key_here"'
    echo 'export SCOPEFINDER_PATH="'$(pwd)'"'
    echo ""
    echo "2. Add these convenience functions to your shell configuration:"
    echo ""
    echo '# Run bash shell inside ScopeFinder container'
    echo 'sf-run() {'
    echo '  docker run --rm -it \'
    echo '    --entrypoint "/bin/bash" \'
    echo '    -e SHODAN_API_KEY="${SHODAN_API_KEY}" \'
    echo '    -e DEHASHED_API_KEY="${DEHASHED_API_KEY}" \'
    echo '    -e DEHASHED_EMAIL="${DEHASHED_EMAIL}" \'
    echo '    -e HUNTERIO_API_KEY="${HUNTERIO_API_KEY}" \'
    echo '    -e WPSCAN_API_KEY="${WPSCAN_API_KEY}" \'
    echo '    -e URLSCAN_API_KEY="${URLSCAN_API_KEY}" \'
    echo '    -e VIRUSTOTAL_API_KEY="${VIRUSTOTAL_API_KEY}" \'
    echo '    -e PDCP_API_KEY="${PDCP_API_KEY}" \'
    echo '    -v "${SCOPEFINDER_PATH}/.config:/root/.config" \'
    echo '    -v "$(pwd):/output" \'
    echo '    -w /output \'
    echo '    scopefinder -c "$*"'
    echo '}'
    echo ""
    echo '# Run ScopeFinder'
    echo 'ScopeFinder() {'
    echo '  # Check if scripts exist'
    echo '  if [[ ! -f "${SCOPEFINDER_PATH}/ScopeFinder.sh" ]]; then'
    echo '    echo "Error: ScopeFinder.sh not found at ${SCOPEFINDER_PATH}/ScopeFinder.sh"'
    echo '    echo "Please set SCOPEFINDER_PATH to the correct directory"'
    echo '    return 1'
    echo '  fi'
    echo ''
    echo '  docker run --rm -it \'
    echo '    --entrypoint "/bin/bash" \'
    echo '    -e SHODAN_API_KEY="${SHODAN_API_KEY}" \'
    echo '    -e DEHASHED_API_KEY="${DEHASHED_API_KEY}" \'
    echo '    -e DEHASHED_EMAIL="${DEHASHED_EMAIL}" \'
    echo '    -e HUNTERIO_API_KEY="${HUNTERIO_API_KEY}" \'
    echo '    -e WPSCAN_API_KEY="${WPSCAN_API_KEY}" \'
    echo '    -e URLSCAN_API_KEY="${URLSCAN_API_KEY}" \'
    echo '    -e VIRUSTOTAL_API_KEY="${VIRUSTOTAL_API_KEY}" \'
    echo '    -e PDCP_API_KEY="${PDCP_API_KEY}" \'
    echo '    -v "${SCOPEFINDER_PATH}/ScopeFinder.sh:/opt/ScopeFinder.sh" \'
    echo '    -v "${SCOPEFINDER_PATH}/lib:/opt/lib" \'
    echo '    -v "${SCOPEFINDER_PATH}/modules:/opt/modules" \'
    echo '    -v "${SCOPEFINDER_PATH}/.config:/root/.config" \'
    echo '    -v "$(pwd):/output" \'
    echo '    -w /output \'
    echo '    scopefinder \'
    echo '    -c "chmod +x /opt/ScopeFinder.sh && /opt/ScopeFinder.sh $*"'
    echo '}'
    echo ""
    echo "3. Reload your shell configuration:"
    echo "   source ~/.bashrc  # or source ~/.zshrc"
    echo ""
    echo -e "${GREEN}=== Usage Examples ===${NC}"
    echo ""
    echo "# Run a full scan:"
    echo "ScopeFinder example.com"
    echo ""
    echo "# Check module status:"
    echo "ScopeFinder example.com --status"
    echo ""
    echo "# Access container shell:"
    echo "sf-run bash"
    echo ""
    echo "# Run with proxy:"
    echo "ScopeFinder example.com --proxy http://172.17.0.1:8080"
    echo ""
else
    echo ""
    echo -e "${RED}=== Build failed ===${NC}"
    exit 1
fi