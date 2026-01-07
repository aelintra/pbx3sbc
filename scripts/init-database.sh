#!/bin/bash
#
# Initialize or reset the OpenSIPS MySQL routing database
#

set -euo pipefail

DB_NAME="${DB_NAME:-opensips}"
DB_USER="${DB_USER:-opensips}"
DB_PASS="${DB_PASS:-rigmarole}"
OPENSIPS_USER="${OPENSIPS_USER:-opensips}"
OPENSIPS_GROUP="${OPENSIPS_GROUP:-opensips}"

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)"
    exit 1
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
SCHEMA_FILES=(
    "standard-create.sql"
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
echo "Loading core OpenSIPS schema from ${SCHEMA_DIR}/standard-create.sql..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "${SCHEMA_DIR}/standard-create.sql"
echo "Core schema loaded successfully."

# Load dispatcher schema
echo "Loading dispatcher schema from ${SCHEMA_DIR}/dispatcher-create.sql..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "${SCHEMA_DIR}/dispatcher-create.sql"
echo "Dispatcher schema loaded successfully."

# Load domain schema
echo "Loading domain schema from ${SCHEMA_DIR}/domain-create.sql..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "${SCHEMA_DIR}/domain-create.sql"
echo "Domain schema loaded successfully."

# Create custom endpoint_locations table (MySQL syntax)
echo "Creating custom endpoint_locations table..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
CREATE TABLE IF NOT EXISTS endpoint_locations (
    aor VARCHAR(255) PRIMARY KEY,
    contact_ip VARCHAR(45) NOT NULL,
    contact_port VARCHAR(10) NOT NULL,
    expires DATETIME NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_endpoint_locations_expires ON endpoint_locations(expires);
EOF

echo "Custom tables created successfully."

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
echo "  INSERT INTO domain (domain) VALUES ('example.com');"
echo "  -- Note: Use domain.id as setid for dispatcher entries"
echo "  INSERT INTO dispatcher (setid, destination, priority, state, probe_mode) VALUES (1, 'sip:10.0.1.10:5060', 0, 0, 0);"
