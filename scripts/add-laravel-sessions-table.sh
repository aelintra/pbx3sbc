#!/bin/bash
#
# Add Laravel sessions table to existing OpenSIPS database
# This script adds the sessions table required by Laravel/Filament admin panel
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

echo "Adding Laravel sessions table to database '${DB_NAME}'..."
echo

# Check if table already exists
if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES LIKE 'sessions';" 2>/dev/null | grep -q "sessions"; then
    echo "  ✓ sessions table already exists - skipping"
    echo
    echo "Laravel sessions table migration complete!"
    exit 0
fi

# Create the table
echo "  Creating sessions table..."
if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "${SCRIPT_DIR}/add-laravel-sessions-table.sql" 2>&1 | grep -v "already exists" | grep -v "^$"; then
    echo "  ✓ sessions table created"
else
    echo "  Error: Failed to create sessions table"
    exit 1
fi

echo
echo "Laravel sessions table migration complete!"
echo
echo "You can verify the table was created with:"
echo "  mysql -u ${DB_USER} -p opensips -e 'DESCRIBE sessions;'"
