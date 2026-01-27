#!/bin/bash
#
# Manage Fail2ban whitelist (ignoreip) for OpenSIPS brute force detection
# Adds/removes IP addresses and CIDR ranges from the Fail2ban jail whitelist
#
# Usage:
#   ./manage-fail2ban-whitelist.sh add <IP_or_CIDR> [comment]
#   ./manage-fail2ban-whitelist.sh remove <IP_or_CIDR>
#   ./manage-fail2ban-whitelist.sh list
#   ./manage-fail2ban-whitelist.sh show
#
# Examples:
#   ./manage-fail2ban-whitelist.sh add 203.0.113.50 "Customer A office"
#   ./manage-fail2ban-whitelist.sh add 198.51.100.0/24 "Customer B network"
#   ./manage-fail2ban-whitelist.sh remove 203.0.113.50
#   ./manage-fail2ban-whitelist.sh list
#

set -euo pipefail

JAIL_CONFIG="/etc/fail2ban/jail.d/opensips-brute-force.conf"
BACKUP_DIR="/etc/fail2ban/jail.d/backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validate IP or CIDR format
validate_ip_or_cidr() {
    local ip="$1"
    
    # Check if it's a valid IP or CIDR
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
        # Validate IP components
        IFS='/' read -r ip_part cidr_part <<< "$ip"
        IFS='.' read -r a b c d <<< "$ip_part"
        
        if [[ $a -le 255 && $b -le 255 && $c -le 255 && $d -le 255 ]]; then
            if [[ -n "$cidr_part" ]]; then
                if [[ $cidr_part -ge 0 && $cidr_part -le 32 ]]; then
                    return 0
                fi
            else
                return 0
            fi
        fi
    fi
    
    # Check IPv6 (basic validation)
    if [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}(/[0-9]{1,3})?$ ]] || [[ "$ip" == "::1" ]]; then
        return 0
    fi
    
    echo -e "${RED}Error: Invalid IP or CIDR format: $ip${NC}" >&2
    echo "Valid formats:" >&2
    echo "  - IPv4: 192.168.1.100" >&2
    echo "  - IPv4 CIDR: 192.168.1.0/24" >&2
    echo "  - IPv6: 2001:db8::1" >&2
    echo "  - IPv6 CIDR: 2001:db8::/32" >&2
    return 1
}

# Check if jail config exists
if [[ ! -f "$JAIL_CONFIG" ]]; then
    echo -e "${RED}Error: Jail configuration not found: $JAIL_CONFIG${NC}" >&2
    echo "Please install Fail2ban configuration first:" >&2
    echo "  sudo cp config/fail2ban/opensips-brute-force.conf /etc/fail2ban/jail.d/" >&2
    exit 1
fi

# Create backup before making changes
create_backup() {
    mkdir -p "$BACKUP_DIR"
    local backup_file="${BACKUP_DIR}/opensips-brute-force.conf.$(date +%Y%m%d_%H%M%S)"
    cp "$JAIL_CONFIG" "$backup_file"
    echo -e "${GREEN}Backup created: $backup_file${NC}"
}

# Extract current ignoreip values
get_current_whitelist() {
    # Extract ignoreip line, remove comments, and get the value
    grep -E "^ignoreip\s*=" "$JAIL_CONFIG" | head -1 | sed 's/^ignoreip\s*=\s*//' | sed 's/#.*$//' | xargs
}

# Add IP to whitelist
add_to_whitelist() {
    local ip="$1"
    local comment="${2:-}"
    
    validate_ip_or_cidr "$ip" || return 1
    
    # Get current whitelist
    local current=$(get_current_whitelist)
    
    # Check if already whitelisted
    if echo "$current" | grep -qE "(^|[[:space:]])${ip}([[:space:]]|$)"; then
        echo -e "${YELLOW}IP $ip is already whitelisted${NC}"
        return 0
    fi
    
    create_backup
    
    # Add IP to whitelist
    if [[ -z "$current" ]]; then
        # No existing ignoreip line, add new one
        # Find the line with "# ignoreip" comment and add after it
        if grep -q "^# ignoreip" "$JAIL_CONFIG"; then
            # Add after the commented ignoreip line
            sed -i "/^# ignoreip/a ignoreip = $ip" "$JAIL_CONFIG"
        else
            # Add before the Notes section
            sed -i "/^# Notes:/i ignoreip = $ip" "$JAIL_CONFIG"
        fi
    else
        # Append to existing ignoreip line
        sed -i "s/^ignoreip\s*=.*/& $ip/" "$JAIL_CONFIG"
    fi
    
    # Add comment if provided
    if [[ -n "$comment" ]]; then
        # Add comment on the line after ignoreip
        sed -i "/^ignoreip\s*=.*/a #   $ip - $comment" "$JAIL_CONFIG"
    fi
    
    echo -e "${GREEN}Added $ip to whitelist${NC}"
    if [[ -n "$comment" ]]; then
        echo "  Comment: $comment"
    fi
    
    # Restart Fail2ban to apply changes
    echo -e "${YELLOW}Restarting Fail2ban to apply changes...${NC}"
    systemctl restart fail2ban 2>/dev/null || {
        echo -e "${YELLOW}Warning: Could not restart Fail2ban automatically${NC}"
        echo "Please restart manually: sudo systemctl restart fail2ban"
    }
}

# Remove IP from whitelist
remove_from_whitelist() {
    local ip="$1"
    
    validate_ip_or_cidr "$ip" || return 1
    
    # Get current whitelist
    local current=$(get_current_whitelist)
    
    # Check if whitelisted
    if ! echo "$current" | grep -qE "(^|[[:space:]])${ip}([[:space:]]|$)"; then
        echo -e "${YELLOW}IP $ip is not in whitelist${NC}"
        return 0
    fi
    
    create_backup
    
    # Remove IP from whitelist (handle both with and without surrounding spaces)
    local new_list=$(echo "$current" | sed -E "s/(^|[[:space:]])${ip}([[:space:]]|$)/ /g" | xargs)
    
    # Update ignoreip line
    if [[ -z "$new_list" ]]; then
        # No IPs left, comment out the line
        sed -i "s/^ignoreip\s*=.*/# ignoreip = /" "$JAIL_CONFIG"
    else
        # Update with remaining IPs
        sed -i "s/^ignoreip\s*=.*/ignoreip = $new_list/" "$JAIL_CONFIG"
    fi
    
    # Remove associated comment line if exists
    sed -i "/#.*$ip.*-/d" "$JAIL_CONFIG"
    
    echo -e "${GREEN}Removed $ip from whitelist${NC}"
    
    # Restart Fail2ban to apply changes
    echo -e "${YELLOW}Restarting Fail2ban to apply changes...${NC}"
    systemctl restart fail2ban 2>/dev/null || {
        echo -e "${YELLOW}Warning: Could not restart Fail2ban automatically${NC}"
        echo "Please restart manually: sudo systemctl restart fail2ban"
    }
}

# List whitelisted IPs
list_whitelist() {
    local current=$(get_current_whitelist)
    
    if [[ -z "$current" ]]; then
        echo -e "${YELLOW}No IPs currently whitelisted${NC}"
        return 0
    fi
    
    echo -e "${GREEN}Whitelisted IPs and ranges:${NC}"
    echo "$current" | tr ' ' '\n' | while read -r ip; do
        [[ -n "$ip" ]] && echo "  - $ip"
    done
    
    # Show comments if any
    if grep -qE "^#.*-.*" "$JAIL_CONFIG"; then
        echo
        echo -e "${GREEN}Comments:${NC}"
        grep -E "^#.*-.*" "$JAIL_CONFIG" | sed 's/^#/  /'
    fi
}

# Show current configuration
show_config() {
    echo -e "${GREEN}Current Fail2ban whitelist configuration:${NC}"
    echo
    grep -A 20 "^# Whitelist" "$JAIL_CONFIG" | head -25
    echo
    echo -e "${GREEN}Active whitelist:${NC}"
    list_whitelist
}

# Main script logic
case "${1:-}" in
    add)
        if [[ $# -lt 2 ]]; then
            echo "Usage: $0 add <IP_or_CIDR> [comment]"
            echo "Example: $0 add 203.0.113.50 'Customer A office'"
            exit 1
        fi
        add_to_whitelist "$2" "${3:-}"
        ;;
    remove)
        if [[ $# -lt 2 ]]; then
            echo "Usage: $0 remove <IP_or_CIDR>"
            echo "Example: $0 remove 203.0.113.50"
            exit 1
        fi
        remove_from_whitelist "$2"
        ;;
    list)
        list_whitelist
        ;;
    show)
        show_config
        ;;
    *)
        echo "Usage: $0 {add|remove|list|show} [arguments]"
        echo
        echo "Commands:"
        echo "  add <IP_or_CIDR> [comment]  - Add IP or CIDR range to whitelist"
        echo "  remove <IP_or_CIDR>        - Remove IP or CIDR range from whitelist"
        echo "  list                       - List all whitelisted IPs"
        echo "  show                       - Show configuration and whitelist"
        echo
        echo "Examples:"
        echo "  $0 add 203.0.113.50 'Customer A office'"
        echo "  $0 add 198.51.100.0/24 'Customer B network'"
        echo "  $0 remove 203.0.113.50"
        echo "  $0 list"
        exit 1
        ;;
esac
