#!/bin/bash
#
# Add a domain to the routing database
#

set -euo pipefail

DB_PATH="${DB_PATH:-/var/lib/kamailio/routing.db}"

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <domain> <dispatcher_setid> [enabled] [comment]"
    echo
    echo "Example:"
    echo "  $0 example.com 10 1 'Example tenant'"
    exit 1
fi

DOMAIN="$1"
SETID="$2"
ENABLED="${3:-1}"
COMMENT="${4:-}"

# Validate domain format (basic check)
if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.-]*[a-zA-Z0-9]$ ]]; then
    echo "Error: Invalid domain format: $DOMAIN"
    exit 1
fi

# Insert domain
sqlite3 "$DB_PATH" <<EOF
INSERT OR REPLACE INTO sip_domains (domain, dispatcher_setid, enabled, comment)
VALUES ('$DOMAIN', $SETID, $ENABLED, '$COMMENT');
EOF

if [[ $? -eq 0 ]]; then
    echo "Domain added: $DOMAIN -> setid $SETID"
else
    echo "Error: Failed to add domain"
    exit 1
fi
