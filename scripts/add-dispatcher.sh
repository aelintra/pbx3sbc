#!/bin/bash
#
# Add a dispatcher destination to the routing database
# OpenSIPS 3.6 version 9 schema
#

set -euo pipefail

DB_PATH="${DB_PATH:-/var/lib/opensips/routing.db}"

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <setid> <destination> [priority] [weight] [socket] [description]"
    echo
    echo "Example:"
    echo "  $0 10 sip:10.0.1.10:5060"
    echo "  $0 10 sip:10.0.1.10:5060 0 '1' 'udp:192.168.1.1:5060' 'Primary Asterisk'"
    exit 1
fi

SETID="$1"
DESTINATION="$2"
PRIORITY="${3:-0}"
WEIGHT="${4:-1}"
SOCKET="${5:-}"
DESCRIPTION="${6:-}"

# Validate destination format (basic SIP URI check)
if [[ ! "$DESTINATION" =~ ^sip: ]]; then
    echo "Error: Destination must be a SIP URI (sip:host:port)"
    exit 1
fi

# Insert dispatcher entry (OpenSIPS 3.6 version 9 schema)
# Column order: setid, destination, socket, state, probe_mode, weight, priority, attrs, description
# Build SQL with optional parameters (socket, description are nullable)
SQL="INSERT INTO dispatcher (setid, destination, state, probe_mode, weight, priority"
VALUES="$SETID, '$DESTINATION', 0, 0, '$WEIGHT', $PRIORITY"

if [[ -n "$SOCKET" ]]; then
    SQL="$SQL, socket"
    VALUES="$VALUES, '$SOCKET'"
fi

if [[ -n "$DESCRIPTION" ]]; then
    SQL="$SQL, description"
    VALUES="$VALUES, '$DESCRIPTION'"
fi

SQL="$SQL) VALUES ($VALUES);"

sqlite3 "$DB_PATH" "$SQL"

if [[ $? -eq 0 ]]; then
    echo "Dispatcher added: setid $SETID -> $DESTINATION"
else
    echo "Error: Failed to add dispatcher"
    exit 1
fi
