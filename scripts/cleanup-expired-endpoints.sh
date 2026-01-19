#!/bin/bash
#
# Cleanup expired endpoint locations from endpoint_locations table
#
# This script removes endpoint location records that have expired.
# Expired entries are automatically filtered out of queries, but remain
# in the database until explicitly deleted.
#
# Usage:
#   sudo ./cleanup-expired-endpoints.sh
#   sudo ./cleanup-expired-endpoints.sh --dry-run  # Show what would be deleted
#   sudo ./cleanup-expired-endpoints.sh --verbose   # Show detailed output
#
# Environment variables:
#   DB_NAME     - Database name (default: opensips)
#   DB_USER     - Database user (default: opensips)
#   DB_PASS     - Database password (default: your-password)
#

set -euo pipefail

# Default values
DB_NAME="${DB_NAME:-opensips}"
DB_USER="${DB_USER:-opensips}"
DB_PASS="${DB_PASS:-your-password}"
DRY_RUN=false
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--dry-run] [--verbose]"
            echo ""
            echo "Options:"
            echo "  --dry-run    Show what would be deleted without actually deleting"
            echo "  --verbose    Show detailed output"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Function to run MySQL query and return result
mysql_query() {
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "$1" 2>/dev/null || echo "ERROR"
}

# Function to run MySQL query with output
mysql_query_output() {
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "$1" 2>/dev/null
}

# Check if endpoint_locations table exists
if ! mysql_query "SHOW TABLES LIKE 'endpoint_locations';" | grep -q "^endpoint_locations$"; then
    echo "Error: endpoint_locations table does not exist"
    echo "Please run init-database.sh to create the table"
    exit 1
fi

# Get count of expired entries
EXPIRED_COUNT=$(mysql_query "SELECT COUNT(*) FROM endpoint_locations WHERE expires < NOW();" || echo "0")

if [ "$EXPIRED_COUNT" = "0" ] || [ "$EXPIRED_COUNT" = "ERROR" ]; then
    if [ "$VERBOSE" = true ]; then
        echo "No expired endpoint locations found"
    fi
    exit 0
fi

echo "Found $EXPIRED_COUNT expired endpoint location(s)"

if [ "$VERBOSE" = true ] || [ "$DRY_RUN" = true ]; then
    echo ""
    echo "Expired entries:"
    echo "--------------------------------"
    mysql_query_output "SELECT 
        aor,
        contact_ip,
        contact_port,
        expires,
        TIMESTAMPDIFF(SECOND, expires, NOW()) as expired_seconds_ago
    FROM endpoint_locations 
    WHERE expires < NOW()
    ORDER BY expires DESC;" | while IFS=$'\t' read -r aor ip port expires expired_ago; do
        echo "  AoR: $aor"
        echo "    IP:Port: $ip:$port"
        echo "    Expired: $expires (${expired_ago}s ago)"
        echo ""
    done
fi

if [ "$DRY_RUN" = true ]; then
    echo "DRY RUN: Would delete $EXPIRED_COUNT expired endpoint location(s)"
    echo "Run without --dry-run to actually delete them"
    exit 0
fi

# Delete expired entries
echo "Deleting expired endpoint locations..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "DELETE FROM endpoint_locations WHERE expires < NOW();" >/dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "Error: Failed to delete expired entries"
    exit 1
fi

# Use the count we found earlier (we verified expired entries exist)
echo "Successfully deleted $EXPIRED_COUNT expired endpoint location(s)"

# Show remaining active entries if verbose
if [ "$VERBOSE" = true ]; then
    ACTIVE_COUNT=$(mysql_query "SELECT COUNT(*) FROM endpoint_locations WHERE expires > NOW();" || echo "0")
    echo "Remaining active endpoint locations: $ACTIVE_COUNT"
fi

exit 0
