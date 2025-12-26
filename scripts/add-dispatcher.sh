#!/bin/bash
#
# Add a dispatcher destination to the routing database
#

set -euo pipefail

DB_PATH="${DB_PATH:-/var/lib/opensips/routing.db}"

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <setid> <destination> [flags] [priority]"
    echo
    echo "Example:"
    echo "  $0 10 sip:10.0.1.10:5060 0 0"
    exit 1
fi

SETID="$1"
DESTINATION="$2"
FLAGS="${3:-0}"
PRIORITY="${4:-0}"

# Validate destination format (basic SIP URI check)
if [[ ! "$DESTINATION" =~ ^sip: ]]; then
    echo "Error: Destination must be a SIP URI (sip:host:port)"
    exit 1
fi

# Insert dispatcher entry
sqlite3 "$DB_PATH" <<EOF
INSERT INTO dispatcher (setid, destination, flags, priority)
VALUES ($SETID, '$DESTINATION', $FLAGS, $PRIORITY);
EOF

if [[ $? -eq 0 ]]; then
    echo "Dispatcher added: setid $SETID -> $DESTINATION"
else
    echo "Error: Failed to add dispatcher"
    exit 1
fi
