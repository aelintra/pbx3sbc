#!/bin/bash
#
# View status of Kamailio and Litestream services
#

DB_PATH="${DB_PATH:-/var/lib/kamailio/routing.db}"

echo "=== Kamailio SIP Edge Router Status ==="
echo

# Kamailio status
echo "Kamailio Service:"
if systemctl is-active --quiet kamailio 2>/dev/null; then
    echo "  Status: Running"
    echo "  Version: $(kamailio -V 2>&1 | head -n1)"
else
    echo "  Status: Not running"
fi
echo

# Litestream status
echo "Litestream Service:"
if systemctl is-active --quiet litestream 2>/dev/null; then
    echo "  Status: Running"
    echo "  Version: $(litestream version 2>/dev/null | head -n1 || echo 'Unknown')"
    echo
    echo "  Replication Status:"
    litestream databases 2>/dev/null || echo "    (Check logs if replication not working)"
else
    echo "  Status: Not running"
fi
echo

# Database status
echo "Database:"
if [[ -f "$DB_PATH" ]]; then
    echo "  Path: $DB_PATH"
    echo "  Size: $(du -h "$DB_PATH" | cut -f1)"
    echo "  Integrity: $(sqlite3 "$DB_PATH" "PRAGMA integrity_check;" 2>/dev/null || echo 'Check failed')"
    echo
    echo "  Domains: $(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sip_domains WHERE enabled=1;" 2>/dev/null || echo '0')"
    echo "  Dispatcher entries: $(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM dispatcher;" 2>/dev/null || echo '0')"
else
    echo "  Database not found"
fi
echo

# Recent logs
echo "Recent Logs (last 5 lines):"
echo "  Kamailio:"
journalctl -u kamailio -n 5 --no-pager 2>/dev/null | sed 's/^/    /' || echo "    (No logs)"
echo
echo "  Litestream:"
journalctl -u litestream -n 5 --no-pager 2>/dev/null | sed 's/^/    /' || echo "    (No logs)"
