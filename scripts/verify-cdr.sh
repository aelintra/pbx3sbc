#!/bin/bash
#
# CDR Verification Script
# Verifies that CDR accounting is working correctly
#

set -euo pipefail

DB_NAME="${DB_NAME:-opensips}"
DB_USER="${DB_USER:-opensips}"
DB_PASS="${DB_PASS:-your-password}"

echo "=========================================="
echo "CDR Verification Test"
echo "=========================================="
echo

# Function to run MySQL query
mysql_query() {
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "$1" 2>/dev/null || echo "ERROR"
}

# Function to check if table exists
table_exists() {
    local table=$1
    mysql_query "SHOW TABLES LIKE '$table';" | grep -q "^$table$"
}

# Function to check if column exists
column_exists() {
    local table=$1
    local column=$2
    mysql_query "SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS 
                 WHERE TABLE_SCHEMA = DATABASE() 
                 AND TABLE_NAME = '$table' 
                 AND COLUMN_NAME = '$column';" | grep -q "^1$"
}

echo "1. Checking database schema..."
echo "--------------------------------"

# Check acc table exists
if table_exists "acc"; then
    echo "  ✓ acc table exists"
else
    echo "  ✗ acc table does NOT exist - run init-database.sh"
    exit 1
fi

# Check dialog table exists
if table_exists "dialog"; then
    echo "  ✓ dialog table exists"
else
    echo "  ✗ dialog table does NOT exist - run init-database.sh"
    exit 1
fi

# Check from_uri column
if column_exists "acc" "from_uri"; then
    echo "  ✓ from_uri column exists in acc table"
else
    echo "  ✗ from_uri column does NOT exist - run init-database.sh or add-acc-columns.sql"
    exit 1
fi

# Check to_uri column
if column_exists "acc" "to_uri"; then
    echo "  ✓ to_uri column exists in acc table"
else
    echo "  ✗ to_uri column does NOT exist - run init-database.sh or add-acc-columns.sql"
    exit 1
fi

echo
echo "2. Checking recent CDR records..."
echo "--------------------------------"

# Get count of records
RECORD_COUNT=$(mysql_query "SELECT COUNT(*) FROM acc;" || echo "0")
echo "  Total records in acc table: $RECORD_COUNT"

if [ "$RECORD_COUNT" -eq "0" ]; then
    echo "  ⚠ No records found - make a test call first"
    echo
    echo "3. Next steps:"
    echo "   - Make a test call (e.g., from 1001 to 1000)"
    echo "   - Wait for call to complete (hang up)"
    echo "   - Run this script again to verify CDR data"
    exit 0
fi

# Get the most recent record
echo
echo "  Most recent CDR record:"
echo "  ----------------------"
mysql_query "SELECT 
    id,
    method,
    callid,
    sip_code,
    from_uri,
    to_uri,
    duration,
    ms_duration,
    created,
    time
FROM acc 
ORDER BY id DESC 
LIMIT 1;" | while IFS=$'\t' read -r id method callid sip_code from_uri to_uri duration ms_duration created time; do
    echo "    ID: $id"
    echo "    Method: $method"
    echo "    Call-ID: $callid"
    echo "    SIP Code: $sip_code"
    echo "    From URI: ${from_uri:-<NULL>}"
    echo "    To URI: ${to_uri:-<NULL>}"
    echo "    Duration: ${duration:-0} seconds"
    echo "    Duration (ms): ${ms_duration:-0} milliseconds"
    echo "    Created: ${created:-<NULL>}"
    echo "    Time: ${time:-<NULL>}"
done

echo
echo "3. Verifying CDR data quality..."
echo "--------------------------------"

# Check for records with from_uri populated
FROM_URI_COUNT=$(mysql_query "SELECT COUNT(*) FROM acc WHERE from_uri IS NOT NULL AND from_uri != '';" || echo "0")
echo "  Records with from_uri: $FROM_URI_COUNT / $RECORD_COUNT"

# Check for records with to_uri populated
TO_URI_COUNT=$(mysql_query "SELECT COUNT(*) FROM acc WHERE to_uri IS NOT NULL AND to_uri != '';" || echo "0")
echo "  Records with to_uri: $TO_URI_COUNT / $RECORD_COUNT"

# Check for records with duration > 0
DURATION_COUNT=$(mysql_query "SELECT COUNT(*) FROM acc WHERE duration > 0;" || echo "0")
echo "  Records with duration > 0: $DURATION_COUNT / $RECORD_COUNT"

# Check for records with created timestamp
CREATED_COUNT=$(mysql_query "SELECT COUNT(*) FROM acc WHERE created IS NOT NULL AND created != '0000-00-00 00:00:00';" || echo "0")
echo "  Records with valid created timestamp: $CREATED_COUNT / $RECORD_COUNT"

# Check for duplicate records (same callid, multiple rows)
DUPLICATE_CALLIDS=$(mysql_query "SELECT callid, COUNT(*) as cnt FROM acc GROUP BY callid HAVING cnt > 1;" || echo "")
if [ -n "$DUPLICATE_CALLIDS" ]; then
    echo "  ⚠ Found duplicate Call-IDs (multiple rows per call):"
    echo "$DUPLICATE_CALLIDS" | while IFS=$'\t' read -r callid cnt; do
        echo "    Call-ID: $callid - $cnt rows"
    done
else
    echo "  ✓ No duplicate Call-IDs found (CDR mode working correctly)"
fi

echo
echo "4. Checking dialog table..."
echo "--------------------------------"

DIALOG_COUNT=$(mysql_query "SELECT COUNT(*) FROM dialog;" || echo "0")
echo "  Total records in dialog table: $DIALOG_COUNT"

if [ "$DIALOG_COUNT" -eq "0" ]; then
    echo "  ⚠ Dialog table is empty"
    echo "     Note: With db_mode=2, dialogs may be cached in memory"
    echo "     This is normal behavior, but dialogs should still be written to DB"
else
    echo "  ✓ Dialog table has records"
    echo
    echo "  Most recent dialog:"
    mysql_query "SELECT 
        dlg_id,
        callid,
        from_uri,
        to_uri,
        state,
        created,
        modified
    FROM dialog 
    ORDER BY created DESC 
    LIMIT 1;" | while IFS=$'\t' read -r dlg_id callid from_uri to_uri state created modified; do
        echo "    Dialog ID: $dlg_id"
        echo "    Call-ID: $callid"
        echo "    From URI: ${from_uri:-<NULL>}"
        echo "    To URI: ${to_uri:-<NULL>}"
        echo "    State: ${state:-<NULL>}"
        echo "    Created: ${created:-<NULL>}"
        echo "    Modified: ${modified:-<NULL>}"
    done
fi

echo
echo "5. Testing both routing paths..."
echo "--------------------------------"
echo "  To verify accounting works for both paths:"
echo "    1. Domain routing: Make call using domain (e.g., sip:1001@example.com)"
echo "    2. Endpoint routing: Make call using IP (e.g., sip:1001@192.168.1.100)"
echo "    3. Check that both create CDR records with from_uri/to_uri populated"

echo
echo "=========================================="
echo "Verification Complete"
echo "=========================================="
echo
echo "Summary:"
echo "  - Schema: $(if table_exists "acc" && column_exists "acc" "from_uri" && column_exists "acc" "to_uri"; then echo "✓ OK"; else echo "✗ Issues found"; fi)"
echo "  - CDR Records: $RECORD_COUNT"
echo "  - From/To URIs: $FROM_URI_COUNT / $TO_URI_COUNT records populated"
echo "  - Duration: $DURATION_COUNT records with duration > 0"
echo "  - Dialog Table: $DIALOG_COUNT records"
