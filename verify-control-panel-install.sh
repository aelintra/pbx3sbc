#!/bin/bash
#
# OpenSIPS Control Panel Installation Verification Script
# Verifies that the control panel installation is complete and correct
#
# Usage: sudo ./verify-control-panel-install.sh [--db-password <PASSWORD>]
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
OCP_WEB_ROOT="/var/www/opensips-cp"
OCP_CONFIG_DIR="${OCP_WEB_ROOT}/config"
OCP_WEB_DIR="${OCP_WEB_ROOT}/web"
DB_NAME="${DB_NAME:-opensips}"
DB_USER="${DB_USER:-opensips}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"
DB_PASSWORD=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHED_DIR="${SCRIPT_DIR}/control-panel-patched"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --db-password)
            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}Error: --db-password requires a password${NC}"
                exit 1
            fi
            DB_PASSWORD="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Get database password if not provided
if [[ -z "$DB_PASSWORD" ]]; then
    echo
    read -sp "Enter MySQL database password for user '${DB_USER}': " DB_PASSWORD
    echo
    if [[ -z "$DB_PASSWORD" ]]; then
        log_error "Database password cannot be empty"
        exit 1
    fi
fi

# Verification counters
PASSED=0
FAILED=0
WARNINGS=0

verify_file() {
    local file="$1"
    local desc="$2"
    
    if [[ -f "$file" ]]; then
        log_success "$desc exists: $file"
        ((PASSED++))
        return 0
    else
        log_error "$desc missing: $file"
        ((FAILED++))
        return 1
    fi
}

verify_directory() {
    local dir="$1"
    local desc="$2"
    
    if [[ -d "$dir" ]]; then
        log_success "$desc exists: $dir"
        ((PASSED++))
        return 0
    else
        log_error "$desc missing: $dir"
        ((FAILED++))
        return 1
    fi
}

verify_permissions() {
    local file="$1"
    local expected_owner="$2"
    local desc="$3"
    
    if [[ -f "$file" ]] || [[ -d "$file" ]]; then
        local owner=$(stat -c '%U:%G' "$file" 2>/dev/null || echo "unknown")
        if [[ "$owner" == "$expected_owner" ]]; then
            log_success "$desc permissions correct ($owner): $file"
            ((PASSED++))
            return 0
        else
            log_warn "$desc permissions incorrect (expected $expected_owner, got $owner): $file"
            ((WARNINGS++))
            return 1
        fi
    else
        log_error "$desc not found: $file"
        ((FAILED++))
        return 1
    fi
}

verify_database_table() {
    local table="$1"
    local desc="$2"
    
    if mysql -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" -P "$DB_PORT" "$DB_NAME" -e "DESCRIBE $table;" &>/dev/null; then
        log_success "$desc table exists: $table"
        ((PASSED++))
        return 0
    else
        log_error "$desc table missing: $table"
        ((FAILED++))
        return 1
    fi
}

verify_patched_file() {
    local file="$1"
    local check_pattern="$2"
    local desc="$3"
    
    if [[ -f "$file" ]]; then
        if grep -q "$check_pattern" "$file" 2>/dev/null; then
            log_success "$desc patched correctly: $file"
            ((PASSED++))
            return 0
        else
            log_error "$desc not patched (missing: $check_pattern): $file"
            ((FAILED++))
            return 1
        fi
    else
        log_error "$desc file missing: $file"
        ((FAILED++))
        return 1
    fi
}

# Main verification
main() {
    echo
    echo "=========================================="
    echo "OpenSIPS Control Panel Installation Verification"
    echo "=========================================="
    echo
    
    check_root
    
    log_info "Starting verification checks..."
    echo
    
    # 1. Check directory structure
    echo "=== Directory Structure ==="
    verify_directory "$OCP_WEB_ROOT" "Control panel root directory"
    verify_directory "$OCP_CONFIG_DIR" "Config directory"
    verify_directory "$OCP_WEB_DIR" "Web directory"
    verify_directory "${OCP_WEB_DIR}/tools/system/domains" "Domain tool directory"
    verify_directory "${OCP_WEB_DIR}/tools/system/domains/template" "Domain tool template directory"
    verify_directory "${OCP_CONFIG_DIR}/tools" "Config tools directory"
    echo
    
    # 2. Check required config files
    echo "=== Required Config Files ==="
    verify_file "${OCP_CONFIG_DIR}/db.inc.php" "Database config"
    verify_file "${OCP_CONFIG_DIR}/local.inc.php" "Local config"
    verify_file "${OCP_CONFIG_DIR}/globals.php" "Globals config"
    verify_file "${OCP_CONFIG_DIR}/modules.inc.php" "Modules config"
    verify_file "${OCP_CONFIG_DIR}/session.inc.php" "Session config"
    verify_file "${OCP_CONFIG_DIR}/boxes.load.php" "Boxes load config"
    verify_file "${OCP_CONFIG_DIR}/db_schema.mysql" "Database schema file"
    echo
    
    # 3. Check web files
    echo "=== Web Files ==="
    verify_file "${OCP_WEB_DIR}/index.php" "Main index file"
    verify_file "${OCP_WEB_DIR}/login.php" "Login page"
    verify_file "${OCP_WEB_DIR}/tools/system/domains/domains.php" "Domain tool handler"
    verify_file "${OCP_WEB_DIR}/tools/system/domains/template/domains.main.php" "Domain tool main template"
    verify_file "${OCP_WEB_DIR}/tools/system/domains/template/domains.form.php" "Domain tool form template"
    echo
    
    # 4. Check permissions
    echo "=== File Permissions ==="
    verify_permissions "$OCP_WEB_ROOT" "www-data:www-data" "Web root"
    verify_permissions "$OCP_CONFIG_DIR" "www-data:www-data" "Config directory"
    verify_permissions "$OCP_WEB_DIR" "www-data:www-data" "Web directory"
    verify_permissions "${OCP_CONFIG_DIR}/db.inc.php" "www-data:www-data" "Database config file"
    verify_permissions "${OCP_WEB_DIR}/index.php" "www-data:www-data" "Index file"
    echo
    
    # 5. Check database connection
    echo "=== Database Connection ==="
    if mysql -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" -P "$DB_PORT" -e "USE ${DB_NAME};" 2>/dev/null; then
        log_success "Database connection successful"
        ((PASSED++))
    else
        log_error "Cannot connect to database"
        ((FAILED++))
        echo
        exit 1
    fi
    echo
    
    # 6. Check database tables (control panel)
    echo "=== Control Panel Database Tables ==="
    verify_database_table "ocp_boxes_config" "Boxes config"
    verify_database_table "ocp_tools_config" "Tools config"
    verify_database_table "ocp_admin_privileges" "Admin privileges"
    verify_database_table "domain" "Domain"
    echo
    
    # 7. Check admin user exists
    echo "=== Admin User ==="
    ADMIN_COUNT=$(mysql -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" -P "$DB_PORT" "$DB_NAME" -sN -e "SELECT COUNT(*) FROM ocp_admin_privileges;" 2>/dev/null || echo "0")
    if [[ "$ADMIN_COUNT" -gt 0 ]]; then
        log_success "Admin user exists ($ADMIN_COUNT user(s))"
        ((PASSED++))
    else
        log_warn "No admin users found in database"
        ((WARNINGS++))
    fi
    echo
    
    # 8. Check patched files
    echo "=== Patched Files Verification ==="
    verify_patched_file "${OCP_WEB_DIR}/tools/system/domains/domains.php" "setid.*INSERT INTO" "Domain tool INSERT query with setid"
    verify_patched_file "${OCP_WEB_DIR}/tools/system/domains/domains.php" "setid.*UPDATE.*SET" "Domain tool UPDATE query with setid"
    verify_patched_file "${OCP_WEB_DIR}/tools/system/domains/template/domains.main.php" "Set ID" "Domain tool table with Set ID column"
    verify_patched_file "${OCP_WEB_DIR}/tools/system/domains/template/domains.main.php" "form_init_status" "Domain tool JavaScript initialization"
    verify_patched_file "${OCP_WEB_DIR}/tools/system/domains/template/domains.form.php" "Set ID" "Domain tool form with Set ID field"
    echo
    
    # 9. Check Apache
    echo "=== Apache Configuration ==="
    if systemctl is-active --quiet apache2; then
        log_success "Apache is running"
        ((PASSED++))
    else
        log_error "Apache is not running"
        ((FAILED++))
    fi
    
    if [[ -f /etc/apache2/sites-available/opensips-cp.conf ]]; then
        log_success "Apache virtual host config exists"
        ((PASSED++))
    else
        log_error "Apache virtual host config missing"
        ((FAILED++))
    fi
    
    if apache2ctl configtest &>/dev/null; then
        log_success "Apache configuration is valid"
        ((PASSED++))
    else
        log_error "Apache configuration test failed"
        ((FAILED++))
    fi
    echo
    
    # 10. Check HTTP accessibility
    echo "=== HTTP Accessibility ==="
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" ]] || [[ "$HTTP_CODE" == "302" ]]; then
        log_success "Control panel is accessible (HTTP $HTTP_CODE)"
        ((PASSED++))
    elif [[ "$HTTP_CODE" == "403" ]]; then
        log_warn "Control panel returns 403 Forbidden (permissions issue?)"
        ((WARNINGS++))
    elif [[ "$HTTP_CODE" == "500" ]]; then
        log_warn "Control panel returns 500 Error (check error logs)"
        ((WARNINGS++))
    else
        log_error "Control panel not accessible (HTTP $HTTP_CODE)"
        ((FAILED++))
    fi
    echo
    
    # Summary
    echo "=========================================="
    echo "Verification Summary"
    echo "=========================================="
    echo
    echo -e "${GREEN}Passed:${NC} $PASSED"
    echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
    echo -e "${RED}Failed:${NC} $FAILED"
    echo
    
    if [[ $FAILED -eq 0 ]]; then
        if [[ $WARNINGS -eq 0 ]]; then
            echo -e "${GREEN}✓ All checks passed! Control panel installation is complete.${NC}"
            echo
            exit 0
        else
            echo -e "${YELLOW}! Installation complete but has warnings. Review warnings above.${NC}"
            echo
            exit 0
        fi
    else
        echo -e "${RED}✗ Installation verification failed. Please review errors above.${NC}"
        echo
        exit 1
    fi
}

# Run main function
main "$@"

