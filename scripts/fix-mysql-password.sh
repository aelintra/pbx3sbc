#!/bin/bash
#
# Fix MySQL password for opensips user
# Use this if the migration script created a user with empty password
#
# Usage: sudo ./scripts/fix-mysql-password.sh [password]
#

set -euo pipefail

MYSQL_DB="opensips"
MYSQL_USER="opensips"

if [[ $# -ge 1 ]]; then
    NEW_PASSWORD="$1"
else
    # Generate a secure password
    if command -v openssl &> /dev/null; then
        NEW_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)
    elif [[ -f /dev/urandom ]]; then
        NEW_PASSWORD=$(head -c 24 /dev/urandom | base64 | tr -d "=+/" | cut -c1-20)
    else
        NEW_PASSWORD="opensips_$(date +%s)_$RANDOM"
    fi
    echo "Generated password: ${NEW_PASSWORD}"
    echo "SAVE THIS PASSWORD!"
fi

if [[ -z "$NEW_PASSWORD" ]]; then
    echo "Error: Password cannot be empty"
    exit 1
fi

echo "Setting password for MySQL user ${MYSQL_USER}..."

mysql -u root <<EOF
ALTER USER '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${NEW_PASSWORD}';
FLUSH PRIVILEGES;
EOF

if [[ $? -eq 0 ]]; then
    echo "Password updated successfully!"
    echo "New password: ${NEW_PASSWORD}"
    echo
    echo "Now update the OpenSIPS config and credentials file:"
    echo "  1. Update /etc/opensips/opensips.cfg with the new password"
    echo "  2. Update /etc/opensips/.mysql_credentials with the new password"
    echo
    echo "Or re-run the migration script with: --mysql-password '${NEW_PASSWORD}'"
else
    echo "Error: Failed to update password"
    exit 1
fi

