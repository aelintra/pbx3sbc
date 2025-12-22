#!/bin/bash
#
# Automated testing script for PBX3sbc installation
# Tests installation, configuration, and basic functionality
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Functions
log_info() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    ((TESTS_SKIPPED++))
}

test_command() {
    local name="$1"
    local command="$2"
    
    log_info "Testing: $name"
    if eval "$command" &>/dev/null; then
        log_success "$name"
        return 0
    else
        log_fail "$name"
        return 1
    fi
}

test_file_exists() {
    local file="$1"
    local name="${2:-$file}"
    
    log_info "Checking file: $name"
    if [[ -f "$file" ]]; then
        log_success "File exists: $name"
        return 0
    else
        log_fail "File missing: $name"
        return 1
    fi
}

test_service_running() {
    local service="$1"
    
    log_info "Checking service: $service"
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        log_success "Service running: $service"
        return 0
    else
        log_fail "Service not running: $service"
        return 1
    fi
}

test_service_enabled() {
    local service="$1"
    
    log_info "Checking service enabled: $service"
    if systemctl is-enabled --quiet "$service" 2>/dev/null; then
        log_success "Service enabled: $service"
        return 0
    else
        log_fail "Service not enabled: $service"
        return 1
    fi
}

# Main test suite
main() {
    echo
    echo "=========================================="
    echo "PBX3sbc Installation Test Suite"
    echo "=========================================="
    echo
    
    # Test 1: Check if running as root
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This test script must be run as root (use sudo)${NC}"
        exit 1
    fi
    
    # Test 2: Dependencies
    echo
    echo "=== Dependency Tests ==="
    test_command "Litestream installed" "command -v litestream"
    test_command "Kamailio installed" "command -v kamailio"
    test_command "SQLite3 installed" "command -v sqlite3"
    test_command "systemctl available" "command -v systemctl"
    
    # Test 3: Configuration Files
    echo
    echo "=== Configuration File Tests ==="
    test_file_exists "/etc/litestream.yml" "Litestream config"
    test_file_exists "/etc/kamailio/kamailio.cfg" "Kamailio config"
    test_file_exists "/etc/systemd/system/litestream.service" "Litestream service"
    
    # Test 4: Database
    echo
    echo "=== Database Tests ==="
    test_file_exists "/var/lib/kamailio/routing.db" "Routing database"
    
    if [[ -f "/var/lib/kamailio/routing.db" ]]; then
        test_command "Database integrity check" "sqlite3 /var/lib/kamailio/routing.db 'PRAGMA integrity_check;' | grep -q 'ok'"
        test_command "Database has sip_domains table" "sqlite3 /var/lib/kamailio/routing.db '.tables' | grep -q sip_domains"
        test_command "Database has dispatcher table" "sqlite3 /var/lib/kamailio/routing.db '.tables' | grep -q dispatcher"
        test_command "Database WAL mode enabled" "sqlite3 /var/lib/kamailio/routing.db 'PRAGMA journal_mode;' | grep -q WAL"
    else
        log_skip "Database tests (database not found)"
    fi
    
    # Test 5: Services
    echo
    echo "=== Service Tests ==="
    test_service_running "litestream"
    test_service_enabled "litestream"
    test_service_running "kamailio"
    test_service_enabled "kamailio"
    
    # Test 6: Helper Scripts
    echo
    echo "=== Helper Script Tests ==="
    test_file_exists "./scripts/init-database.sh" "init-database.sh"
    test_file_exists "./scripts/add-domain.sh" "add-domain.sh"
    test_file_exists "./scripts/add-dispatcher.sh" "add-dispatcher.sh"
    test_file_exists "./scripts/restore-database.sh" "restore-database.sh"
    test_file_exists "./scripts/view-status.sh" "view-status.sh"
    
    # Test 7: Script Permissions
    echo
    echo "=== Script Permission Tests ==="
    if [[ -x "./scripts/init-database.sh" ]]; then
        log_success "init-database.sh is executable"
    else
        log_fail "init-database.sh is not executable"
    fi
    
    # Test 8: Litestream Replication
    echo
    echo "=== Litestream Replication Tests ==="
    if systemctl is-active --quiet litestream 2>/dev/null; then
        test_command "Litestream databases command" "litestream databases &>/dev/null"
        
        # Check if replication is configured
        if grep -q "bucket:" /etc/litestream.yml 2>/dev/null; then
            log_success "Litestream replication configured"
        else
            log_skip "Litestream replication not configured (may be using IAM)"
        fi
    else
        log_skip "Litestream replication tests (service not running)"
    fi
    
    # Test 9: Kamailio Configuration
    echo
    echo "=== Kamailio Configuration Tests ==="
    if command -v kamailio &>/dev/null && [[ -f /etc/kamailio/kamailio.cfg ]]; then
        test_command "Kamailio config syntax check" "kamailio -c -f /etc/kamailio/kamailio.cfg"
    else
        log_skip "Kamailio config test (Kamailio not installed or config missing)"
    fi
    
    # Test 10: File Permissions
    echo
    echo "=== File Permission Tests ==="
    if [[ -f /var/lib/kamailio/routing.db ]]; then
        if [[ -r /var/lib/kamailio/routing.db ]]; then
            log_success "Database is readable"
        else
            log_fail "Database is not readable"
        fi
    fi
    
    if [[ -f /etc/litestream.yml ]]; then
        local perms=$(stat -c "%a" /etc/litestream.yml 2>/dev/null || echo "000")
        if [[ "$perms" == "600" ]] || [[ "$perms" == "640" ]]; then
            log_success "Litestream config has secure permissions"
        else
            log_fail "Litestream config permissions too open: $perms"
        fi
    fi
    
    # Test 11: Network/Firewall (if UFW is installed)
    echo
    echo "=== Firewall Tests ==="
    if command -v ufw &>/dev/null; then
        if ufw status | grep -q "Status: active"; then
            log_success "UFW firewall is active"
            if ufw status | grep -q "5060"; then
                log_success "SIP port 5060 is configured"
            else
                log_skip "SIP port 5060 not found in firewall rules"
            fi
        else
            log_skip "UFW firewall is not active"
        fi
    else
        log_skip "UFW not installed"
    fi
    
    # Test 12: Database Operations (if database exists)
    echo
    echo "=== Database Operation Tests ==="
    if [[ -f /var/lib/kamailio/routing.db ]]; then
        # Test adding a test domain (cleanup after)
        if ./scripts/add-domain.sh test-validation.example.com 99 1 "Test validation" &>/dev/null; then
            log_success "add-domain.sh script works"
            # Cleanup
            sqlite3 /var/lib/kamailio/routing.db "DELETE FROM sip_domains WHERE domain='test-validation.example.com';" &>/dev/null || true
        else
            log_fail "add-domain.sh script failed"
        fi
    else
        log_skip "Database operation tests (database not found)"
    fi
    
    # Summary
    echo
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo -e "${GREEN}Passed:${NC} $TESTS_PASSED"
    echo -e "${RED}Failed:${NC} $TESTS_FAILED"
    echo -e "${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
    echo
    
    TOTAL=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
    echo "Total tests: $TOTAL"
    echo
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed. Review the output above.${NC}"
        exit 1
    fi
}

# Run tests
main "$@"
