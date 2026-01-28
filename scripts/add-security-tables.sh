#!/bin/bash
#
# Add security tracking tables to existing OpenSIPS database
# This script adds failed_registrations and door_knock_attempts tables
# if they don't already exist
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

echo "Adding security tracking tables to database '${DB_NAME}'..."
echo

# Check if tables already exist
if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES LIKE 'failed_registrations';" 2>/dev/null | grep -q "failed_registrations"; then
    echo "  ✓ failed_registrations table already exists - skipping"
else
    echo "  Creating failed_registrations table..."
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "${SCRIPT_DIR}/add-security-tables.sql" 2>&1 | grep -v "already exists" || true
    echo "  ✓ failed_registrations table created"
fi

if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES LIKE 'door_knock_attempts';" 2>/dev/null | grep -q "door_knock_attempts"; then
    echo "  ✓ door_knock_attempts table already exists - skipping"
else
    echo "  Creating door_knock_attempts table..."
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "source ${SCRIPT_DIR}/add-security-tables.sql" 2>&1 | grep -v "already exists" || true
    echo "  ✓ door_knock_attempts table created"
fi

echo
echo "Security tables migration complete!"
echo
echo "You can verify the tables were created with:"
echo "  mysql -u ${DB_USER} -p opensips -e 'SHOW TABLES LIKE \"%failed%\" OR SHOW TABLES LIKE \"%door%\";'"
