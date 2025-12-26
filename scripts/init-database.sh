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

# Backup existing database if it exists
if [[ -f "$DB_PATH" ]]; then
    BACKUP="${DB_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
    echo "Backing up existing database to ${BACKUP}..."
    cp "$DB_PATH" "$BACKUP"
    rm -f "${DB_PATH}-wal" "${DB_PATH}-shm"
fi

# Create database with schema
sqlite3 "$DB_PATH" <<EOF
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA cache_size = -64000;
PRAGMA wal_autocheckpoint = 1000;

-- Version table (required by OpenSIPS modules)
CREATE TABLE IF NOT EXISTS version (
    table_name VARCHAR(32) PRIMARY KEY,
    table_version INTEGER DEFAULT 0 NOT NULL
);

-- Domain routing table
CREATE TABLE IF NOT EXISTS sip_domains (
    domain TEXT PRIMARY KEY,
    dispatcher_setid INTEGER NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    comment TEXT
);

CREATE INDEX IF NOT EXISTS idx_sip_domains_enabled ON sip_domains(enabled);

-- Dispatcher destinations table (OpenSIPS 3.6 version 9 schema)
-- Drop and recreate to ensure correct schema
DROP TABLE IF EXISTS dispatcher;
CREATE TABLE dispatcher (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    setid INTEGER DEFAULT 0 NOT NULL,
    destination TEXT DEFAULT '' NOT NULL,
    socket TEXT,
    state INTEGER DEFAULT 0 NOT NULL,
    probe_mode INTEGER DEFAULT 0 NOT NULL,
    weight TEXT DEFAULT '1' NOT NULL,
    priority INTEGER DEFAULT 0 NOT NULL,
    attrs TEXT,
    description TEXT
);

CREATE INDEX idx_dispatcher_setid ON dispatcher(setid);

-- Endpoint locations table (for routing OPTIONS from Asterisk to endpoints)
CREATE TABLE IF NOT EXISTS endpoint_locations (
    aor TEXT PRIMARY KEY,
    contact_ip TEXT NOT NULL,
    contact_port TEXT NOT NULL,
    expires TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_endpoint_locations_expires ON endpoint_locations(expires);

-- Initialize version table with dispatcher module version
-- OpenSIPS 3.6 expects version 9 for dispatcher table
INSERT OR REPLACE INTO version (table_name, table_version) VALUES ('dispatcher', 9);

-- Add a test dispatcher entry (can be deleted later)
-- OpenSIPS may require at least one row to validate the schema
INSERT INTO dispatcher (setid, destination, state, probe_mode, weight, priority)
VALUES (0, 'sip:127.0.0.1:5060', 0, 0, '1', 0);
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
echo "  INSERT INTO sip_domains (domain, dispatcher_setid, enabled) VALUES ('example.com', 10, 1);"
echo "  INSERT INTO dispatcher (setid, destination, priority, state, probe_mode) VALUES (10, 'sip:10.0.1.10:5060', 0, 0, 0);"
