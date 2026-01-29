#!/bin/bash
#
# Sync Fail2Ban whitelist from database to config file
# This script reads from the fail2ban_whitelist table and updates the Fail2Ban jail config
#
# Usage:
#   ./sync-fail2ban-whitelist.sh [DB_NAME] [DB_USER] [DB_PASS]
#
# If credentials are not provided as arguments, they are read from environment variables:
#   DB_NAME, DB_USER, DB_PASS
#
# This script is typically called:
# - Via cron (periodic sync) - uses environment variables
# - From admin panel (on-demand sync) - uses command-line arguments
# - After whitelist changes in admin panel
#

set -euo pipefail

# Configuration
JAIL_CONFIG="/etc/fail2ban/jail.d/opensips-brute-force.conf"

# Accept credentials from environment variables or command-line arguments
# Command-line arguments take precedence (more reliable with sudo)
if [[ $# -ge 3 ]]; then
    DB_NAME="$1"
    DB_USER="$2"
    DB_PASS="$3"
else
    # Fallback to environment variables
    DB_NAME="${DB_NAME:-opensips}"
    DB_USER="${DB_USER:-opensips}"
    DB_PASS="${DB_PASS:-}"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if jail config exists
if [[ ! -f "$JAIL_CONFIG" ]]; then
    echo -e "${RED}Error: Jail configuration not found: $JAIL_CONFIG${NC}" >&2
    exit 1
fi

# Check database credentials
if [[ -z "$DB_PASS" ]]; then
    echo -e "${RED}Error: DB_PASS environment variable not set${NC}" >&2
    exit 1
fi

# Get whitelist entries from database
echo "Reading whitelist entries from database..."
IPS=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -sN -e "
    SELECT GROUP_CONCAT(ip_or_cidr SEPARATOR ' ') 
    FROM fail2ban_whitelist 
    ORDER BY created_at;
" 2>/dev/null || echo "")

# Trim whitespace
IPS=$(echo "$IPS" | xargs)

# Create backup
BACKUP_DIR="/etc/fail2ban/jail.d/backups"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="${BACKUP_DIR}/opensips-brute-force.conf.$(date +%Y%m%d_%H%M%S)"
cp "$JAIL_CONFIG" "$BACKUP_FILE"
echo -e "${GREEN}Backup created: $BACKUP_FILE${NC}"

# Remove ALL existing ignoreip lines (including duplicates) to prevent configuration errors
# This ensures we only have one ignoreip line
sed -i '/^ignoreip\s*=/d' "$JAIL_CONFIG"

# Remove any comment lines that were added by previous syncs (lines starting with # followed by IP/CIDR)
sed -i '/^#\s\+[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+/d' "$JAIL_CONFIG"

# Add new ignoreip line in a safe location
# Prefer to add before the Notes section, or after commented ignoreip examples
if grep -q "^# Notes:" "$JAIL_CONFIG"; then
    # Insert before Notes section (most reliable location)
    if [[ -n "$IPS" ]]; then
        sed -i "/^# Notes:/i ignoreip = $IPS" "$JAIL_CONFIG"
    else
        # Empty ignoreip (Fail2ban allows this)
        sed -i "/^# Notes:/i ignoreip =" "$JAIL_CONFIG"
    fi
elif grep -q "^# ignoreip" "$JAIL_CONFIG"; then
    # Insert after the last commented ignoreip example
    # Use awk to find the last occurrence and add after it
    LAST_LINE=$(grep -n "^# ignoreip" "$JAIL_CONFIG" | tail -1 | cut -d: -f1)
    if [[ -n "$LAST_LINE" ]]; then
        if [[ -n "$IPS" ]]; then
            sed -i "${LAST_LINE}a ignoreip = $IPS" "$JAIL_CONFIG"
        else
            sed -i "${LAST_LINE}a ignoreip =" "$JAIL_CONFIG"
        fi
    else
        # Fallback: add at end of file
        if [[ -n "$IPS" ]]; then
            echo "ignoreip = $IPS" >> "$JAIL_CONFIG"
        else
            echo "ignoreip =" >> "$JAIL_CONFIG"
        fi
    fi
else
    # Fallback: add at end of file
    if [[ -n "$IPS" ]]; then
        echo "ignoreip = $IPS" >> "$JAIL_CONFIG"
    else
        echo "ignoreip =" >> "$JAIL_CONFIG"
    fi
fi

# Add comments for each IP (if comments exist in database)
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -sN -e "
    SELECT CONCAT('#   ', ip_or_cidr, ' - ', IFNULL(comment, ''))
    FROM fail2ban_whitelist
    WHERE comment IS NOT NULL AND comment != ''
    ORDER BY created_at;
" 2>/dev/null | while read -r comment_line; do
    if [[ -n "$comment_line" ]]; then
        # Add comment after ignoreip line (if not already present)
        if ! grep -q "$comment_line" "$JAIL_CONFIG"; then
            sed -i "/^ignoreip\s*=.*/a $comment_line" "$JAIL_CONFIG"
        fi
    fi
done

# Restart Fail2Ban to apply changes
echo -e "${YELLOW}Restarting Fail2Ban to apply changes...${NC}"
if systemctl restart fail2ban 2>/dev/null; then
    echo -e "${GREEN}Fail2Ban restarted successfully${NC}"
    echo -e "${GREEN}Whitelist synced: ${IPS:-'(empty)'}${NC}"
else
    echo -e "${RED}Warning: Failed to restart Fail2Ban${NC}" >&2
    echo "Please restart manually: sudo systemctl restart fail2ban" >&2
    exit 1
fi
