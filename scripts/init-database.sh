#!/bin/bash
#
# Initialize or reset the Kamailio routing database
#

set -euo pipefail

DB_PATH="${DB_PATH:-/var/lib/kamailio/routing.db}"
KAMAILIO_USER="${KAMAILIO_USER:-kamailio}"
KAMAILIO_GROUP="${KAMAILIO_GROUP:-kamailio}"

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

echo "Initializing Kamailio routing database at ${DB_PATH}..."

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

-- Version table (required by Kamailio modules)
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

-- Dispatcher destinations table
CREATE TABLE IF NOT EXISTS dispatcher (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    setid INTEGER NOT NULL,
    destination TEXT NOT NULL,
    flags INTEGER DEFAULT 0,
    priority INTEGER DEFAULT 0,
    attrs TEXT
);

CREATE INDEX IF NOT EXISTS idx_dispatcher_setid ON dispatcher(setid);

-- Endpoint locations table (for routing OPTIONS from Asterisk to endpoints)
CREATE TABLE IF NOT EXISTS endpoint_locations (
    aor TEXT PRIMARY KEY,
    contact_ip TEXT NOT NULL,
    contact_port TEXT NOT NULL,
    expires TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_endpoint_locations_expires ON endpoint_locations(expires);

-- Initialize version table with dispatcher module version
INSERT OR IGNORE INTO version (table_name, table_version) VALUES ('dispatcher', 4);
EOF

# Set permissions
chown "${KAMAILIO_USER}:${KAMAILIO_GROUP}" "$DB_PATH"
chmod 644 "$DB_PATH"

echo "Database initialized successfully!"
echo
echo "Add domains and dispatcher entries:"
echo "  sqlite3 ${DB_PATH}"
echo
echo "Example:"
echo "  INSERT INTO sip_domains (domain, dispatcher_setid, enabled) VALUES ('example.com', 10, 1);"
echo "  INSERT INTO dispatcher (setid, destination) VALUES (10, 'sip:10.0.1.10:5060');"
