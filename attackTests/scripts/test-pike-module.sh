#!/bin/bash
#
# Pike Module Test Script
# Tests OpenSIPS Pike module flood detection capabilities
#
# Usage:
#   ./test-pike-module.sh <sbc-ip> [sbc-port]
#
# Example:
#   ./test-pike-module.sh 192.168.1.10 5060
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SBC_IP="${1:-}"
SBC_PORT="${2:-5060}"
TEST_USER="40004"
TEST_DOMAIN="ael.vcloudpbx.com"
REQUESTS_PER_BURST=20
BURST_DELAY=100  # milliseconds between requests
THRESHOLD=16      # Pike threshold (requests per 2 seconds)
BLOCK_DURATION=8  # seconds

# Check if SBC IP provided
if [[ -z "$SBC_IP" ]]; then
    echo -e "${RED}Error: SBC IP address required${NC}"
    echo "Usage: $0 <sbc-ip> [sbc-port]"
    echo "Example: $0 192.168.1.10 5060"
    exit 1
fi

# Check if SIPp is installed
if ! command -v sipp &> /dev/null; then
    echo -e "${RED}Error: SIPp not found${NC}"
    echo "Please install SIPp: sudo apt-get install sipp"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Pike Module Test Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "SBC Target: $SBC_IP:$SBC_PORT"
echo "Test User: $TEST_USER@$TEST_DOMAIN"
echo "Pike Threshold: $THRESHOLD requests per 2 seconds"
echo "Block Duration: $BLOCK_DURATION seconds"
echo ""

# Function to send SIP OPTIONS request
send_options() {
    local count=$1
    local delay=$2
    echo -e "${YELLOW}Sending $count OPTIONS requests with $delay ms delay...${NC}"
    
    sipp -sn uac \
        -s "$TEST_USER" \
        -m "$count" \
        -r "$count" \
        -d "$delay" \
        -trace_msg \
        "$SBC_IP:$SBC_PORT" \
        > /tmp/sipp-test.log 2>&1 || true
    
    echo -e "${GREEN}Requests sent${NC}"
}

# Function to check if IP is blocked (no response to request)
test_blocked_ip() {
    echo -e "${YELLOW}Testing if IP is blocked (should get no response)...${NC}"
    
    # Send single OPTIONS request
    timeout 5 sipp -sn uac \
        -s "$TEST_USER" \
        -m 1 \
        -r 1 \
        -d 1000 \
        "$SBC_IP:$SBC_PORT" \
        > /tmp/sipp-blocked-test.log 2>&1 || true
    
    # Check if we got a response
    if grep -q "200 OK" /tmp/sipp-blocked-test.log; then
        echo -e "${RED}WARNING: Got response - IP may not be blocked${NC}"
        return 1
    else
        echo -e "${GREEN}No response received - IP appears to be blocked${NC}"
        return 0
    fi
}

# Function to wait for unblock
wait_for_unblock() {
    local wait_time=$1
    echo -e "${YELLOW}Waiting $wait_time seconds for IP to be unblocked...${NC}"
    
    for i in $(seq 1 $wait_time); do
        echo -n "."
        sleep 1
    done
    echo ""
}

# Function to test normal traffic
test_normal_traffic() {
    echo -e "${BLUE}Test 1: Normal Traffic (should work)${NC}"
    echo "Sending 5 OPTIONS requests with 500ms delay..."
    
    send_options 5 500
    
    if grep -q "200 OK" /tmp/sipp-test.log; then
        echo -e "${GREEN}✓ Normal traffic works${NC}"
    else
        echo -e "${YELLOW}⚠ No 200 OK responses (may be normal if domain not configured)${NC}"
    fi
    echo ""
}

# Function to test flood detection
test_flood_detection() {
    echo -e "${BLUE}Test 2: Flood Detection (should trigger Pike)${NC}"
    echo "Sending $REQUESTS_PER_BURST requests rapidly to exceed threshold..."
    echo ""
    echo -e "${YELLOW}NOTE: Check OpenSIPS logs for: 'PIKE: IP ... blocked due to flood detection'${NC}"
    echo ""
    
    # Send rapid requests
    send_options $REQUESTS_PER_BURST $BURST_DELAY
    
    echo ""
    echo -e "${YELLOW}Check OpenSIPS logs now:${NC}"
    echo "  journalctl -u opensips -f | grep -i pike"
    echo ""
    read -p "Press Enter after checking logs..."
    echo ""
}

# Function to test blocking behavior
test_blocking() {
    echo -e "${BLUE}Test 3: Blocking Behavior${NC}"
    echo "Sending request from potentially blocked IP..."
    
    test_blocked_ip
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ IP appears to be blocked (no response)${NC}"
    else
        echo -e "${YELLOW}⚠ IP may not be blocked (got response)${NC}"
    fi
    echo ""
}

# Function to test unblocking
test_unblocking() {
    echo -e "${BLUE}Test 4: Unblocking After Timeout${NC}"
    
    wait_for_unblock $BLOCK_DURATION
    
    echo "Testing if IP is unblocked..."
    send_options 3 500
    
    if grep -q "200 OK\|407\|401" /tmp/sipp-test.log; then
        echo -e "${GREEN}✓ IP appears to be unblocked (got response)${NC}"
    else
        echo -e "${YELLOW}⚠ Still no response (may need more time or different test)${NC}"
    fi
    echo ""
}

# Function to show log monitoring instructions
show_log_instructions() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Log Monitoring Instructions${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "On the OpenSIPS server, run:"
    echo ""
    echo "  journalctl -u opensips -f | grep -i pike"
    echo ""
    echo "Or watch all logs:"
    echo ""
    echo "  journalctl -u opensips -f"
    echo ""
    echo "Look for:"
    echo "  - 'PIKE: IP <ip> blocked due to flood detection'"
    echo "  - Request patterns showing blocking"
    echo ""
}

# Main test sequence
main() {
    echo -e "${BLUE}Starting Pike Module Tests...${NC}"
    echo ""
    
    show_log_instructions
    read -p "Press Enter when ready to start tests..."
    echo ""
    
    # Test 1: Normal traffic
    test_normal_traffic
    sleep 2
    
    # Test 2: Flood detection
    test_flood_detection
    sleep 2
    
    # Test 3: Blocking behavior
    test_blocking
    sleep 2
    
    # Test 4: Unblocking
    test_unblocking
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Test Complete${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "Review the results above and check OpenSIPS logs for Pike events."
    echo ""
    echo "Test logs saved in:"
    echo "  /tmp/sipp-test.log"
    echo "  /tmp/sipp-blocked-test.log"
    echo ""
}

# Run main function
main
