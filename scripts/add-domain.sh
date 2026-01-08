#!/bin/bash
#
# Add a domain to the routing database
# Uses MySQL domain table with explicit setid column
#

set -euo pipefail

DB_NAME="${DB_NAME:-opensips}"
DB_USER="${DB_USER:-opensips}"
DB_PASS="${DB_PASS:-your-password}"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <domain> [setid]"
    echo
    echo "Example:"
    echo "  $0 example.com"
    echo "  $0 example.com 10"
    echo
    echo "Note: If setid is not provided, it defaults to the auto-generated domain ID"
    exit 1
fi

DOMAIN="$1"
SETID="$2"  # Optional setid

# Validate domain format (basic check)
if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]*[a-zA-Z0-9]$ ]]; then
    echo "Error: Invalid domain format: $DOMAIN"
    exit 1
fi

# Insert domain with setid
if [ -z "$SETID" ]; then
    # No setid provided, insert and get auto-generated ID
    DOMAIN_ID=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -sN <<EOF
INSERT INTO domain (domain, setid) VALUES ('$DOMAIN', 0);
SELECT LAST_INSERT_ID();
EOF
    )
    # Update setid to match id if it was 0
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "UPDATE domain SET setid = id WHERE id = $DOMAIN_ID AND setid = 0;" >/dev/null 2>&1
    SETID=$DOMAIN_ID
else
    # Setid provided, use it
    DOMAIN_ID=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -sN <<EOF
INSERT INTO domain (domain, setid) VALUES ('$DOMAIN', $SETID);
SELECT LAST_INSERT_ID();
EOF
    )
fi

if [[ $? -eq 0 ]] && [[ -n "$DOMAIN_ID" ]]; then
    echo "Domain '$DOMAIN' added successfully"
    echo "Domain ID: $DOMAIN_ID"
    echo "Set ID: $SETID (use this for dispatcher entries)"
else
    echo "Error: Failed to add domain"
    exit 1
fi
