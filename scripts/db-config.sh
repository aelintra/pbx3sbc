#!/bin/bash
#
# Database configuration helper
# Detects and provides database connection details
#

# Try to read from credentials file first
CRED_FILE="/etc/opensips/.mysql_credentials"
if [[ -f "$CRED_FILE" ]]; then
    # Source the credentials file
    source "$CRED_FILE" 2>/dev/null || true
fi

# Check if MySQL is configured
if [[ -n "${CONNECTION_STRING:-}" ]] && [[ "$CONNECTION_STRING" =~ ^mysql:// ]]; then
    DB_TYPE="mysql"
    # Parse connection string: mysql://user:pass@host/db
    DB_CONN_STR="$CONNECTION_STRING"
    DB_USER="${USER:-opensips}"
    DB_PASS="${PASSWORD:-}"
    DB_HOST="${DB_HOST:-localhost}"
    DB_NAME="${DATABASE:-opensips}"
elif [[ -f "/etc/opensips/opensips.db" ]]; then
    DB_TYPE="sqlite"
    DB_PATH="/etc/opensips/opensips.db"
else
    DB_TYPE="sqlite"
    DB_PATH="/var/lib/opensips/routing.db"
fi

# Export variables
export DB_TYPE
export DB_CONN_STR
export DB_USER
export DB_PASS
export DB_HOST
export DB_NAME
export DB_PATH

