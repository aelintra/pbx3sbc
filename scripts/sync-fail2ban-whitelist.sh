#!/bin/bash
#
# Sync Fail2Ban whitelist from database to config file
# This script reads from the fail2ban_whitelist table and updates the Fail2Ban jail config
#
# Usage:
#   ./sync-fail2ban-whitelist.sh
#
# This script is typically called:
# - Via cron (periodic sync)
# - From admin panel (on-demand sync)
# - After whitelist changes in admin panel
#

set -euo pipefail

# Configuration
JAIL_CONFIG="/etc/fail2ban/jail.d/opensips-brute-force.conf"
DB_NAME="${DB_NAME:-opensips}"
DB_USER="${DB_USER:-opensips}"
DB_PASS="${DB_PASS:-}"

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

# Update ignoreip line in config
if grep -q "^ignoreip\s*=" "$JAIL_CONFIG"; then
    # Replace existing ignoreip line
    sed -i "s|^ignoreip\s*=.*|ignoreip = $IPS|" "$JAIL_CONFIG"
else
    # Add new ignoreip line
    if grep -q "^# ignoreip" "$JAIL_CONFIG"; then
        # Add after commented ignoreip line
        sed -i "/^# ignoreip/a ignoreip = $IPS" "$JAIL_CONFIG"
    else
        # Add before Notes section
        sed -i "/^# Notes:/i ignoreip = $IPS" "$JAIL_CONFIG"
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
