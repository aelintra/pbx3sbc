#!/bin/bash
#
# Diagnostic script to check failed registrations logging
# Checks database, OpenSIPS logs, and configuration
#

set -euo pipefail

# Load database credentials if available
if [[ -f /etc/opensips/.mysql_credentials ]]; then
    source /etc/opensips/.mysql_credentials
fi

DB_NAME="${DB_NAME:-opensips}"
DB_USER="${DB_USER:-opensips}"
DB_PASS="${DB_PASS:-your-password}"

echo "=== Failed Registrations Diagnostic ==="
echo

# Check database table
echo "1. Checking database table..."
TOTAL_COUNT=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -sN -e "SELECT COUNT(*) FROM failed_registrations;" 2>/dev/null || echo "0")
echo "   Total records in failed_registrations table: $TOTAL_COUNT"

if [[ "$TOTAL_COUNT" -gt 0 ]]; then
    echo "   Recent entries:"
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT id, username, domain, source_ip, response_code, attempt_time FROM failed_registrations ORDER BY attempt_time DESC LIMIT 5;" 2>/dev/null || echo "   Error querying table"
    
    echo
    echo "   Response code breakdown:"
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT response_code, COUNT(*) as count FROM failed_registrations GROUP BY response_code ORDER BY count DESC;" 2>/dev/null || echo "   Error querying table"
else
    echo "   ⚠ No records found in failed_registrations table"
fi

echo
echo "2. Checking OpenSIPS logs for failed registration logging..."
RECENT_LOGS=$(sudo journalctl -u opensips --since "1 hour ago" 2>/dev/null | grep -i "failed registration\|REGISTER.*Failed" | tail -10 || echo "")
if [[ -n "$RECENT_LOGS" ]]; then
    echo "   Recent failed registration log entries:"
    echo "$RECENT_LOGS" | head -5
else
    echo "   No recent failed registration log entries found"
fi

echo
echo "3. Checking for SQL query errors..."
SQL_ERRORS=$(sudo journalctl -u opensips --since "1 hour ago" 2>/dev/null | grep -i "failed to log\|sql.*fail\|database.*error" | tail -5 || echo "")
if [[ -n "$SQL_ERRORS" ]]; then
    echo "   ⚠ SQL errors found:"
    echo "$SQL_ERRORS"
else
    echo "   ✓ No SQL errors found"
fi

echo
echo "4. Checking OpenSIPS configuration..."
if [[ -f /etc/opensips/opensips.cfg ]]; then
    if grep -q "INSERT INTO failed_registrations" /etc/opensips/opensips.cfg; then
        echo "   ✓ Failed registration logging is configured"
        # Check if 401 is being skipped
        if grep -q "if (\$rs == 401)" /etc/opensips/opensips.cfg; then
            echo "   ℹ 401 responses are skipped (normal auth challenge)"
        fi
    else
        echo "   ⚠ Failed registration logging not found in config"
    fi
else
    echo "   ⚠ OpenSIPS config not found at /etc/opensips/opensips.cfg"
fi

echo
echo "5. Checking door_knock_attempts table..."
DOOR_KNOCK_COUNT=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -sN -e "SELECT COUNT(*) FROM door_knock_attempts;" 2>/dev/null || echo "0")
echo "   Total records in door_knock_attempts table: $DOOR_KNOCK_COUNT"

if [[ "$DOOR_KNOCK_COUNT" -gt 0 ]]; then
    echo "   Recent entries:"
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT id, domain, source_ip, method, reason, attempt_time FROM door_knock_attempts ORDER BY attempt_time DESC LIMIT 5;" 2>/dev/null || echo "   Error querying table"
    
    echo
    echo "   Reason breakdown:"
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT reason, COUNT(*) as count FROM door_knock_attempts GROUP BY reason ORDER BY count DESC;" 2>/dev/null || echo "   Error querying table"
else
    echo "   ⚠ No records found in door_knock_attempts table"
fi

echo
echo "6. Checking OpenSIPS logs for door-knock logging..."
DOOR_KNOCK_LOGS=$(sudo journalctl -u opensips --since "1 hour ago" 2>/dev/null | grep -i "door-knock\|Door-knock" | tail -10 || echo "")
if [[ -n "$DOOR_KNOCK_LOGS" ]]; then
    echo "   Recent door-knock log entries:"
    echo "$DOOR_KNOCK_LOGS" | head -5
else
    echo "   No recent door-knock log entries found"
fi

echo
echo "=== Diagnostic Complete ==="
echo
echo "Note: OpenSIPS only logs:"
echo "  - 403 Forbidden and other 4xx/5xx failures"
echo "  - 401 Unauthorized is NOT logged (normal auth challenge)"
echo
echo "Door-knock attempts are logged for:"
echo "  - Unknown domains (domain_not_found)"
echo "  - Domain mismatches (domain_mismatch)"
echo "  - Scanner detection (scanner_detected)"
echo "  - Method not allowed (method_not_allowed)"
echo "  - Max forwards exceeded (max_forwards_exceeded)"
echo
echo "If you're seeing 401s in logs, they won't appear in the admin panel."
