#!/bin/bash
#
# OpenSIPS SIP Edge Router Installation Script
# Installs and configures OpenSIPS with MySQL routing database
#
# Usage: sudo ./install.sh [--skip-deps] [--skip-firewall] [--skip-db] [--advertised-ip <IP>] [--preferlan] [--db-password <PASSWORD>]
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
        
        # Verify HTTP modules are available (for control panel)
        if opensips -m 2>/dev/null | grep -q httpd; then
            log_success "HTTP modules are available"
        else
            log_warn "HTTP modules not found - required for control panel"
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
    
    # Allow HTTP/HTTPS (for control panel)
    add_ufw_rule_if_missing "80/tcp" "HTTP"
    add_ufw_rule_if_missing "443/tcp" "HTTPS"
    
    # Allow SIP
    add_ufw_rule_if_missing "5060/udp" "SIP UDP"
    add_ufw_rule_if_missing "5060/tcp" "SIP TCP"
    add_ufw_rule_if_missing "5061/tcp" "SIP TLS"
    
    # Allow RTP range (for endpoints, not handled by OpenSIPS but good to document)
    add_ufw_rule_if_missing "10000:20000/udp" "RTP range"
    
    # Allow OpenSIPS MI interface (for control panel)
    add_ufw_rule_if_missing "8888/tcp" "OpenSIPS MI HTTP"
    
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

enable_services() {
    log_info "Enabling services..."
    
    # Enable OpenSIPS
    systemctl enable opensips || {
        log_error "Failed to enable OpenSIPS service"
        exit 1
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
    create_user
    create_directories
    setup_helper_scripts
    configure_firewall
    
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
    echo
}

# Run main function
main "$@"
