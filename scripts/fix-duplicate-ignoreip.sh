#!/bin/bash
#
# Fix duplicate ignoreip entries in Fail2ban config
# This script removes ALL ignoreip lines and adds a single clean one
#
# Usage:
#   sudo ./fix-duplicate-ignoreip.sh
#

set -euo pipefail

JAIL_CONFIG="/etc/fail2ban/jail.d/opensips-brute-force.conf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root (use sudo)${NC}" >&2
   exit 1
fi

# Check if config file exists
if [[ ! -f "$JAIL_CONFIG" ]]; then
    echo -e "${RED}Error: Config file not found: $JAIL_CONFIG${NC}" >&2
    exit 1
fi

echo -e "${YELLOW}Checking for duplicate ignoreip entries...${NC}"

# Show current ignoreip lines
echo -e "${YELLOW}Current ignoreip lines:${NC}"
grep -n "ignoreip" "$JAIL_CONFIG" || echo "  (none found)"

# Create backup
BACKUP_FILE="${JAIL_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$JAIL_CONFIG" "$BACKUP_FILE"
echo -e "${GREEN}Backup created: $BACKUP_FILE${NC}"

# Remove ALL ignoreip lines (including variations with whitespace)
# This removes:
# - ignoreip = ...
# - ignoreip=...
# - ignoreip = (empty)
# - Lines with leading/trailing whitespace
sed -i '/^[[:space:]]*ignoreip[[:space:]]*=/d' "$JAIL_CONFIG"

# Remove comment lines that were added by sync script (lines starting with # followed by IP)
sed -i '/^[[:space:]]*#[[:space:]]*[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+/d' "$JAIL_CONFIG"

echo -e "${GREEN}Removed all ignoreip entries${NC}"

# Check if we have whitelist entries in database (optional - only if DB credentials available)
IPS=""
if [[ -n "${DB_PASS:-}" ]] && [[ -n "${DB_USER:-opensips}" ]] && [[ -n "${DB_NAME:-opensips}" ]]; then
    echo -e "${YELLOW}Checking database for whitelist entries...${NC}"
    IPS=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -sN -e "
        SELECT GROUP_CONCAT(ip_or_cidr SEPARATOR ' ') 
        FROM fail2ban_whitelist 
        ORDER BY created_at;
    " 2>/dev/null || echo "")
    IPS=$(echo "$IPS" | xargs)
fi

# Add single ignoreip line before Notes section
if grep -q "^# Notes:" "$JAIL_CONFIG"; then
    if [[ -n "$IPS" ]]; then
        sed -i "/^# Notes:/i ignoreip = $IPS" "$JAIL_CONFIG"
        echo -e "${GREEN}Added ignoreip = $IPS${NC}"
    else
        sed -i "/^# Notes:/i ignoreip =" "$JAIL_CONFIG"
        echo -e "${GREEN}Added empty ignoreip line${NC}"
    fi
else
    # Fallback: add at end of [opensips-brute-force] section
    if [[ -n "$IPS" ]]; then
        echo "ignoreip = $IPS" >> "$JAIL_CONFIG"
        echo -e "${GREEN}Added ignoreip = $IPS at end of section${NC}"
    else
        echo "ignoreip =" >> "$JAIL_CONFIG"
        echo -e "${GREEN}Added empty ignoreip line at end of section${NC}"
    fi
fi

# Verify only one ignoreip line exists
IGNOREIP_COUNT=$(grep -c "^[[:space:]]*ignoreip[[:space:]]*=" "$JAIL_CONFIG" || echo "0")
if [[ "$IGNOREIP_COUNT" -eq 1 ]]; then
    echo -e "${GREEN}✓ Verified: Only one ignoreip line exists${NC}"
    echo -e "${YELLOW}Final ignoreip line:${NC}"
    grep "^[[:space:]]*ignoreip[[:space:]]*=" "$JAIL_CONFIG"
else
    echo -e "${RED}Error: Found $IGNOREIP_COUNT ignoreip lines (expected 1)${NC}" >&2
    echo -e "${YELLOW}All ignoreip lines:${NC}"
    grep -n "^[[:space:]]*ignoreip[[:space:]]*=" "$JAIL_CONFIG"
    exit 1
fi

# Test Fail2ban configuration
echo -e "${YELLOW}Testing Fail2ban configuration...${NC}"
if sudo fail2ban-client -t 2>&1 | grep -q "OK"; then
    echo -e "${GREEN}✓ Configuration test passed${NC}"
    echo ""
    echo -e "${GREEN}You can now start Fail2ban:${NC}"
    echo -e "  ${GREEN}sudo systemctl start fail2ban${NC}"
else
    echo -e "${RED}Configuration test failed. Check output above.${NC}" >&2
    echo -e "${YELLOW}Restore backup with:${NC}"
    echo -e "  ${YELLOW}sudo cp $BACKUP_FILE $JAIL_CONFIG${NC}"
    exit 1
fi
