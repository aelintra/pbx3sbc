#!/bin/bash
#
# Restore database from Litestream backup
#

set -euo pipefail

DB_PATH="${DB_PATH:-/var/lib/opensips/routing.db}"
LITESTREAM_CONFIG="${LITESTREAM_CONFIG:-/etc/litestream.yml}"
TIMESTAMP="${1:-}"

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

echo "Restoring database from Litestream backup..."

# Stop services
echo "Stopping services..."
systemctl stop opensips
systemctl stop litestream

# Backup current database
if [[ -f "$DB_PATH" ]]; then
    BACKUP="${DB_PATH}.pre-restore.$(date +%Y%m%d_%H%M%S)"
    echo "Backing up current database to ${BACKUP}..."
    cp "$DB_PATH" "$BACKUP"
    rm -f "${DB_PATH}-wal" "${DB_PATH}-shm"
fi

# Restore
if [[ -n "$TIMESTAMP" ]]; then
    echo "Restoring to timestamp: $TIMESTAMP"
    litestream restore -timestamp "$TIMESTAMP" "$DB_PATH"
else
    echo "Restoring to latest..."
    litestream restore "$DB_PATH"
fi

if [[ $? -eq 0 ]]; then
    echo "Database restored successfully!"
    
    # Set permissions
    chown opensips:opensips "$DB_PATH"
    chmod 644 "$DB_PATH"
    
    # Start services
    echo "Starting services..."
    systemctl start litestream
    sleep 2
    systemctl start opensips
    
    echo "Restore complete!"
else
    echo "Error: Restore failed"
    exit 1
fi
