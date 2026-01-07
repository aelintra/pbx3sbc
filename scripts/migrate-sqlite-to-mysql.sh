#!/bin/bash
#
# Migrate OpenSIPS from SQLite to MySQL
# This script handles the complete migration process
#
# Usage: sudo ./scripts/migrate-sqlite-to-mysql.sh [--mysql-password PASSWORD] [--skip-install]
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
OPENSIPS_USER="opensips"
OPENSIPS_GROUP="opensips"
OPENSIPS_DIR="/etc/opensips"
SQLITE_DB="${OPENSIPS_DIR}/opensips.db"
MYSQL_DB="opensips"
MYSQL_USER="opensips"
MYSQL_PASSWORD=""
SKIP_INSTALL=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --mysql-password)
            MYSQL_PASSWORD="$2"
            shift 2
            ;;
        --skip-install)
            SKIP_INSTALL=true
            shift
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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Step 1: Install MySQL and schema package
install_mysql() {
    if [[ "$SKIP_INSTALL" == true ]]; then
        log_info "Skipping MySQL installation"
        return
    fi
    
    log_info "Installing MySQL server and OpenSIPS MySQL schema..."
    
    apt-get update -qq
    apt-get install -y mysql-server opensips-mysql-dbschema || {
        log_error "Failed to install MySQL server or schema package"
        exit 1
    }
    
    # Start MySQL service
    systemctl start mysql || systemctl start mariadb || {
        log_warn "MySQL/MariaDB service may already be running"
    }
    
    systemctl enable mysql 2>/dev/null || systemctl enable mariadb 2>/dev/null || true
    
    log_success "MySQL server and schema package installed"
}

# Step 2: Find MySQL schema file
find_mysql_schema() {
    # Send log messages to stderr so they don't interfere with stdout return value
    log_info "Locating OpenSIPS MySQL schema files..." >&2
    
    SCHEMA_DIR="/usr/share/opensips/mysql"
    
    if [[ ! -d "$SCHEMA_DIR" ]]; then
        log_error "MySQL schema directory not found: ${SCHEMA_DIR}" >&2
        log_error "Please install opensips-mysql-dbschema package" >&2
        exit 1
    fi
    
    # Core schema file
    STANDARD_SCHEMA="${SCHEMA_DIR}/standard-create.sql"
    if [[ ! -f "$STANDARD_SCHEMA" ]]; then
        log_error "Core schema file not found: ${STANDARD_SCHEMA}" >&2
        exit 1
    fi
    
    # Required module schemas for our setup
    REQUIRED_SCHEMAS=(
        "${SCHEMA_DIR}/standard-create.sql"
        "${SCHEMA_DIR}/dispatcher-create.sql"
        "${SCHEMA_DIR}/domain-create.sql"
    )
    
    # Check all required schemas exist
    for schema in "${REQUIRED_SCHEMAS[@]}"; do
        if [[ ! -f "$schema" ]]; then
            log_warn "Schema file not found: ${schema}" >&2
        fi
    done
    
    log_success "Found MySQL schema directory: ${SCHEMA_DIR}" >&2
    # Return absolute path to stdout (for variable capture)
    echo "$(readlink -f "${SCHEMA_DIR}" 2>/dev/null || echo "${SCHEMA_DIR}")"
}

# Step 3: Create MySQL database and user
create_mysql_database() {
    log_info "Creating MySQL database and user..."
    
    # Generate password if not provided
    if [[ -z "$MYSQL_PASSWORD" ]]; then
        # Try multiple methods to generate a secure password
        if command -v openssl &> /dev/null; then
            MYSQL_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)
        elif [[ -f /dev/urandom ]]; then
            MYSQL_PASSWORD=$(head -c 24 /dev/urandom | base64 | tr -d "=+/" | cut -c1-20)
        else
            # Fallback: use date + random number
            MYSQL_PASSWORD="opensips_$(date +%s)_$RANDOM"
        fi
        
        # Validate password was generated
        if [[ -z "$MYSQL_PASSWORD" ]] || [[ ${#MYSQL_PASSWORD} -lt 8 ]]; then
            log_error "Failed to generate MySQL password. Please provide one with --mysql-password"
            exit 1
        fi
        
        log_info "Generated MySQL password for user ${MYSQL_USER}"
        log_warn "SAVE THIS PASSWORD: ${MYSQL_PASSWORD}"
    fi
    
    # Validate password is not empty
    if [[ -z "$MYSQL_PASSWORD" ]]; then
        log_error "MySQL password cannot be empty. Please provide one with --mysql-password"
        exit 1
    fi
    
    # Escape password for MySQL (replace single quotes with escaped quotes)
    MYSQL_PASSWORD_ESCAPED=$(echo "$MYSQL_PASSWORD" | sed "s/'/''/g")
    
    # Determine which method to use for root access
    log_info "Testing MySQL root connection..."
    ROOT_CMD=""
    if [[ -n "${MYSQL_ROOT_PASSWORD:-}" ]]; then
        log_info "Using MySQL root password"
        export MYSQL_PWD="${MYSQL_ROOT_PASSWORD}"
        if mysql -u root -e "SELECT 1;" > /dev/null 2>&1; then
            ROOT_CMD="mysql -u root"
        else
            log_error "Failed to connect with root password"
            unset MYSQL_PWD
            exit 1
        fi
    elif sudo mysql -e "SELECT 1;" > /dev/null 2>&1; then
        log_info "Using sudo mysql (socket authentication)"
        ROOT_CMD="sudo mysql"
    elif mysql -u root -e "SELECT 1;" > /dev/null 2>&1; then
        log_info "Using mysql -u root (no password required)"
        ROOT_CMD="mysql -u root"
    else
        log_error "Cannot connect to MySQL as root"
        log_error "Please ensure MySQL is running and root access is configured"
        log_error "Try: sudo mysql"
        exit 1
    fi
    
    # Drop existing user/database if they exist (for clean start)
    log_info "Cleaning up any existing opensips user/database..."
    $ROOT_CMD <<EOF 2>&1 | grep -v "Unknown user\|Unknown database" || true
DROP USER IF EXISTS '${MYSQL_USER}'@'localhost';
DROP DATABASE IF EXISTS ${MYSQL_DB};
EOF
    
    # Create database and user
    log_info "Creating database: ${MYSQL_DB}"
    log_info "Creating user: ${MYSQL_USER}"
    $ROOT_CMD <<EOF
CREATE DATABASE ${MYSQL_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD_ESCAPED}';
GRANT ALL PRIVILEGES ON ${MYSQL_DB}.* TO '${MYSQL_USER}'@'localhost';
FLUSH PRIVILEGES;
SELECT 'Database and user created successfully' AS status;
EOF
    
    MYSQL_RESULT=$?
    
    # Clean up root password from environment
    if [[ -n "${MYSQL_ROOT_PASSWORD:-}" ]]; then
        unset MYSQL_PWD
    fi
    
    if [[ $MYSQL_RESULT -eq 0 ]]; then
        log_success "MySQL database and user created"
        log_info "Database: ${MYSQL_DB}"
        log_info "User: ${MYSQL_USER}"
        log_warn "Password: ${MYSQL_PASSWORD} (save this!)"
        
        # Verify the user can connect
        log_info "Verifying user can connect..."
        export MYSQL_PWD="${MYSQL_PASSWORD}"
        if mysql -u "${MYSQL_USER}" "${MYSQL_DB}" -e "SELECT 'Connection test successful' AS status;" > /dev/null 2>&1; then
            log_success "User authentication verified"
        else
            log_warn "User authentication test failed - but continuing anyway"
            log_warn "You may need to manually fix the password"
        fi
        unset MYSQL_PWD
    else
        log_error "Failed to create MySQL database or user"
        log_error "MySQL exit code: $MYSQL_RESULT"
        log_error "Try running manually: sudo mysql"
        exit 1
    fi
}

# Step 4: Load MySQL schema
load_mysql_schema() {
    local schema_dir="$1"
    
    log_info "Loading OpenSIPS MySQL schema..."
    
    # Verify schema directory exists
    if [[ ! -d "$schema_dir" ]]; then
        log_error "Schema directory not found: ${schema_dir}"
        exit 1
    fi
    
    log_info "Schema directory: ${schema_dir}"
    
    # Use MYSQL_PWD environment variable to avoid password in command line
    export MYSQL_PWD="${MYSQL_PASSWORD}"
    
    # Load core schema first
    STANDARD_SCHEMA="${schema_dir}/standard-create.sql"
    if [[ ! -f "$STANDARD_SCHEMA" ]]; then
        unset MYSQL_PWD
        log_error "Core schema file not found: ${STANDARD_SCHEMA}"
        log_info "Available files in ${schema_dir}:"
        ls -1 "${schema_dir}"/*.sql 2>/dev/null | head -10 || true
        exit 1
    fi
    
    log_info "Loading core schema: $(basename ${STANDARD_SCHEMA})"
    log_info "Full path: ${STANDARD_SCHEMA}"
    
    # Verify file is readable
    if [[ ! -r "$STANDARD_SCHEMA" ]]; then
        unset MYSQL_PWD
        log_error "Schema file is not readable: ${STANDARD_SCHEMA}"
        exit 1
    fi
    
    # Load the schema - capture both stdout and stderr
    log_info "Executing: mysql -u ${MYSQL_USER} ${MYSQL_DB} < ${STANDARD_SCHEMA}"
    if mysql -u "${MYSQL_USER}" "${MYSQL_DB}" < "${STANDARD_SCHEMA}" 2>&1; then
        log_success "Core schema loaded successfully"
    else
        local mysql_error=$?
        unset MYSQL_PWD
        log_error "Failed to load core schema (exit code: ${mysql_error})"
        log_error "File path: ${STANDARD_SCHEMA}"
        log_error "File exists: $([ -f "${STANDARD_SCHEMA}" ] && echo 'yes' || echo 'no')"
        log_error "File readable: $([ -r "${STANDARD_SCHEMA}" ] && echo 'yes' || echo 'no')"
        log_error "Trying to show file contents (first 5 lines):"
        head -5 "${STANDARD_SCHEMA}" 2>&1 || log_error "Could not read file"
        exit 1
    fi
    
    # Load required module schemas
    REQUIRED_SCHEMAS=(
        "dispatcher-create.sql"
        "domain-create.sql"
    )
    
    for schema_file in "${REQUIRED_SCHEMAS[@]}"; do
        local full_path="${schema_dir}/${schema_file}"
        if [[ -f "$full_path" ]]; then
            log_info "Loading module schema: ${schema_file}"
            if mysql -u "${MYSQL_USER}" "${MYSQL_DB}" < "$full_path" 2>&1; then
                log_success "Loaded: ${schema_file}"
            else
                local mysql_error=$?
                unset MYSQL_PWD
                log_error "Failed to load schema: ${schema_file} (exit code: ${mysql_error})"
                exit 1
            fi
        else
            log_warn "Schema file not found: ${schema_file} (skipping)"
        fi
    done
    
    unset MYSQL_PWD
    
    log_success "MySQL schema loaded"
}

# Step 5: Create custom tables
create_custom_tables() {
    log_info "Creating custom routing tables in MySQL..."
    
    # Use MYSQL_PWD environment variable to avoid password in command line
    export MYSQL_PWD="${MYSQL_PASSWORD}"
    mysql -u "${MYSQL_USER}" "${MYSQL_DB}" <<EOF
-- Custom domain routing table (links domains to dispatcher sets)
CREATE TABLE IF NOT EXISTS sip_domains (
    domain VARCHAR(128) PRIMARY KEY,
    dispatcher_setid INT NOT NULL,
    enabled TINYINT NOT NULL DEFAULT 1,
    comment VARCHAR(255),
    INDEX idx_sip_domains_enabled (enabled)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Endpoint locations table (for routing OPTIONS from Asterisk to endpoints)
CREATE TABLE IF NOT EXISTS endpoint_locations (
    aor VARCHAR(255) PRIMARY KEY,
    contact_ip VARCHAR(64) NOT NULL,
    contact_port VARCHAR(16) NOT NULL,
    expires DATETIME NOT NULL,
    INDEX idx_endpoint_locations_expires (expires)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOF
    
    if [[ $? -eq 0 ]]; then
        log_success "Custom tables created"
    else
        log_error "Failed to create custom tables"
        exit 1
    fi
}

# Step 6: Migrate data from SQLite (if exists)
migrate_data() {
    if [[ ! -f "$SQLITE_DB" ]]; then
        log_info "No SQLite database found, skipping data migration"
        return
    fi
    
    log_info "Checking for data to migrate from SQLite..."
    
    # Check if there's any data
    local domain_count=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM sip_domains;" 2>/dev/null || echo "0")
    local dispatcher_count=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM dispatcher;" 2>/dev/null || echo "0")
    local endpoint_count=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM endpoint_locations;" 2>/dev/null || echo "0")
    
    if [[ "$domain_count" == "0" ]] && [[ "$dispatcher_count" == "0" ]] && [[ "$endpoint_count" == "0" ]]; then
        log_info "No data to migrate (all tables are empty)"
        return
    fi
    
    log_warn "Data migration from SQLite to MySQL is not automated in this script"
    log_info "Domain records: ${domain_count}"
    log_info "Dispatcher records: ${dispatcher_count}"
    log_info "Endpoint records: ${endpoint_count}"
    log_info "You may need to manually export/import this data if needed"
}

# Step 7: Update OpenSIPS configuration
update_opensips_config() {
    log_info "Updating OpenSIPS configuration to use MySQL..."
    
    local OPENSIPS_CFG="${OPENSIPS_DIR}/opensips.cfg"
    
    if [[ ! -f "$OPENSIPS_CFG" ]]; then
        log_error "OpenSIPS config not found at ${OPENSIPS_CFG}"
        exit 1
    fi
    
    # Backup config
    cp "$OPENSIPS_CFG" "${OPENSIPS_CFG}.backup.$(date +%Y%m%d_%H%M%S)"
    log_info "Backed up config to ${OPENSIPS_CFG}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Replace db_sqlite with db_mysql
    sed -i 's/loadmodule "db_sqlite\.so"/loadmodule "db_mysql.so"/g' "$OPENSIPS_CFG"
    
    # Update database URLs
    local mysql_url="mysql://${MYSQL_USER}:${MYSQL_PASSWORD}@localhost/${MYSQL_DB}"
    
    # Use Python to handle multi-line replacement properly
    python3 <<PYTHON_SCRIPT
import re

mysql_url = "${mysql_url}"
config_file = "${OPENSIPS_CFG}"

with open(config_file, 'r') as f:
    lines = f.readlines()

# Process lines to remove multi-line modparam blocks
output_lines = []
i = 0
while i < len(lines):
    line = lines[i]
    
    # Check if this is a modparam("sqlops", "db_url", or modparam("dispatcher", "db_url", line
    if re.match(r'^\s*modparam\("(sqlops|dispatcher)",\s*"db_url",', line):
        # Found the start of a db_url modparam - replace it with single line
        if 'sqlops' in line:
            output_lines.append(f'modparam("sqlops", "db_url", "{mysql_url}")\n')
        else:
            output_lines.append(f'modparam("dispatcher", "db_url", "{mysql_url}")\n')
        
        # Skip following lines that are part of this multi-line modparam
        i += 1
        skipped_blank = False
        while i < len(lines):
            next_line = lines[i]
            stripped = next_line.strip()
            
            # Skip comment lines
            if stripped.startswith('#'):
                i += 1
                continue
            # Skip lines with just a URL (sqlite or mysql)
            if re.match(r'^"[^"]*://[^"]*"$', stripped):
                i += 1
                continue
            # Skip lines with URL and closing paren
            if re.match(r'^\s*"[^"]*://[^"]*"\s*\)', stripped):
                i += 1
                break
            # If we hit a blank line after skipping some lines, include it and break
            if stripped == '':
                if skipped_blank:
                    break
                skipped_blank = True
                i += 1
                continue
            # If we hit the next statement, we're done
            if stripped.startswith('modparam') or stripped.startswith('loadmodule') or stripped.startswith('#'):
                break
            # If line has just closing paren, skip it
            if stripped == ')':
                i += 1
                break
            # Otherwise, we've moved past the modparam block
            break
        
        continue
    
    output_lines.append(line)
    i += 1

# Write back
with open(config_file, 'w') as f:
    f.writelines(output_lines)
PYTHON_SCRIPT
    
    # Fix datetime syntax if present (SQLite uses datetime('now'), MySQL uses NOW())
    sed -i "s/datetime('now'/NOW()/g" "$OPENSIPS_CFG"
    sed -i "s/datetime('now', '+\([0-9]*\) seconds')/DATE_ADD(NOW(), INTERVAL \1 SECOND)/g" "$OPENSIPS_CFG"
    
    log_success "OpenSIPS configuration updated"
    log_warn "MySQL password is stored in plain text in the config file"
    log_warn "Consider securing the config file: chmod 640 ${OPENSIPS_CFG}"
}

# Step 8: Test configuration
test_config() {
    log_info "Testing OpenSIPS configuration..."
    
    local OPENSIPS_CFG="${OPENSIPS_DIR}/opensips.cfg"
    
    if opensips -C -f "$OPENSIPS_CFG" > /dev/null 2>&1; then
        log_success "OpenSIPS configuration syntax is valid"
    else
        log_error "OpenSIPS configuration has errors. Check the output above."
        opensips -C -f "$OPENSIPS_CFG"
        exit 1
    fi
}

# Step 9: Save credentials
save_credentials() {
    local cred_file="${OPENSIPS_DIR}/.mysql_credentials"
    
    cat > "$cred_file" <<EOF
# MySQL Database Credentials for OpenSIPS
# Generated: $(date)
# 
# DO NOT COMMIT THIS FILE TO VERSION CONTROL
#
DATABASE=${MYSQL_DB}
USER=${MYSQL_USER}
PASSWORD=${MYSQL_PASSWORD}
CONNECTION_STRING=mysql://${MYSQL_USER}:${MYSQL_PASSWORD}@localhost/${MYSQL_DB}
EOF
    
    chmod 600 "$cred_file"
    chown "${OPENSIPS_USER}:${OPENSIPS_GROUP}" "$cred_file"
    
    log_success "Credentials saved to ${cred_file} (readable only by root/opensips)"
}

# Main execution
main() {
    echo
    echo "=========================================="
    echo "OpenSIPS SQLite to MySQL Migration"
    echo "=========================================="
    echo
    
    check_root
    
    log_info "Starting migration from SQLite to MySQL..."
    echo
    
    install_mysql
    SCHEMA_DIR=$(find_mysql_schema)
    create_mysql_database
    load_mysql_schema "$SCHEMA_DIR"
    create_custom_tables
    migrate_data
    update_opensips_config
    test_config
    save_credentials
    
    echo
    log_success "Migration complete!"
    echo
    log_info "Next steps:"
    echo "  1. Review the updated configuration: ${OPENSIPS_DIR}/opensips.cfg"
    echo "  2. Restart OpenSIPS: systemctl restart opensips"
    echo "  3. Verify MySQL connection in logs: journalctl -u opensips -f"
    echo "  4. Test functionality with your SIP endpoints"
    echo
    log_warn "MySQL credentials saved to: ${OPENSIPS_DIR}/.mysql_credentials"
    echo
}

main "$@"

