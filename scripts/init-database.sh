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
if [[ -f "$SCHEMA_FILE" ]]; then
    echo "Loading full OpenSIPS 3.6.3 schema from ${SCHEMA_FILE}..."
    sqlite3 "$DB_PATH" < "$SCHEMA_FILE"
    echo "Full schema loaded successfully."
else
    echo "Warning: Schema file not found at ${SCHEMA_FILE}"
    echo "Creating minimal schema instead..."
    sqlite3 "$DB_PATH" <<EOF
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA cache_size = -64000;
PRAGMA wal_autocheckpoint = 1000;

-- Version table (required by OpenSIPS modules)
CREATE TABLE IF NOT EXISTS version (
    table_name CHAR(32) NOT NULL,
    table_version INTEGER DEFAULT 0 NOT NULL,
    CONSTRAINT version_t_name_idx UNIQUE (table_name)
);

-- Dispatcher table (OpenSIPS 3.6 version 9 schema)
CREATE TABLE IF NOT EXISTS dispatcher (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    setid INTEGER DEFAULT 0 NOT NULL,
    destination CHAR(192) DEFAULT '' NOT NULL,
    socket CHAR(128) DEFAULT NULL,
    state INTEGER DEFAULT 0 NOT NULL,
    probe_mode INTEGER DEFAULT 0 NOT NULL,
    weight CHAR(64) DEFAULT 1 NOT NULL,
    priority INTEGER DEFAULT 0 NOT NULL,
    attrs CHAR(128) DEFAULT NULL,
    description CHAR(64) DEFAULT NULL
);

-- Location table (usrloc module, version 1013)
CREATE TABLE IF NOT EXISTS location (
    contact_id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    username CHAR(64) DEFAULT '' NOT NULL,
    domain CHAR(64) DEFAULT NULL,
    contact TEXT NOT NULL,
    received CHAR(255) DEFAULT NULL,
    path CHAR(255) DEFAULT NULL,
    expires INTEGER NOT NULL,
    q FLOAT(10,2) DEFAULT 1.0 NOT NULL,
    callid CHAR(255) DEFAULT 'Default-Call-ID' NOT NULL,
    cseq INTEGER DEFAULT 13 NOT NULL,
    last_modified DATETIME DEFAULT '1900-01-01 00:00:01' NOT NULL,
    flags INTEGER DEFAULT 0 NOT NULL,
    cflags CHAR(255) DEFAULT NULL,
    user_agent CHAR(255) DEFAULT '' NOT NULL,
    socket CHAR(64) DEFAULT NULL,
    methods INTEGER DEFAULT NULL,
    sip_instance CHAR(255) DEFAULT NULL,
    kv_store TEXT(512) DEFAULT NULL,
    attr CHAR(255) DEFAULT NULL
);

-- Initialize version table
INSERT OR REPLACE INTO version (table_name, table_version) VALUES ('dispatcher', 9);
INSERT OR REPLACE INTO version (table_name, table_version) VALUES ('location', 1013);
EOF
fi

# Add our custom tables (required for routing logic)
echo "Adding custom routing tables..."
sqlite3 "$DB_PATH" <<EOF
-- Custom domain routing table (links domains to dispatcher sets)
CREATE TABLE IF NOT EXISTS sip_domains (
    domain TEXT PRIMARY KEY,
    dispatcher_setid INTEGER NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    comment TEXT
);

CREATE INDEX IF NOT EXISTS idx_sip_domains_enabled ON sip_domains(enabled);

-- Endpoint locations table (for routing OPTIONS from Asterisk to endpoints)
CREATE TABLE IF NOT EXISTS endpoint_locations (
    aor TEXT PRIMARY KEY,
    contact_ip TEXT NOT NULL,
    contact_port TEXT NOT NULL,
    expires TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_endpoint_locations_expires ON endpoint_locations(expires);

-- Ensure dispatcher table has correct version entry
INSERT OR REPLACE INTO version (table_name, table_version) VALUES ('dispatcher', 9);

-- Ensure location table has correct version entry
INSERT OR REPLACE INTO version (table_name, table_version) VALUES ('location', 1013);

-- Add a test dispatcher entry (can be deleted later)
-- OpenSIPS may require at least one row to validate the schema
INSERT OR IGNORE INTO dispatcher (setid, destination, state, probe_mode, weight, priority)
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
