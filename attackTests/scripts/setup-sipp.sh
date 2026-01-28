#!/bin/bash
#
# SIPp Installation Script
# Installs SIPp for OpenSIPS testing
#
# Usage:
#   ./setup-sipp.sh [install-method]
#
# Options:
#   package  - Install from package (default, fastest)
#   source   - Install from source (latest version)
#   docker   - Create Docker container
#

set -euo pipefail

INSTALL_METHOD="${1:-package}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}SIPp Installation Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if running as root (needed for some operations)
if [[ $EUID -eq 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
    echo -e "${YELLOW}Note: Some operations may require sudo${NC}"
    echo ""
fi

case "$INSTALL_METHOD" in
    package)
        echo -e "${BLUE}Installing SIPp from package...${NC}"
        
        $SUDO apt-get update
        $SUDO apt-get install -y sipp
        
        echo ""
        echo -e "${GREEN}✓ SIPp installed successfully${NC}"
        ;;
        
    source)
        echo -e "${BLUE}Installing SIPp from source...${NC}"
        
        # Install dependencies
        echo "Installing build dependencies..."
        $SUDO apt-get update
        $SUDO apt-get install -y \
            build-essential \
            libncurses5-dev \
            libssl-dev \
            libpcap-dev \
            libsctp-dev \
            wget \
            tar
        
        # Download SIPp
        echo "Downloading SIPp source..."
        cd /tmp
        SIPP_VERSION="3.7.1"
        wget -q "https://github.com/SIPp/sipp/releases/download/v${SIPP_VERSION}/sipp-${SIPP_VERSION}.tar.gz"
        tar -xzf "sipp-${SIPP_VERSION}.tar.gz"
        cd "sipp-${SIPP_VERSION}"
        
        # Build
        echo "Building SIPp..."
        ./configure --with-pcap --with-sctp
        make
        $SUDO make install
        
        echo ""
        echo -e "${GREEN}✓ SIPp built and installed successfully${NC}"
        ;;
        
    docker)
        echo -e "${BLUE}Creating SIPp Docker container...${NC}"
        
        # Check if Docker is installed
        if ! command -v docker &> /dev/null; then
            echo -e "${YELLOW}Docker not found. Installing Docker...${NC}"
            $SUDO apt-get update
            $SUDO apt-get install -y docker.io
            $SUDO systemctl start docker
            $SUDO systemctl enable docker
        fi
        
        # Create Dockerfile
        cat > /tmp/Dockerfile.sipp << 'EOF'
FROM ubuntu:22.04

RUN apt-get update && \
    apt-get install -y sipp && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
CMD ["/bin/bash"]
EOF
        
        # Build image
        echo "Building Docker image..."
        docker build -f /tmp/Dockerfile.sipp -t sipp-test .
        
        echo ""
        echo -e "${GREEN}✓ SIPp Docker image created${NC}"
        echo ""
        echo "To use:"
        echo "  docker run -it --rm --network host sipp-test"
        ;;
        
    *)
        echo "Error: Unknown install method: $INSTALL_METHOD"
        echo "Usage: $0 [package|source|docker]"
        exit 1
        ;;
esac

# Verify installation
echo ""
echo -e "${BLUE}Verifying installation...${NC}"

if [[ "$INSTALL_METHOD" == "docker" ]]; then
    echo "SIPp is available in Docker container: sipp-test"
    echo "Run: docker run -it --rm --network host sipp-test sipp -v"
else
    if command -v sipp &> /dev/null; then
        echo -e "${GREEN}✓ SIPp found${NC}"
        sipp -v
    else
        echo -e "${YELLOW}⚠ SIPp not found in PATH${NC}"
        echo "You may need to log out and back in, or run: source ~/.bashrc"
    fi
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Installation Complete${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Quick test:"
echo "  sipp -sn uac -s 40004 -m 1 <sbc-ip>:5060"
echo ""
echo "Run Pike test script:"
echo "  cd attackTests"
echo "  ./scripts/test-pike-module.sh <sbc-ip> 5060"
echo ""
