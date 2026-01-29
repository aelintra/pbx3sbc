#!/bin/bash
#
# Setup sudoers configuration for pbx3sbc-admin panel
# This allows www-data to run fail2ban-client commands without password
#
# Usage:
#   sudo ./setup-admin-panel-sudoers.sh
#

set -euo pipefail

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

SUDOERS_FILE="/etc/sudoers.d/pbx3sbc-admin"

# Detect sync script path
SYNC_SCRIPT_PATH=""
if [[ -f "/home/ubuntu/pbx3sbc/scripts/sync-fail2ban-whitelist.sh" ]]; then
    SYNC_SCRIPT_PATH="/home/ubuntu/pbx3sbc/scripts/sync-fail2ban-whitelist.sh"
elif [[ -f "/opt/pbx3sbc/scripts/sync-fail2ban-whitelist.sh" ]]; then
    SYNC_SCRIPT_PATH="/opt/pbx3sbc/scripts/sync-fail2ban-whitelist.sh"
elif [[ -f "/usr/local/pbx3sbc/scripts/sync-fail2ban-whitelist.sh" ]]; then
    SYNC_SCRIPT_PATH="/usr/local/pbx3sbc/scripts/sync-fail2ban-whitelist.sh"
else
    # Try to find it
    SYNC_SCRIPT_PATH=$(find /home /opt /usr/local -name "sync-fail2ban-whitelist.sh" 2>/dev/null | head -1)
    if [[ -z "$SYNC_SCRIPT_PATH" ]]; then
        echo -e "${YELLOW}Warning: Could not find sync-fail2ban-whitelist.sh${NC}"
        echo -e "${YELLOW}You may need to update the sudoers file manually with the correct path${NC}"
        SYNC_SCRIPT_PATH="/home/*/pbx3sbc/scripts/sync-fail2ban-whitelist.sh"
    fi
fi

echo -e "${GREEN}Setting up sudoers configuration for pbx3sbc-admin...${NC}"
echo ""

# Create sudoers file
cat > "$SUDOERS_FILE" <<EOF
# Sudoers configuration for pbx3sbc-admin panel
# Allows www-data user to run Fail2ban management commands without password

# Fail2ban status and management commands
www-data ALL=(ALL) NOPASSWD: /usr/bin/fail2ban-client status opensips-brute-force
www-data ALL=(ALL) NOPASSWD: /usr/bin/fail2ban-client set opensips-brute-force banip *
www-data ALL=(ALL) NOPASSWD: /usr/bin/fail2ban-client set opensips-brute-force unbanip *
www-data ALL=(ALL) NOPASSWD: /usr/bin/fail2ban-client set opensips-brute-force unban --all

# Whitelist sync script
www-data ALL=(ALL) NOPASSWD: $SYNC_SCRIPT_PATH
EOF

# Set correct permissions (sudoers files must be 0440)
chmod 0440 "$SUDOERS_FILE"

# Validate sudoers syntax
if visudo -c -f "$SUDOERS_FILE" 2>/dev/null; then
    echo -e "${GREEN}✓ Sudoers file created successfully: $SUDOERS_FILE${NC}"
    echo ""
    echo -e "${GREEN}Configuration:${NC}"
    cat "$SUDOERS_FILE"
    echo ""
    echo -e "${GREEN}✓ Sudoers syntax validated${NC}"
    echo ""
    echo -e "${YELLOW}Note: The changes take effect immediately.${NC}"
    echo -e "${YELLOW}You may need to restart your web server for www-data to pick up the changes:${NC}"
    echo -e "  ${GREEN}sudo systemctl restart php*-fpm${NC}  # For PHP-FPM"
    echo -e "  ${GREEN}sudo systemctl restart apache2${NC}   # For Apache"
    echo -e "  ${GREEN}sudo systemctl restart nginx${NC}      # For Nginx (if using PHP-FPM)"
else
    echo -e "${RED}Error: Sudoers syntax validation failed${NC}" >&2
    echo -e "${RED}Removing invalid file...${NC}" >&2
    rm -f "$SUDOERS_FILE"
    exit 1
fi
