#!/bin/bash
#
# Initialize or reset the OpenSIPS MySQL routing database
#

set -euo pipefail

# Try to read database credentials from credentials file (created by install.sh)
CRED_FILE="/etc/opensips/.mysql_credentials"
if [[ -f "$CRED_FILE" ]]; then
    # Source the credentials file to get DB_NAME, DB_USER, DB_PASS
    source "$CRED_FILE" 2>/dev/null || true
fi

# Set defaults if not already set from credentials file
DB_NAME="${DB_NAME:-opensips}"
DB_USER="${DB_USER:-opensips}"
DB_PASS="${DB_PASS:-your-password}"
OPENSIPS_USER="${OPENSIPS_USER:-opensips}"
OPENSIPS_GROUP="${OPENSIPS_GROUP:-opensips}"

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

# Warn if using default password
if [[ "$DB_PASS" == "your-password" ]]; then
    echo "Warning: Using default password 'your-password'"
    echo "  If this is incorrect, either:"
    echo "    1. Set DB_PASS environment variable: sudo DB_PASS='your-password' ./scripts/init-database.sh"
    echo "    2. Create credentials file: sudo ./scripts/setup-db-credentials.sh [password]"
    echo "    3. Source credentials file manually if it exists at ${CRED_FILE}"
    echo
fi

echo "Initializing OpenSIPS MySQL database '${DB_NAME}'..."

# Schema files location (installed with OpenSIPS packages)
SCHEMA_DIR="/usr/share/opensips/mysql"

# Check if schema directory exists
if [[ ! -d "$SCHEMA_DIR" ]]; then
    echo "Error: OpenSIPS MySQL schema directory not found at ${SCHEMA_DIR}"
    echo "Please ensure OpenSIPS packages are installed."
    exit 1
fi

# Required schema files
# Note: standard-create.sql only creates the version table
# Each OpenSIPS module has its own create file
SCHEMA_FILES=(
    "standard-create.sql"      # Creates version table only
    "acc-create.sql"                # Accounting/CDR tables (acc, missed_calls)
    "dispatcher-create.sql"         # Dispatcher table
    "domain-create.sql"             # Domain table
)

# Check if schema files exist
MISSING_FILES=()
for schema_file in "${SCHEMA_FILES[@]}"; do
    if [[ ! -f "${SCHEMA_DIR}/${schema_file}" ]]; then
        MISSING_FILES+=("${schema_file}")
    fi
done

if [[ ${#MISSING_FILES[@]} -gt 0 ]]; then
    echo "Warning: Some schema files not found:"
    for file in "${MISSING_FILES[@]}"; do
        echo "  - ${file}"
    done
    echo "Available schema files in ${SCHEMA_DIR}:"
    ls -1 "${SCHEMA_DIR}"/*.sql 2>/dev/null | sed 's|^|  |' || echo "  (none found)"
    echo
    echo "Continuing with available files..."
fi

# Load standard schema (creates version table only)
echo "Loading standard OpenSIPS schema from ${SCHEMA_DIR}/standard-create.sql..."
echo "  This creates the version table (schema version tracking)"
if [[ -f "${SCHEMA_DIR}/standard-create.sql" ]]; then
    if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "${SCHEMA_DIR}/standard-create.sql" 2>&1; then
        echo "  ✓ Standard schema loaded successfully"
    else
        echo "  ⚠ Warning: Failed to load standard-create.sql"
    fi
else
    echo "  ⚠ Warning: standard-create.sql not found, skipping"
fi

# Load accounting schema (acc, missed_calls tables)
echo "Loading accounting schema from ${SCHEMA_DIR}/acc-create.sql..."
echo "  This creates acc and missed_calls tables for CDR"
if [[ -f "${SCHEMA_DIR}/acc-create.sql" ]]; then
    if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "${SCHEMA_DIR}/acc-create.sql" 2>&1; then
        echo "  ✓ Accounting schema loaded successfully"
    else
        echo "  ⚠ Warning: Failed to load acc-create.sql"
    fi
else
    echo "  ⚠ Warning: acc-create.sql not found - accounting tables will not be created"
    echo "    You may need to install opensips-mysql-module or create acc table manually"
fi

# Load dispatcher schema
echo "Loading dispatcher schema from ${SCHEMA_DIR}/dispatcher-create.sql..."
if [[ -f "${SCHEMA_DIR}/dispatcher-create.sql" ]]; then
    if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "${SCHEMA_DIR}/dispatcher-create.sql" 2>&1; then
        echo "  ✓ Dispatcher schema loaded successfully"
    else
        echo "  ⚠ Warning: Failed to load dispatcher-create.sql"
    fi
else
    echo "  ⚠ Warning: dispatcher-create.sql not found, skipping"
fi

# Load domain schema
echo "Loading domain schema from ${SCHEMA_DIR}/domain-create.sql..."
if [[ -f "${SCHEMA_DIR}/domain-create.sql" ]]; then
    if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "${SCHEMA_DIR}/domain-create.sql" 2>&1; then
        echo "  ✓ Domain schema loaded successfully"
    else
        echo "  ⚠ Warning: Failed to load domain-create.sql"
    fi
else
    echo "  ⚠ Warning: domain-create.sql not found, skipping"
fi

# Show table count after loading all schemas
echo
TABLE_COUNT=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -sN -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';" 2>/dev/null || echo "0")
echo "Tables created so far: ${TABLE_COUNT}"
echo "Table list:"
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -sN -e "SHOW TABLES;" 2>/dev/null | sed 's/^/  - /' || echo "  (could not list tables)"
echo

# Create custom endpoint_locations table (MySQL syntax)
echo "Creating custom endpoint_locations table..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
CREATE TABLE IF NOT EXISTS endpoint_locations (
    aor VARCHAR(255) PRIMARY KEY,
    contact_ip VARCHAR(45) NOT NULL,
    contact_port VARCHAR(10) NOT NULL,
    contact_uri VARCHAR(255) NOT NULL,
    expires DATETIME NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_endpoint_locations_expires ON endpoint_locations(expires);
EOF

# Add contact_uri column to existing tables (if table exists but column doesn't)
echo "Ensuring contact_uri column exists in endpoint_locations table..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
SET @col_exists = (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS 
                   WHERE TABLE_SCHEMA = DATABASE() 
                   AND TABLE_NAME = 'endpoint_locations' 
                   AND COLUMN_NAME = 'contact_uri');
SET @sql = IF(@col_exists = 0,
    'ALTER TABLE endpoint_locations ADD COLUMN contact_uri VARCHAR(255) NOT NULL DEFAULT "" AFTER contact_port',
    'SELECT "Column contact_uri already exists" AS message');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Migrate existing data: populate contact_uri from aor if empty
UPDATE endpoint_locations SET contact_uri = CONCAT('sip:', aor) WHERE contact_uri = '' OR contact_uri IS NULL;
EOF

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

-- Update any existing domains to use id as setid
UPDATE domain SET setid = id WHERE setid = 0;

-- Add index if it doesn't exist
CREATE INDEX IF NOT EXISTS idx_domain_setid ON domain(setid);
EOF

echo "Custom tables and schema modifications created successfully."

# Final table count
FINAL_TABLE_COUNT=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -sN -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';" 2>/dev/null || echo "0")
echo
echo "Database initialized successfully!"
echo
echo "Database: ${DB_NAME}"
echo "User: ${DB_USER}"
echo "Total tables: ${FINAL_TABLE_COUNT}"
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
