#!/bin/bash
#
# Fix Laravel migrations by creating missing tables and marking migrations as complete
# This handles the case where migrations partially ran but tables are missing
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

echo "Fixing Laravel migrations for database '${DB_NAME}'..."
echo

# Run the SQL fix script
if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "${SCRIPT_DIR}/fix-laravel-migrations.sql" 2>&1; then
    echo "  ✓ Laravel tables created/verified"
    echo "  ✓ Migrations marked as complete"
    echo
    echo "Laravel migrations fixed successfully!"
    echo
    echo "You can now run remaining migrations:"
    echo "  cd /path/to/pbx3sbc-admin"
    echo "  php artisan migrate --force"
else
    echo "  Error: Failed to fix migrations"
    exit 1
fi
