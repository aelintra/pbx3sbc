#!/bin/bash
#
# Initialize or reset the OpenSIPS routing database
#

set -euo pipefail

DB_PATH="${DB_PATH:-/var/lib/opensips/routing.db}"
OPENSIPS_USER="${OPENSIPS_USER:-opensips}"
OPENSIPS_GROUP="${OPENSIPS_GROUP:-opensips}"

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

echo "Initializing OpenSIPS routing database at ${DB_PATH}..."

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEMA_FILE="${PROJECT_ROOT}/dbsource/opensips-3.6.3-sqlite3.sql"

# Backup existing database if it exists
if [[ -f "$DB_PATH" ]]; then
    BACKUP="${DB_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
    echo "Backing up existing database to ${BACKUP}..."
    cp "$DB_PATH" "$BACKUP"
    rm -f "${DB_PATH}-wal" "${DB_PATH}-shm"
fi

# Load full OpenSIPS 3.6.3 schema first
if [[ ! -f "$SCHEMA_FILE" ]]; then
    echo "Error: OpenSIPS schema file not found at ${SCHEMA_FILE}"
    echo "The full OpenSIPS database schema is required."
    exit 1
fi

echo "Loading full OpenSIPS 3.6.3 schema from ${SCHEMA_FILE}..."
sqlite3 "$DB_PATH" < "$SCHEMA_FILE"
echo "Full schema loaded successfully."

# Add our custom tables (required for routing logic)
echo "Adding custom routing tables..."
sqlite3 "$DB_PATH" <<EOF
-- Note: Using standard OpenSIPS 'domain' table (created by schema)
-- domain.id is used as dispatcher_setid for routing

-- Endpoint locations table (for routing OPTIONS from Asterisk to endpoints)
CREATE TABLE IF NOT EXISTS endpoint_locations (
    aor TEXT PRIMARY KEY,
    contact_ip TEXT NOT NULL,
    contact_port TEXT NOT NULL,
    expires TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_endpoint_locations_expires ON endpoint_locations(expires);
EOF

# Set permissions
chown "${OPENSIPS_USER}:${OPENSIPS_GROUP}" "$DB_PATH"
chmod 644 "$DB_PATH"

echo "Database initialized successfully!"
echo
echo "Add domains and dispatcher entries:"
echo "  Use the helper scripts:"
echo "    ./scripts/add-domain.sh <domain> <setid>"
echo "    ./scripts/add-dispatcher.sh <setid> <destination>"
echo
echo "Or use sqlite3 directly:"
echo "  sqlite3 ${DB_PATH}"
echo
echo "Example:"
echo "  INSERT INTO domain (domain) VALUES ('example.com');"
echo "  -- Note: Use domain.id as setid for dispatcher entries"
echo "  INSERT INTO dispatcher (setid, destination, priority, state, probe_mode) VALUES (1, 'sip:10.0.1.10:5060', 0, 0, 0);"
