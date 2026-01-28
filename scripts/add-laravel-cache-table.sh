#!/bin/bash
#
# Add Laravel cache tables to existing OpenSIPS database
# This script adds the cache and cache_locks tables required by Laravel/Filament admin panel
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load database credentials if available
if [[ -f /etc/opensips/.mysql_credentials ]]; then
    source /etc/opensips/.mysql_credentials
fi

DB_NAME="${DB_NAME:-opensips}"
DB_USER="${DB_USER:-opensips}"
DB_PASS="${DB_PASS:-your-password}"

# Check if running as root (for reading credentials file)
if [[ $EUID -ne 0 ]] && [[ ! -f /etc/opensips/.mysql_credentials ]]; then
    echo "Warning: Not running as root and credentials file not found."
    echo "Using default credentials. You may need to provide password."
fi

echo "Adding Laravel cache tables to database '${DB_NAME}'..."
echo

# Check if tables already exist
if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES LIKE 'cache';" 2>/dev/null | grep -q "cache"; then
    echo "  ✓ cache table already exists - skipping"
else
    echo "  Creating cache table..."
    if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "${SCRIPT_DIR}/add-laravel-cache-table.sql" 2>&1 | grep -v "already exists" | grep -v "^$"; then
        echo "  ✓ cache table created"
    else
        echo "  Error: Failed to create cache table"
        exit 1
    fi
fi

if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES LIKE 'cache_locks';" 2>/dev/null | grep -q "cache_locks"; then
    echo "  ✓ cache_locks table already exists - skipping"
else
    echo "  Creating cache_locks table..."
    # The SQL file creates both tables, so if cache exists but cache_locks doesn't, run just that part
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
CREATE TABLE IF NOT EXISTS cache_locks (
    \`key\` VARCHAR(255) NOT NULL PRIMARY KEY,
    owner VARCHAR(255) NOT NULL,
    expiration INT NOT NULL,
    INDEX idx_cache_locks_expiration (expiration)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOF
    echo "  ✓ cache_locks table created"
fi

echo
echo "Laravel cache tables migration complete!"
echo
echo "You can verify the tables were created with:"
echo "  mysql -u ${DB_USER} -p opensips -e 'SHOW TABLES LIKE \"cache%\";'"
