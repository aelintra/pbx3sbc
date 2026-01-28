#!/bin/bash
#
# Initialize or reset the OpenSIPS MySQL routing database
#

set -euo pipefail

DB_NAME="${DB_NAME:-opensips}"
DB_USER="${DB_USER:-opensips}"
DB_PASS="${DB_PASS:-your-password}"
OPENSIPS_USER="${OPENSIPS_USER:-opensips}"
OPENSIPS_GROUP="${OPENSIPS_GROUP:-opensips}"

# Get script directory (for location table creation script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

echo "Initializing OpenSIPS MySQL database '${DB_NAME}'..."

# Verify database connection before proceeding
echo "Verifying database connection..."
if ! mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT 1;" >/dev/null 2>&1; then
    echo "Error: Cannot connect to database '${DB_NAME}' as user '${DB_USER}'"
    echo "Please verify database credentials are correct"
    exit 1
fi
echo "Database connection verified."
echo

# Schema files location (installed with OpenSIPS packages)
SCHEMA_DIR="/usr/share/opensips/mysql"

# Check if schema directory exists
if [[ ! -d "$SCHEMA_DIR" ]]; then
    echo "Error: OpenSIPS MySQL schema directory not found at ${SCHEMA_DIR}"
    echo "Please ensure OpenSIPS packages are installed."
    exit 1
fi

# Required schema files
SCHEMA_FILES=(
    "standard-create.sql"
    "acc-create.sql"
    "dialog-create.sql"
    "dispatcher-create.sql"
    "domain-create.sql"
)

# Check if schema files exist
for schema_file in "${SCHEMA_FILES[@]}"; do
    if [[ ! -f "${SCHEMA_DIR}/${schema_file}" ]]; then
        echo "Error: Schema file not found: ${SCHEMA_DIR}/${schema_file}"
        echo "Please ensure OpenSIPS packages are fully installed."
        exit 1
    fi
done

# Load core schema (standard-create.sql) - includes version table
# Idempotent: version table uses CREATE TABLE IF NOT EXISTS
echo "Loading core OpenSIPS schema from ${SCHEMA_DIR}/standard-create.sql..."
# Capture output and check for errors
SCHEMA_OUTPUT=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "${SCHEMA_DIR}/standard-create.sql" 2>&1)
SCHEMA_EXIT_CODE=$?

if [[ $SCHEMA_EXIT_CODE -ne 0 ]]; then
    echo "Error: Failed to load core schema (exit code: $SCHEMA_EXIT_CODE)"
    echo "$SCHEMA_OUTPUT" | grep -v "already exists" || echo "$SCHEMA_OUTPUT"
    exit 1
fi

# Show any warnings (but not "already exists" messages)
if echo "$SCHEMA_OUTPUT" | grep -v "already exists" | grep -v "^$" | grep -q "."; then
    echo "$SCHEMA_OUTPUT" | grep -v "already exists" | grep -v "^$"
fi

echo "Core schema loaded successfully."

# Load accounting schema (acc, missed_calls tables)
# Idempotent: check if table exists before loading
echo "Loading accounting schema from ${SCHEMA_DIR}/acc-create.sql..."
if [[ -f "${SCHEMA_DIR}/acc-create.sql" ]]; then
    # Check if acc table already exists
    if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES LIKE 'acc';" 2>/dev/null | grep -q "acc"; then
        echo "  ✓ acc table already exists - skipping schema load (idempotent)"
    else
        mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "${SCHEMA_DIR}/acc-create.sql"
        echo "  ✓ Accounting schema loaded successfully."
    fi
else
    echo "Warning: acc-create.sql not found - accounting tables will not be created"
    echo "  You may need to install opensips-mysql-module or create acc table manually"
fi

# Load dialog schema (for CDR mode - optional, dialog can work in-memory only)
# Idempotent: check if table exists before loading
echo "Loading dialog schema from ${SCHEMA_DIR}/dialog-create.sql..."
if [[ -f "${SCHEMA_DIR}/dialog-create.sql" ]]; then
    # Check if dialog table already exists
    if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES LIKE 'dialog';" 2>/dev/null | grep -q "dialog"; then
        echo "  ✓ dialog table already exists - skipping schema load (idempotent)"
    else
        mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "${SCHEMA_DIR}/dialog-create.sql"
        echo "  ✓ Dialog schema loaded successfully."
    fi
else
    echo "Warning: dialog-create.sql not found - dialog table will not be created"
    echo "  Dialog module can work in-memory only (db_mode=0), so this is optional"
fi

# Load dispatcher schema
# Idempotent: check if table exists before loading
echo "Loading dispatcher schema from ${SCHEMA_DIR}/dispatcher-create.sql..."
if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES LIKE 'dispatcher';" 2>/dev/null | grep -q "dispatcher"; then
    echo "  ✓ dispatcher table already exists - skipping schema load (idempotent)"
    echo "  Existing dispatcher entries are preserved"
else
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "${SCHEMA_DIR}/dispatcher-create.sql"
    echo "  ✓ Dispatcher schema loaded successfully."
fi

# Load domain schema
# Idempotent: check if table exists before loading
echo "Loading domain schema from ${SCHEMA_DIR}/domain-create.sql..."
if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES LIKE 'domain';" 2>/dev/null | grep -q "domain"; then
    echo "  ✓ domain table already exists - skipping schema load (idempotent)"
    echo "  Existing domain entries are preserved"
else
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "${SCHEMA_DIR}/domain-create.sql"
    echo "  ✓ Domain schema loaded successfully."
fi

# Ensure domain module version entry exists in version table (required for domain module)
echo "Ensuring domain module version entry exists..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
INSERT INTO version (table_name, table_version) VALUES ('domain', 4)
ON DUPLICATE KEY UPDATE table_version = 4;
EOF
echo "  ✓ Domain module version entry verified."

# Create OpenSIPS location table for usrloc module
# Idempotent: check if table exists before creating
echo "Creating OpenSIPS location table (for usrloc module)..."
if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES LIKE 'location';" 2>/dev/null | grep -q "location"; then
    echo "  ✓ location table already exists - skipping creation (idempotent)"
else
    # Use our custom location table script (converted from SQLite to MySQL)
    if [[ -f "${SCRIPT_DIR}/create-location-table.sql" ]]; then
        mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "${SCRIPT_DIR}/create-location-table.sql"
        echo "  ✓ Location table created successfully."
    else
        echo "  Warning: create-location-table.sql not found at ${SCRIPT_DIR}/create-location-table.sql"
        echo "  Location table will not be created - usrloc module migration will require manual table creation"
    fi
fi

# Ensure location module version entry exists in version table (required for usrloc module)
# Version 1013 is the expected version for OpenSIPS 3.6.3
echo "Ensuring location module version entry exists..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
INSERT INTO version (table_name, table_version) VALUES ('location', 1013)
ON DUPLICATE KEY UPDATE table_version = 1013;
EOF
echo "  ✓ Location module version entry verified."

# Note: endpoint_locations table creation removed - migration to location table complete
# All endpoint location tracking now uses OpenSIPS standard location table via usrloc module
# See scripts/create-location-table.sql for location table schema

# Add setid column to domain table (if not exists)
echo "Adding setid column to domain table..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
SET @col_exists = (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS 
                   WHERE TABLE_SCHEMA = DATABASE() 
                   AND TABLE_NAME = 'domain' 
                   AND COLUMN_NAME = 'setid');
SET @sql = IF(@col_exists = 0,
    'ALTER TABLE domain ADD COLUMN setid INT NOT NULL DEFAULT 0',
    'SELECT ''Column setid already exists'' AS message');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Update any existing domains to use id as setid and populate attrs
UPDATE domain SET setid = id, attrs = CONCAT('setid=', id) WHERE setid = 0 AND (attrs IS NULL OR attrs = '');

-- Add index if it doesn't exist
CREATE INDEX IF NOT EXISTS idx_domain_setid ON domain(setid);
EOF

# Add from_uri and to_uri columns to acc table for billing (if not exists)
echo "Adding from_uri and to_uri columns to acc table for billing..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
-- Add from_uri column if it doesn't exist
SET @col_exists = (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS 
                   WHERE TABLE_SCHEMA = DATABASE() 
                   AND TABLE_NAME = 'acc' 
                   AND COLUMN_NAME = 'from_uri');
SET @sql = IF(@col_exists = 0,
    'ALTER TABLE acc ADD COLUMN from_uri VARCHAR(255) DEFAULT NULL AFTER to_tag',
    'SELECT "Column from_uri already exists" AS message');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Add to_uri column if it doesn't exist
SET @col_exists = (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS 
                   WHERE TABLE_SCHEMA = DATABASE() 
                   AND TABLE_NAME = 'acc' 
                   AND COLUMN_NAME = 'to_uri');
SET @sql = IF(@col_exists = 0,
    'ALTER TABLE acc ADD COLUMN to_uri VARCHAR(255) DEFAULT NULL AFTER from_uri',
    'SELECT "Column to_uri already exists" AS message');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
EOF

# Create failed_registrations table for security tracking (Phase 1.1)
# Idempotent: check if table exists before creating
echo "Creating failed_registrations table (security tracking)..."
if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES LIKE 'failed_registrations';" 2>/dev/null | grep -q "failed_registrations"; then
    echo "  ✓ failed_registrations table already exists - skipping creation (idempotent)"
else
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
CREATE TABLE failed_registrations (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64) NOT NULL,
    domain VARCHAR(128) NOT NULL,
    source_ip VARCHAR(45) NOT NULL,
    source_port INT NOT NULL,
    user_agent VARCHAR(255) DEFAULT NULL,
    response_code INT NOT NULL,
    response_reason VARCHAR(255) DEFAULT NULL,
    attempt_time DATETIME NOT NULL,
    expires_header INT DEFAULT NULL,
    INDEX idx_username_domain_time (username, domain, attempt_time),
    INDEX idx_source_ip_time (source_ip, attempt_time),
    INDEX idx_attempt_time (attempt_time),
    INDEX idx_response_code (response_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
EOF
    echo "  ✓ failed_registrations table created successfully."
fi

# Create door_knock_attempts table for security tracking (Phase 1.1)
# Idempotent: check if table exists before creating
echo "Creating door_knock_attempts table (security tracking)..."
if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES LIKE 'door_knock_attempts';" 2>/dev/null | grep -q "door_knock_attempts"; then
    echo "  ✓ door_knock_attempts table already exists - skipping creation (idempotent)"
else
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
CREATE TABLE door_knock_attempts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    domain VARCHAR(128) DEFAULT NULL,
    source_ip VARCHAR(45) NOT NULL,
    source_port INT NOT NULL,
    user_agent VARCHAR(255) DEFAULT NULL,
    method VARCHAR(16) NOT NULL,
    request_uri VARCHAR(255) DEFAULT NULL,
    reason VARCHAR(128) NOT NULL,
    attempt_time DATETIME NOT NULL,
    INDEX idx_domain_time (domain, attempt_time),
    INDEX idx_source_ip_time (source_ip, attempt_time),
    INDEX idx_attempt_time (attempt_time),
    INDEX idx_reason (reason)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
EOF
    echo "  ✓ door_knock_attempts table created successfully."
fi

# Create Laravel sessions table for admin panel
# Idempotent: check if table exists before creating
echo "Creating Laravel sessions table (for admin panel)..."
if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES LIKE 'sessions';" 2>/dev/null | grep -q "sessions"; then
    echo "  ✓ sessions table already exists - skipping creation (idempotent)"
else
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
CREATE TABLE sessions (
    id VARCHAR(255) NOT NULL PRIMARY KEY,
    user_id BIGINT UNSIGNED NULL,
    ip_address VARCHAR(45) NULL,
    user_agent TEXT NULL,
    payload LONGTEXT NOT NULL,
    last_activity INT NOT NULL,
    INDEX idx_sessions_user_id (user_id),
    INDEX idx_sessions_last_activity (last_activity)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOF
    echo "  ✓ sessions table created successfully."
fi

# Create Laravel cache tables for admin panel
# Idempotent: check if table exists before creating
echo "Creating Laravel cache tables (for admin panel)..."
if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES LIKE 'cache';" 2>/dev/null | grep -q "cache"; then
    echo "  ✓ cache table already exists - skipping creation (idempotent)"
else
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
CREATE TABLE cache (
    \`key\` VARCHAR(255) NOT NULL PRIMARY KEY,
    value MEDIUMTEXT NOT NULL,
    expiration INT NOT NULL,
    INDEX idx_cache_expiration (expiration)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOF
    echo "  ✓ cache table created successfully."
fi

if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES LIKE 'cache_locks';" 2>/dev/null | grep -q "cache_locks"; then
    echo "  ✓ cache_locks table already exists - skipping creation (idempotent)"
else
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
CREATE TABLE cache_locks (
    \`key\` VARCHAR(255) NOT NULL PRIMARY KEY,
    owner VARCHAR(255) NOT NULL,
    expiration INT NOT NULL,
    INDEX idx_cache_locks_expiration (expiration)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOF
    echo "  ✓ cache_locks table created successfully."
fi

echo "Custom tables and schema modifications created successfully."

echo "Database initialized successfully!"
echo
echo "Database: ${DB_NAME}"
echo "User: ${DB_USER}"
echo
echo "Add domains and dispatcher entries:"
echo "  Use the helper scripts:"
echo "    ./scripts/add-domain.sh <domain>"
echo "    ./scripts/add-dispatcher.sh <setid> <destination>"
echo
echo "Or use mysql directly:"
echo "  mysql -u ${DB_USER} -p'${DB_PASS}' ${DB_NAME}"
echo
echo "Example:"
echo "  INSERT INTO domain (domain, setid) VALUES ('example.com', 10);"
echo "  -- Note: Use domain.setid for dispatcher entries"
echo "  INSERT INTO dispatcher (setid, destination, priority, state, probe_mode) VALUES (10, 'sip:10.0.1.10:5060', 0, 0, 0);"
