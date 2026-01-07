#!/bin/bash
#
# Add a domain to the routing database
# Uses standard OpenSIPS domain table - domain.id is used as dispatcher_setid
#

set -euo pipefail

DB_PATH="${DB_PATH:-/var/lib/opensips/routing.db}"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <domain>"
    echo
    echo "Example:"
    echo "  $0 example.com"
    echo
    echo "Note: domain.id (auto-generated) should be used as setid for dispatcher entries"
    exit 1
fi

DOMAIN="$1"

# Validate domain format (basic check)
if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]*[a-zA-Z0-9]$ ]]; then
    echo "Error: Invalid domain format: $DOMAIN"
    exit 1
fi

# Insert domain and get the generated ID
DOMAIN_ID=$(sqlite3 "$DB_PATH" <<EOF
INSERT INTO domain (domain) VALUES ('$DOMAIN');
SELECT last_insert_rowid();
EOF
)

if [[ $? -eq 0 ]] && [[ -n "$DOMAIN_ID" ]]; then
    echo "Domain added: $DOMAIN (id=$DOMAIN_ID)"
    echo "Use setid=$DOMAIN_ID for dispatcher entries"
else
    echo "Error: Failed to add domain"
    exit 1
fi
