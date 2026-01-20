#!/bin/bash
#
# OpenSIPS SIP Edge Router Installation Script
# Installs and configures OpenSIPS with MySQL routing database
#
# Usage: sudo ./install.sh [--skip-deps] [--skip-firewall] [--skip-db] [--skip-prometheus] [--advertised-ip <IP>] [--preferlan] [--db-password <PASSWORD>]
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
OPENSIPS_USER="opensips"
OPENSIPS_GROUP="opensips"
OPENSIPS_DIR="/etc/opensips"
OPENSIPS_DATA_DIR="/var/lib/opensips"
OPENSIPS_LOG_DIR="/var/log/opensips"
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="${INSTALL_DIR}/scripts"
CONFIG_DIR="${INSTALL_DIR}/config"

# Flags
SKIP_DEPS=false
SKIP_FIREWALL=false
SKIP_DB=false
SKIP_PROMETHEUS=false
ADVERTISED_IP=""
PREFER_LAN=false
DB_PASSWORD=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-deps)
            SKIP_DEPS=true
            shift
            ;;
        --skip-firewall)
            SKIP_FIREWALL=true
            shift
            ;;
        --skip-db)
            SKIP_DB=true
            shift
            ;;
        --skip-prometheus)
            SKIP_PROMETHEUS=true
            shift
            ;;
        --advertised-ip)
            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}Error: --advertised-ip requires an IP address${NC}"
                exit 1
            fi
            ADVERTISED_IP="$2"
            shift 2
            ;;
        --preferlan)
            PREFER_LAN=true
            shift
            ;;
        --db-password)
            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}Error: --db-password requires a password${NC}"
                exit 1
            fi
            DB_PASSWORD="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS version (/etc/os-release not found)"
        exit 1
    fi
    
    source /etc/os-release
    
    # Require Ubuntu
    if [[ "$ID" != "ubuntu" ]]; then
        log_error "This script requires Ubuntu. Detected: ${ID}"
        exit 1
    fi
    
    # Require Ubuntu 24.04 LTS (noble)
    if [[ "$VERSION_ID" != "24.04" ]]; then
        log_error "This script requires Ubuntu 24.04 LTS. Detected: Ubuntu ${VERSION_ID}"
        log_error "Please use Ubuntu 24.04 LTS (noble)"
        exit 1
    fi
    
    # Verify it's LTS (VERSION_CODENAME should be "noble")
    if [[ "${VERSION_CODENAME:-}" != "noble" ]]; then
        log_warn "Expected Ubuntu 24.04 LTS (noble), but VERSION_CODENAME is: ${VERSION_CODENAME:-unknown}"
        log_warn "Proceeding anyway, but this may cause issues..."
    fi
    
    log_success "Detected Ubuntu 24.04 LTS (noble)"
}

update_system() {
    log_info "Updating package lists..."
    apt-get update -qq || {
        log_error "Failed to update package lists"
        exit 1
    }
    
    log_info "Upgrading system packages..."
    apt-get upgrade -y -qq || {
        log_error "Failed to upgrade system packages"
        exit 1
    }
    
    log_success "System updated and upgraded"
}

install_dependencies() {
    if [[ "$SKIP_DEPS" == true ]]; then
        log_info "Skipping dependency installation"
        return
    fi
    
    log_info "Adding OpenSIPS APT repository..."
    # Add OpenSIPS official repository (apt.opensips.org)
    # Check if repository already added by checking if the file exists
    if [[ ! -f /etc/apt/sources.list.d/opensips.list ]]; then
        # Install prerequisites
        apt-get update -qq
        apt-get install -y curl ca-certificates || {
            log_error "Failed to install prerequisites for repository setup"
            exit 1
        }
        
        # Add OpenSIPS GPG key (using official method from OpenSIPS website)
        log_info "Adding OpenSIPS GPG key..."
        curl https://apt.opensips.org/opensips-org.gpg -o /usr/share/keyrings/opensips-org.gpg || {
            log_error "Failed to add OpenSIPS GPG key"
            exit 1
        }
        
        # Add OpenSIPS repository (hardcoded for Ubuntu 24.04 noble)
        log_info "Adding OpenSIPS repository for noble (Ubuntu 24.04)..."
        echo "deb [signed-by=/usr/share/keyrings/opensips-org.gpg] https://apt.opensips.org noble 3.6-releases" > /etc/apt/sources.list.d/opensips.list || {
            log_error "Failed to create OpenSIPS repository file"
            exit 1
        }
        
        log_success "OpenSIPS repository added successfully"
    else
        log_info "OpenSIPS repository already configured"
    fi
    
    log_info "Updating package lists..."
    apt-get update -qq
    
    log_info "Installing MySQL/MariaDB server..."
    apt-get install -y mariadb-server || {
        log_error "Failed to install MariaDB server"
        exit 1
    }
    
    log_info "Installing OpenSIPS and dependencies..."
    apt-get install -y \
        opensips \
        opensips-mysql-module \
        opensips-mysql-dbschema \
        opensips-http-modules \
        opensips-prometheus-module \
        curl \
        wget \
        ufw \
        jq \
        || {
            log_error "Failed to install dependencies"
            exit 1
        }
    
    # Verify OpenSIPS installation and log version
    if command -v opensips &> /dev/null; then
        OPENSIPS_VERSION=$(opensips -V 2>&1 | head -n1 || echo "unknown")
        log_success "Dependencies installed (OpenSIPS: ${OPENSIPS_VERSION})"
        
        # Verify MySQL module is available
        if opensips -m 2>/dev/null | grep -q mysql; then
            log_success "MySQL module is available"
        else
            log_warn "MySQL module not found - check OpenSIPS module installation"
        fi
        
        # Verify HTTP modules (httpd and prometheus) are available
        if opensips -m 2>/dev/null | grep -qE "(httpd|prometheus)"; then
            log_success "HTTP modules (httpd/prometheus) are available"
        else
            log_warn "HTTP modules (httpd/prometheus) not found - check opensips-http-modules and opensips-prometheus-module package installation"
        fi
    else
        log_error "OpenSIPS installation failed - opensips command not found"
        exit 1
    fi
}

install_opensips_cli() {
    log_info "Installing OpenSIPS CLI..."
    
    # Check if CLI repository already added
    if [[ ! -f /etc/apt/sources.list.d/opensips-cli.list ]]; then
        # Add OpenSIPS GPG key (using official method from OpenSIPS website)
        log_info "Adding OpenSIPS GPG key..."
        curl https://apt.opensips.org/opensips-org.gpg -o /usr/share/keyrings/opensips-org.gpg || {
            log_error "Failed to add OpenSIPS GPG key"
            exit 1
        }
        
        # Add OpenSIPS CLI repository (hardcoded for Ubuntu 24.04 noble)
        log_info "Adding OpenSIPS CLI repository for noble (Ubuntu 24.04)..."
        echo "deb [signed-by=/usr/share/keyrings/opensips-org.gpg] https://apt.opensips.org noble cli-nightly" > /etc/apt/sources.list.d/opensips-cli.list || {
            log_error "Failed to create OpenSIPS CLI repository file"
            exit 1
        }
        
        log_success "OpenSIPS CLI repository added"
        
        # Update package lists
        log_info "Updating package lists..."
        apt-get update -qq
    else
        log_info "OpenSIPS CLI repository already configured"
        apt-get update -qq
    fi
    
    # Install opensips-cli
    log_info "Installing opensips-cli package..."
    apt-get install -y opensips-cli || {
        log_error "Failed to install opensips-cli"
        exit 1
    }
    
    # Verify installation
    if command -v opensips-cli &> /dev/null; then
        CLI_VERSION=$(opensips-cli --version 2>&1 | head -n1 || echo "unknown")
        log_success "OpenSIPS CLI installed (${CLI_VERSION})"
    else
        log_warn "opensips-cli command not found - installation may have failed"
    fi
}

# Litestream installation removed - only .deb packages available for arm64
# Can be added back later when amd64 packages are available

create_user() {
    log_info "Creating opensips user and group..."
    
    if id "$OPENSIPS_USER" &>/dev/null; then
        log_info "User ${OPENSIPS_USER} already exists"
    else
        useradd -r -s /bin/false -d /var/run/opensips -c "OpenSIPS SIP Server" "$OPENSIPS_USER" || {
            log_error "Failed to create opensips user"
            exit 1
        }
        log_success "Created user ${OPENSIPS_USER}"
    fi
}

create_directories() {
    log_info "Creating directories..."
    
    mkdir -p "$OPENSIPS_DIR"
    mkdir -p "$OPENSIPS_DATA_DIR"
    mkdir -p "$OPENSIPS_LOG_DIR"
    mkdir -p /var/run/opensips
    
    chown -R "${OPENSIPS_USER}:${OPENSIPS_GROUP}" "$OPENSIPS_DIR"
    chown -R "${OPENSIPS_USER}:${OPENSIPS_GROUP}" "$OPENSIPS_DATA_DIR"
    chown -R "${OPENSIPS_USER}:${OPENSIPS_GROUP}" "$OPENSIPS_LOG_DIR"
    chown -R "${OPENSIPS_USER}:${OPENSIPS_GROUP}" /var/run/opensips
    
    log_success "Directories created"
}

setup_helper_scripts() {
    log_info "Setting up helper scripts..."
    
    # Ensure scripts are executable
    if [[ -d "$SCRIPT_DIR" ]]; then
        chmod +x "$SCRIPT_DIR"/*.sh 2>/dev/null || true
        log_success "Helper scripts are executable"
    else
        log_warn "Scripts directory not found: ${SCRIPT_DIR}"
    fi
}

configure_firewall() {
    if [[ "$SKIP_FIREWALL" == true ]]; then
        log_info "Skipping firewall configuration"
        return
    fi
    
    log_info "Configuring firewall..."
    
    # Enable UFW if not already enabled
    ufw --force enable || true
    
    # Helper function to add firewall rule if it doesn't exist
    add_ufw_rule_if_missing() {
        local rule="$1"
        local comment="$2"
        
        # Check if rule already exists
        # UFW status format: rule ALLOW ... # comment (or [number] rule ALLOW ... with numbered)
        # Escape special characters in rule for regex (e.g., '/' becomes '\/')
        local escaped_rule=$(echo "$rule" | sed 's|/|\\/|g; s|\.|\\.|g')
        if ufw status | grep -qE "^\s*\[.*\]\s+${escaped_rule}\s+|^\s*${escaped_rule}\s+.*ALLOW"; then
            log_info "Firewall rule already exists: ${rule} (${comment})"
            return 0
        fi
        
        # Rule doesn't exist, add it
        ufw allow "$rule" comment "$comment" || {
            log_warn "Failed to add firewall rule: ${rule}"
            return 1
        }
        log_info "Added firewall rule: ${rule} (${comment})"
    }
    
    # Allow SSH (important!)
    add_ufw_rule_if_missing "22/tcp" "SSH"
    
    # Allow SIP
    add_ufw_rule_if_missing "5060/udp" "SIP UDP"
    add_ufw_rule_if_missing "5060/tcp" "SIP TCP"
    add_ufw_rule_if_missing "5061/tcp" "SIP TLS"
    
    # Allow RTP range (for endpoints, not handled by OpenSIPS but good to document)
    add_ufw_rule_if_missing "10000:20000/udp" "RTP range"
    
    # Allow Prometheus and Node Exporter (if installed)
    if [[ "$SKIP_PROMETHEUS" != true ]]; then
        # Prometheus web UI (restrict to localhost in production)
        add_ufw_rule_if_missing "9090/tcp" "Prometheus web UI"
        # Node Exporter metrics (restrict to localhost in production)
        add_ufw_rule_if_missing "9100/tcp" "Node Exporter metrics"
        # OpenSIPS Prometheus module endpoint (if exposed externally)
        add_ufw_rule_if_missing "8888/tcp" "OpenSIPS Prometheus metrics"
    fi
    
    log_success "Firewall configured"
    log_warn "Firewall rules applied. Ensure SSH access is working before disconnecting!"
}

# Litestream configuration removed - can be added back later

# Litestream service removed - can be added back later

# Detect both LAN and external IP addresses
detect_both_ips() {
    local lan_ip=""
    local external_ip=""
    local active_iface=""
    
    # Get LAN IP from first active interface (excluding loopback)
    active_iface=$(ip addr | grep UP | grep -v lo: | head -n1 | awk -F': ' '{print $2}' || echo "")
    
    if [[ -n "$active_iface" ]]; then
        lan_ip=$(ip -4 addr show dev "$active_iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1 || true)
    fi
    
    # Try to get external IP (for cloud deployments)
    external_ip=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null | head -n1 | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' || true)
    
    # Return both IPs via global variables (bash doesn't return multiple values easily)
    DETECTED_LAN_IP="$lan_ip"
    DETECTED_EXTERNAL_IP="$external_ip"
    DETECTED_ACTIVE_IFACE="$active_iface"
}

detect_ip_address() {
    local prefer_lan="${1:-false}"
    local external_ip=""
    local lan_ip=""
    
    # Get LAN IP from first active interface (excluding loopback)
    log_info "Detecting LAN IP..." >&2
    local active_iface
    active_iface=$(ip addr | grep UP | grep -v lo: | head -n1 | awk -F': ' '{print $2}' || echo "")
    
    if [[ -n "$active_iface" ]]; then
        lan_ip=$(ip -4 addr show dev "$active_iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1 || true)
        if [[ -n "$lan_ip" ]]; then
            log_info "Detected LAN IP on ${active_iface}: ${lan_ip}" >&2
        fi
    fi
    
    # Try to get external IP (for cloud deployments)
    if [[ "$prefer_lan" != "true" ]]; then
        log_info "Detecting external IP address..." >&2
        external_ip=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null | head -n1 | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' || true)
        if [[ -n "$external_ip" ]]; then
            log_info "Detected external IP: ${external_ip}" >&2
        fi
    fi
    
    # Return preferred IP based on preference
    if [[ "$prefer_lan" == "true" ]]; then
        if [[ -n "$lan_ip" ]]; then
            echo "$lan_ip"
            return 0
        fi
        # Fall back to external if LAN not available
        if [[ -n "$external_ip" ]]; then
            log_warn "LAN IP not available, using external IP as fallback" >&2
            echo "$external_ip"
            return 0
        fi
    else
        # Prefer external IP, fall back to LAN
        if [[ -n "$external_ip" ]]; then
            echo "$external_ip"
            return 0
        fi
        if [[ -n "$lan_ip" ]]; then
            log_info "External IP detection failed, using LAN IP" >&2
            echo "$lan_ip"
            return 0
        fi
    fi
    
    # No IP detected
    return 1
}

create_opensips_config() {
    log_info "Creating OpenSIPS configuration..."
    
    OPENSIPS_CFG="${OPENSIPS_DIR}/opensips.cfg"
    
    if [[ -f "$OPENSIPS_CFG" ]]; then
        # Check if this is our config (contains CHANGE_ME marker) or the default OpenSIPS package config
        if grep -q "CHANGE_ME" "$OPENSIPS_CFG" 2>/dev/null; then
            # This is our config template - check if it's valid and already configured
            if opensips -C -f "$OPENSIPS_CFG" &>/dev/null && ! grep -q "advertised_address=\"CHANGE_ME\"" "$OPENSIPS_CFG" 2>/dev/null; then
                log_info "OpenSIPS config already exists and is configured at ${OPENSIPS_CFG}"
                log_info "Skipping config creation (idempotent)"
                return 0
            fi
            # Our config exists but needs updating - backup and continue
            log_info "Backing up existing config..."
            mv "$OPENSIPS_CFG" "${OPENSIPS_CFG}.backup.$(date +%Y%m%d_%H%M%S)"
        else
            # This is the default OpenSIPS package config, not ours - backup and replace it
            log_info "Default OpenSIPS package config detected - backing up and replacing with our template..."
            mv "$OPENSIPS_CFG" "${OPENSIPS_CFG}.backup.$(date +%Y%m%d_%H%M%S)"
        fi
    fi
    
    # Copy template - it must exist
    if [[ ! -f "${CONFIG_DIR}/opensips.cfg.template" ]]; then
        log_error "OpenSIPS template not found at ${CONFIG_DIR}/opensips.cfg.template"
        log_error "Please ensure the template file exists in the repository"
        return 1
    fi
    
    cp "${CONFIG_DIR}/opensips.cfg.template" "$OPENSIPS_CFG"
    log_success "Copied OpenSIPS config from template: ${CONFIG_DIR}/opensips.cfg.template"
    
    # Update database password in config (if DB is not skipped)
    if [[ "$SKIP_DB" != true ]] && [[ -n "$DB_PASSWORD" ]]; then
        # Escape password for sed (replace / with \/ and & with \&)
        local escaped_pass
        escaped_pass=$(echo "$DB_PASSWORD" | sed 's|/|\\/|g; s|&|\\&|g')
        sed -i "s|your-password|${escaped_pass}|g" "$OPENSIPS_CFG"
    fi
    
    # Set ownership on config file
    chown "${OPENSIPS_USER}:${OPENSIPS_GROUP}" "$OPENSIPS_CFG"
    
    # Determine advertised_address: use provided IP, auto-detect with prompt, or warn
    local final_ip=""
    if [[ -n "$ADVERTISED_IP" ]]; then
        final_ip="$ADVERTISED_IP"
        log_info "Using provided advertised_address: ${final_ip}"
    elif [[ "$PREFER_LAN" == "true" ]]; then
        # --preferlan flag: use LAN IP directly without prompt
        log_info "Auto-detecting LAN IP address..."
        if final_ip=$(detect_ip_address "true"); then
            log_info "Auto-detected LAN IP: ${final_ip}"
        else
            log_warn "Could not detect LAN IP address"
            log_warn "advertised_address not set - you must manually update it in ${OPENSIPS_CFG}"
            return 0
        fi
    else
        # Auto-detect and prompt user to choose between LAN and external IP
        log_info "Auto-detecting IP addresses..."
        detect_both_ips
        
        local lan_ip="$DETECTED_LAN_IP"
        local external_ip="$DETECTED_EXTERNAL_IP"
        local active_iface="$DETECTED_ACTIVE_IFACE"
        
        # Prompt user to choose IP address when at least one is detected
        if [[ -n "$lan_ip" ]] && [[ -n "$external_ip" ]]; then
            # Both IPs detected - prompt user to choose
            echo
            log_info "Detected IP addresses:"
            if [[ -n "$active_iface" ]]; then
                echo "  LAN IP (${active_iface}):     ${lan_ip}"
            else
                echo "  LAN IP:                      ${lan_ip}"
            fi
            echo "  External IP:                ${external_ip}"
            echo
            echo "Which IP address should be used for advertised_address?"
            echo "  1) LAN IP (${lan_ip}) - Recommended for local/testing deployments"
            echo "  2) External IP (${external_ip}) - Recommended for cloud/production deployments"
            echo
            while true; do
                read -p "Enter choice (1 or 2): " -n 1 -r
                echo
                case $REPLY in
                    1)
                        final_ip="$lan_ip"
                        log_info "Selected LAN IP: ${final_ip}"
                        break
                        ;;
                    2)
                        final_ip="$external_ip"
                        log_info "Selected External IP: ${final_ip}"
                        break
                        ;;
                    *)
                        echo -e "${YELLOW}Invalid choice. Please enter 1 or 2.${NC}"
                        ;;
                esac
            done
        elif [[ -n "$lan_ip" ]]; then
            # Only LAN IP detected - still prompt user (they might want to enter a different IP)
            echo
            log_info "Detected IP address:"
            if [[ -n "$active_iface" ]]; then
                echo "  LAN IP (${active_iface}):     ${lan_ip}"
            else
                echo "  LAN IP:                      ${lan_ip}"
            fi
            echo
            echo "Which IP address should be used for advertised_address?"
            echo "  1) Use detected LAN IP (${lan_ip})"
            echo "  2) Enter a different IP address"
            echo
            while true; do
                read -p "Enter choice (1 or 2): " -n 1 -r
                echo
                case $REPLY in
                    1)
                        final_ip="$lan_ip"
                        log_info "Selected LAN IP: ${final_ip}"
                        break
                        ;;
                    2)
                        read -p "Enter IP address: " -r
                        echo
                        if [[ $REPLY =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                            final_ip="$REPLY"
                            log_info "Selected IP: ${final_ip}"
                            break
                        else
                            echo -e "${YELLOW}Invalid IP address format. Please enter a valid IPv4 address.${NC}"
                        fi
                        ;;
                    *)
                        echo -e "${YELLOW}Invalid choice. Please enter 1 or 2.${NC}"
                        ;;
                esac
            done
        elif [[ -n "$external_ip" ]]; then
            # Only external IP detected - still prompt user (they might want to enter a different IP)
            echo
            log_info "Detected IP address:"
            echo "  External IP:                ${external_ip}"
            echo
            echo "Which IP address should be used for advertised_address?"
            echo "  1) Use detected External IP (${external_ip})"
            echo "  2) Enter a different IP address"
            echo
            while true; do
                read -p "Enter choice (1 or 2): " -n 1 -r
                echo
                case $REPLY in
                    1)
                        final_ip="$external_ip"
                        log_info "Selected External IP: ${final_ip}"
                        break
                        ;;
                    2)
                        read -p "Enter IP address: " -r
                        echo
                        if [[ $REPLY =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                            final_ip="$REPLY"
                            log_info "Selected IP: ${final_ip}"
                            break
                        else
                            echo -e "${YELLOW}Invalid IP address format. Please enter a valid IPv4 address.${NC}"
                        fi
                        ;;
                    *)
                        echo -e "${YELLOW}Invalid choice. Please enter 1 or 2.${NC}"
                        ;;
                esac
            done
        else
            # No IPs detected - prompt user to enter one
            echo
            log_warn "Could not auto-detect IP address"
            echo "Please enter the IP address to use for advertised_address:"
            while true; do
                read -p "Enter IP address: " -r
                echo
                if [[ $REPLY =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                    final_ip="$REPLY"
                    log_info "Selected IP: ${final_ip}"
                    break
                else
                    echo -e "${YELLOW}Invalid IP address format. Please enter a valid IPv4 address.${NC}"
                fi
            done
        fi
    fi
    
    # Update advertised_address in config
    if [[ -n "$final_ip" ]]; then
        # Trim any whitespace/newlines from the IP address
        final_ip=$(echo "$final_ip" | tr -d '\n\r' | xargs)
        sed -i "s|advertised_address=\"CHANGE_ME\"|advertised_address=\"${final_ip}\"|g" "$OPENSIPS_CFG"
        log_success "Set advertised_address to ${final_ip}"
    fi
    
    log_success "OpenSIPS configuration created at ${OPENSIPS_CFG}"
}

save_database_credentials() {
    # Save database credentials to a file that helper scripts can read
    # Only save if we're not skipping DB setup
    if [[ "$SKIP_DB" == true ]] || [[ -z "$DB_PASSWORD" ]] || [[ "$DB_PASSWORD" == "your-password" ]]; then
        return 0
    fi
    
    local cred_file="${OPENSIPS_DIR}/.mysql_credentials"
    
    # Check if credentials file already exists and password matches (idempotency)
    if [[ -f "$cred_file" ]]; then
        # Source the existing file to get the current password
        # Use a subshell to avoid polluting the current environment
        local existing_pass
        existing_pass=$(source "$cred_file" 2>/dev/null && echo "${DB_PASS:-}" || echo "")
        if [[ -n "$existing_pass" ]] && [[ "$existing_pass" == "$DB_PASSWORD" ]]; then
            log_info "Database credentials file already exists with matching password (idempotent)"
            return 0
        fi
    fi
    
    log_info "Saving database credentials for helper scripts..."
    
    # Escape password for shell script (escape $, `, ", \)
    local escaped_pass
    escaped_pass=$(printf '%q' "$DB_PASSWORD")
    
    # Create credentials file with proper permissions
    cat > "$cred_file" <<EOF
# MySQL database credentials for OpenSIPS helper scripts
# This file is automatically generated by install.sh
# DO NOT edit manually - it will be overwritten on reinstall

DB_NAME="opensips"
DB_USER="opensips"
DB_PASS=${escaped_pass}
EOF
    
    # Set restrictive permissions (readable only by root)
    chmod 600 "$cred_file"
    chown root:root "$cred_file"
    
    log_success "Database credentials saved to ${cred_file}"
}

initialize_database() {
    if [[ "$SKIP_DB" == true ]]; then
        log_info "Skipping database initialization"
        return
    fi
    
    log_info "Setting up MySQL database..."
    
    # Database configuration
    DB_NAME="opensips"
    DB_USER="opensips"
    DB_PASS="$DB_PASSWORD"  # Password already set in main() function
    
    # Check if database already exists
    if mysql -u root -e "USE ${DB_NAME};" 2>/dev/null; then
        log_warn "MySQL database '${DB_NAME}' already exists"
        read -p "Reinitialize database? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping database reinitialization"
            log_info "Database already exists - if you need to reinitialize, run: sudo ${SCRIPT_DIR}/init-database.sh"
            return
        fi
        log_info "Dropping existing database for reinitialization..."
        mysql -u root <<EOF
DROP DATABASE IF EXISTS ${DB_NAME};
EOF
    fi
    
    # Create database and user
    log_info "Creating MySQL database and user..."
    mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8 COLLATE utf8_general_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create MySQL database and user"
        return 1
    fi
    
    log_success "MySQL database and user created"
    
    # Use the dedicated init-database.sh script
    # Set environment variables for MySQL configuration
    export DB_NAME="$DB_NAME"
    export DB_USER="$DB_USER"
    export DB_PASS="$DB_PASS"
    export OPENSIPS_USER="$OPENSIPS_USER"
    export OPENSIPS_GROUP="$OPENSIPS_GROUP"
    
    log_info "Running database initialization script: ${SCRIPT_DIR}/init-database.sh"
    if "${SCRIPT_DIR}/init-database.sh"; then
        log_success "Database schema initialized"
        log_info "Add your domains and dispatcher entries using mysql or the provided scripts"
    else
        log_error "Database initialization failed"
        return 1
    fi
}

setup_cleanup_timer() {
    log_info "Setting up endpoint cleanup timer..."
    
    # Copy cleanup script to system location
    if [[ -f "${SCRIPT_DIR}/cleanup-expired-endpoints.sh" ]]; then
        cp "${SCRIPT_DIR}/cleanup-expired-endpoints.sh" /usr/local/bin/ || {
            log_warn "Failed to copy cleanup script to /usr/local/bin"
            return 1
        }
        chmod +x /usr/local/bin/cleanup-expired-endpoints.sh
        log_success "Cleanup script installed"
    else
        log_warn "Cleanup script not found at ${SCRIPT_DIR}/cleanup-expired-endpoints.sh"
        return 1
    fi
    
    # Copy service and timer files
    if [[ -f "${SCRIPT_DIR}/cleanup-expired-endpoints.service" ]] && [[ -f "${SCRIPT_DIR}/cleanup-expired-endpoints.timer" ]]; then
        # Read database credentials from saved file
        local db_pass="your-password"
        local cred_file="${OPENSIPS_DIR}/.mysql_credentials"
        
        if [[ -f "$cred_file" ]]; then
            # Source credentials file in a subshell to get DB_PASS
            db_pass=$(source "$cred_file" 2>/dev/null && echo "${DB_PASS:-your-password}" || echo "your-password")
        elif [[ -n "${DB_PASSWORD:-}" ]] && [[ "${DB_PASSWORD}" != "your-password" ]]; then
            # Fallback to DB_PASSWORD if credentials file doesn't exist yet
            db_pass="$DB_PASSWORD"
        fi
        
        # Create service file with actual database credentials
        cat > /etc/systemd/system/cleanup-expired-endpoints.service <<EOF
[Unit]
Description=OpenSIPS Expired Endpoint Locations Cleanup
After=network.target mysql.service

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/cleanup-expired-endpoints.sh
Environment="DB_NAME=opensips"
Environment="DB_USER=opensips"
Environment="DB_PASS=${db_pass}"
StandardOutput=journal
StandardError=journal
EOF
        
        # Copy timer file
        cp "${SCRIPT_DIR}/cleanup-expired-endpoints.timer" /etc/systemd/system/ || {
            log_warn "Failed to copy timer file"
            return 1
        }
        
        # Reload systemd and enable timer
        systemctl daemon-reload || {
            log_warn "Failed to reload systemd"
            return 1
        }
        
        systemctl enable cleanup-expired-endpoints.timer || {
            log_warn "Failed to enable cleanup timer"
            return 1
        }
        
        log_success "Cleanup timer enabled (runs daily at 2:00 AM)"
    else
        log_warn "Cleanup service/timer files not found"
        return 1
    fi
}

install_prometheus() {
    if [[ "$SKIP_PROMETHEUS" == true ]]; then
        log_info "Skipping Prometheus installation"
        return
    fi
    
    log_info "Installing Prometheus and Node Exporter..."
    
    # Check if Prometheus is already installed
    if command -v prometheus &> /dev/null; then
        log_info "Prometheus already installed: $(prometheus --version 2>&1 | head -n1)"
    else
        # Create Prometheus user
        if ! id -u prometheus &>/dev/null; then
            useradd --no-create-home --shell /bin/false prometheus || {
                log_error "Failed to create prometheus user"
                exit 1
            }
        fi
        
        # Create directories
        mkdir -p /etc/prometheus
        mkdir -p /var/lib/prometheus
        chown prometheus:prometheus /etc/prometheus
        chown prometheus:prometheus /var/lib/prometheus
        
        # Download Prometheus
        cd /tmp
        PROMETHEUS_VERSION="2.51.2"  # Update to latest version as needed
        log_info "Downloading Prometheus ${PROMETHEUS_VERSION}..."
        
        if [[ ! -f "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" ]]; then
            wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" || {
                log_error "Failed to download Prometheus"
                exit 1
            }
        fi
        
        # Extract
        tar xf "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
        cd "prometheus-${PROMETHEUS_VERSION}.linux-amd64"
        
        # Copy binaries
        cp prometheus /usr/local/bin/
        cp promtool /usr/local/bin/
        chown prometheus:prometheus /usr/local/bin/prometheus
        chown prometheus:prometheus /usr/local/bin/promtool
        
        # Copy configuration files
        cp -r consoles /etc/prometheus
        cp -r console_libraries /etc/prometheus
        chown -R prometheus:prometheus /etc/prometheus/consoles
        chown -R prometheus:prometheus /etc/prometheus/console_libraries
        
        log_success "Prometheus ${PROMETHEUS_VERSION} installed"
    fi
    
    # Install Node Exporter
    if command -v node_exporter &> /dev/null; then
        log_info "Node Exporter already installed: $(node_exporter --version 2>&1 | head -n1)"
    else
        # Create node_exporter user
        if ! id -u node_exporter &>/dev/null; then
            useradd --no-create-home --shell /bin/false node_exporter || {
                log_error "Failed to create node_exporter user"
                exit 1
            }
        fi
        
        # Download Node Exporter
        cd /tmp
        NODE_EXPORTER_VERSION="1.7.0"  # Update to latest version as needed
        log_info "Downloading Node Exporter ${NODE_EXPORTER_VERSION}..."
        
        if [[ ! -f "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz" ]]; then
            wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz" || {
                log_error "Failed to download Node Exporter"
                exit 1
            }
        fi
        
        # Extract
        tar xf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
        cd "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"
        
        # Copy binary
        cp node_exporter /usr/local/bin/
        chown node_exporter:node_exporter /usr/local/bin/node_exporter
        
        log_success "Node Exporter ${NODE_EXPORTER_VERSION} installed"
    fi
}

configure_prometheus() {
    if [[ "$SKIP_PROMETHEUS" == true ]]; then
        log_info "Skipping Prometheus configuration"
        return
    fi
    
    log_info "Configuring Prometheus..."
    
    # Create Prometheus configuration
    cat > /etc/prometheus/prometheus.yml <<'PROMETHEUS_EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'pbx3sbc'
    environment: 'production'

# Alertmanager configuration (optional)
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          # - alertmanager:9093

# Load alert rules
rule_files:
  - "alerts.yml"

# Scrape configurations
scrape_configs:
  # OpenSIPS statistics (from Prometheus module)
  - job_name: 'opensips'
    static_configs:
      - targets: ['localhost:8888']  # OpenSIPS HTTP endpoint (Prometheus module)
    scrape_interval: 15s
    metrics_path: '/metrics'
    scrape_timeout: 10s
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        replacement: 'opensips-sbc'

  # Node Exporter (system metrics - required for Grafana dashboards)
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']  # Node Exporter default port
    scrape_interval: 15s
    metrics_path: '/metrics'
    scrape_timeout: 10s

  # Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
PROMETHEUS_EOF
    
    # Create basic alert rules
    cat > /etc/prometheus/alerts.yml <<'ALERTS_EOF'
groups:
  - name: opensips_alerts
    interval: 30s
    rules:
      - alert: HighErrorRate
        expr: rate(opensips_core_drop_requests[5m]) / rate(opensips_core_rcv_requests[5m]) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value | humanizePercentage }}"

      - alert: NoActiveDestinations
        expr: opensips_dispatcher_active_destinations == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "No active dispatcher destinations"
          description: "All Asterisk backends are down"

      - alert: HighActiveTransactions
        expr: opensips_tm_active_transactions > 1000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High number of active transactions"
          description: "Active transactions: {{ $value }}"
ALERTS_EOF
    
    chown prometheus:prometheus /etc/prometheus/prometheus.yml
    chown prometheus:prometheus /etc/prometheus/alerts.yml
    chmod 640 /etc/prometheus/prometheus.yml
    chmod 640 /etc/prometheus/alerts.yml
    
    # Create Prometheus systemd service
    cat > /etc/systemd/system/prometheus.service <<'SERVICE_EOF'
[Unit]
Description=Prometheus Monitoring System
Documentation=https://prometheus.io/docs/introduction/overview/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus/ \
    --storage.tsdb.retention.time=30d \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --web.listen-address=0.0.0.0:9090 \
    --web.enable-lifecycle

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE_EOF
    
    # Create Node Exporter systemd service
    cat > /etc/systemd/system/node_exporter.service <<'NODE_SERVICE_EOF'
[Unit]
Description=Prometheus Node Exporter
Documentation=https://github.com/prometheus/node_exporter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter \
    --web.listen-address=0.0.0.0:9100 \
    --collector.filesystem.mount-points-exclude="^/(sys|proc|dev|host|etc)($$|/)"

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
NODE_SERVICE_EOF
    
    # Reload systemd
    systemctl daemon-reload
    
    log_success "Prometheus configuration created"
}

enable_services() {
    log_info "Enabling services..."
    
    # Enable OpenSIPS
    systemctl enable opensips || {
        log_error "Failed to enable OpenSIPS service"
        exit 1
    }
    
    # Enable Prometheus and Node Exporter if installed
    if [[ "$SKIP_PROMETHEUS" != true ]]; then
        systemctl enable prometheus || {
            log_warn "Failed to enable Prometheus service"
        }
        
        systemctl enable node_exporter || {
            log_warn "Failed to enable Node Exporter service"
        }
    fi
    
    # Setup cleanup timer (non-fatal if it fails)
    setup_cleanup_timer || {
        log_warn "Cleanup timer setup failed - you can set it up manually later"
    }
    
    log_success "Services enabled"
}

start_services() {
    log_info "Starting services..."
    
    # Start OpenSIPS
    systemctl start opensips || {
        log_error "Failed to start OpenSIPS"
        exit 1
    }
    
    sleep 2
    
    # Check OpenSIPS status
    if systemctl is-active --quiet opensips; then
        log_success "OpenSIPS started"
    else
        log_error "OpenSIPS failed to start. Check logs: journalctl -u opensips"
    fi
    
    # Start Prometheus and Node Exporter if installed
    if [[ "$SKIP_PROMETHEUS" != true ]]; then
        # Start Node Exporter first (Prometheus depends on it)
        systemctl start node_exporter || {
            log_warn "Failed to start Node Exporter"
        } || true
        
        sleep 1
        
        # Start Prometheus
        systemctl start prometheus || {
            log_warn "Failed to start Prometheus"
        } || true
        
        sleep 2
        
        # Check status
        if systemctl is-active --quiet node_exporter; then
            log_success "Node Exporter started"
        else
            log_warn "Node Exporter failed to start. Check logs: journalctl -u node_exporter"
        fi
        
        if systemctl is-active --quiet prometheus; then
            log_success "Prometheus started"
        else
            log_warn "Prometheus failed to start. Check logs: journalctl -u prometheus"
        fi
    fi
}

verify_installation() {
    log_info "Verifying installation..."
    
    echo
    echo "=== Installation Verification ==="
    echo
    
    # Check database (skip if DB setup was skipped)
    if [[ "$SKIP_DB" != true ]] && [[ -n "$DB_PASSWORD" ]]; then
        if mysql -u opensips -p"$DB_PASSWORD" -e "USE opensips;" 2>/dev/null; then
            echo -e "${GREEN}✓${NC} MySQL database 'opensips' is accessible"
            TABLE_COUNT=$(mysql -u opensips -p"$DB_PASSWORD" opensips -sN -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='opensips';" 2>/dev/null || echo "0")
            echo -e "  Tables: ${TABLE_COUNT}"
        else
            echo -e "${RED}✗${NC} MySQL database 'opensips' not accessible"
        fi
    else
        echo -e "${YELLOW}⚠${NC} Database verification skipped"
    fi
    
    # Check OpenSIPS
    if command -v opensips &> /dev/null; then
        echo -e "${GREEN}✓${NC} OpenSIPS installed: $(opensips -V 2>&1 | head -n1)"
    else
        echo -e "${RED}✗${NC} OpenSIPS not found"
    fi
    
    # Check OpenSIPS service
    if systemctl is-enabled --quiet opensips 2>/dev/null; then
        echo -e "${GREEN}✓${NC} OpenSIPS service enabled"
    else
        echo -e "${YELLOW}⚠${NC} OpenSIPS service not enabled"
    fi
    
    if systemctl is-active --quiet opensips 2>/dev/null; then
        echo -e "${GREEN}✓${NC} OpenSIPS service running"
    else
        echo -e "${RED}✗${NC} OpenSIPS service not running"
    fi
    
    # Check cleanup timer
    if systemctl is-enabled --quiet cleanup-expired-endpoints.timer 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Endpoint cleanup timer enabled"
    else
        echo -e "${YELLOW}⚠${NC} Endpoint cleanup timer not enabled"
    fi
    
    # Check Prometheus and Node Exporter if installed
    if [[ "$SKIP_PROMETHEUS" != true ]]; then
        if command -v prometheus &> /dev/null; then
            echo -e "${GREEN}✓${NC} Prometheus installed: $(prometheus --version 2>&1 | head -n1)"
        else
            echo -e "${RED}✗${NC} Prometheus not found"
        fi
        
        if command -v node_exporter &> /dev/null; then
            echo -e "${GREEN}✓${NC} Node Exporter installed: $(node_exporter --version 2>&1 | head -n1)"
        else
            echo -e "${RED}✗${NC} Node Exporter not found"
        fi
        
        if systemctl is-active --quiet prometheus 2>/dev/null; then
            echo -e "${GREEN}✓${NC} Prometheus service running"
        else
            echo -e "${YELLOW}⚠${NC} Prometheus service not running"
        fi
        
        if systemctl is-active --quiet node_exporter 2>/dev/null; then
            echo -e "${GREEN}✓${NC} Node Exporter service running"
        else
            echo -e "${YELLOW}⚠${NC} Node Exporter service not running"
        fi
    fi
    
    echo
    echo "=== Next Steps ==="
    echo
    echo "1. Add domains and dispatcher entries to the database:"
    echo "   mysql -u opensips -p'your-password' opensips"
    echo "   Or use helper scripts:"
    echo "     ${SCRIPT_DIR}/add-domain.sh <domain>"
    echo "     ${SCRIPT_DIR}/add-dispatcher.sh <setid> <destination>"
    echo
    echo "2. Check service status:"
    echo "   systemctl status opensips"
    echo
    echo "3. View logs:"
    echo "   journalctl -u opensips -f"
    echo
    echo "4. Test SIP connectivity (using a SIP client tool):"
    echo "   # Install a SIP testing tool (e.g., sipsak, sipp, or sip-tester if available)"
    echo "   # Example with sipsak:"
    echo "   # sipsak -s sip:your-domain.com -H your-domain.com"
    echo
}

# Main installation flow
main() {
    echo
    echo "=========================================="
    echo "OpenSIPS SIP Edge Router Installation"
    echo "=========================================="
    echo
    
    check_root
    check_ubuntu
    update_system
    
    log_info "Starting installation..."
    echo
    
    install_dependencies
    install_opensips_cli
    install_prometheus
    create_user
    create_directories
    setup_helper_scripts
    configure_firewall
    configure_prometheus
    
    # Get database password early so it can be used in config creation
    if [[ "$SKIP_DB" != true ]] && [[ -z "$DB_PASSWORD" ]]; then
        echo
        read -sp "Enter MySQL database password for user 'opensips': " DB_PASSWORD
        echo
        if [[ -z "$DB_PASSWORD" ]]; then
            log_error "Database password cannot be empty"
            exit 1
        fi
    elif [[ "$SKIP_DB" != true ]]; then
        DB_PASSWORD="$DB_PASSWORD"
    else
        DB_PASSWORD="your-password"  # Placeholder when skipping DB
    fi
    
    # Save credentials for helper scripts (before config creation so it's available)
    save_database_credentials
    
    create_opensips_config
    initialize_database
    enable_services
    start_services
    verify_installation
    
    echo
    log_success "Installation complete!"
    echo
    log_info "Configuration files:"
    echo "  - OpenSIPS: ${OPENSIPS_DIR}/opensips.cfg"
    echo "  - Database: MySQL database 'opensips'"
    if [[ "$SKIP_PROMETHEUS" != true ]]; then
        echo "  - Prometheus: /etc/prometheus/prometheus.yml"
        echo "  - Prometheus Alerts: /etc/prometheus/alerts.yml"
        echo "  - Prometheus Web UI: http://localhost:9090"
        echo "  - Node Exporter: http://localhost:9100/metrics"
    fi
    echo
}

# Run main function
main "$@"
