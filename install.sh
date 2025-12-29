#!/bin/bash
#
# OpenSIPS SIP Edge Router Installation Script
# Installs and configures OpenSIPS with SQLite routing database
#
# Usage: sudo ./install.sh [--skip-deps] [--skip-firewall] [--skip-db] [--advertised-ip <IP>]
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
        log_error "Cannot detect OS version"
        exit 1
    fi
    
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        log_warn "This script is designed for Ubuntu. Proceeding anyway..."
    else
        log_info "Detected Ubuntu ${VERSION_ID}"
    fi
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
        # Detect OS and version for repository URL
        source /etc/os-release
        OS_CODENAME=""
        
        # Map Ubuntu/Debian versions to codenames
        if [[ "$ID" == "ubuntu" ]]; then
            case "$VERSION_ID" in
                "24.04") OS_CODENAME="noble" ;;
                "22.04") OS_CODENAME="jammy" ;;
                "20.04") OS_CODENAME="focal" ;;
                "18.04") OS_CODENAME="bionic" ;;
                *)
                    log_error "Unsupported Ubuntu version: ${VERSION_ID}"
                    log_error "Supported versions: 18.04, 20.04, 22.04, 24.04"
                    exit 1
                    ;;
            esac
        elif [[ "$ID" == "debian" ]]; then
            case "$VERSION_ID" in
                "12") OS_CODENAME="bookworm" ;;
                "11") OS_CODENAME="bullseye" ;;
                "10") OS_CODENAME="buster" ;;
                *)
                    log_error "Unsupported Debian version: ${VERSION_ID}"
                    log_error "Supported versions: 10, 11, 12"
                    exit 1
                    ;;
            esac
        else
            log_error "Unsupported OS: ${ID}"
            log_error "Supported OS: Ubuntu 18.04+, Debian 10+"
            exit 1
        fi
        
        log_info "Detected OS: ${ID} ${VERSION_ID} (${OS_CODENAME})"
        
        # Install prerequisites
        apt-get update -qq
        apt-get install -y curl gnupg2 ca-certificates || {
            log_error "Failed to install prerequisites for repository setup"
            exit 1
        }
        
        # Add OpenSIPS GPG key
        log_info "Adding OpenSIPS GPG key..."
        curl -fsSL https://apt.opensips.org/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/opensips.gpg || {
            log_error "Failed to add OpenSIPS GPG key"
            exit 1
        }
        
        # Add OpenSIPS repository
        log_info "Adding OpenSIPS repository for ${OS_CODENAME}..."
        echo "deb [signed-by=/usr/share/keyrings/opensips.gpg] https://apt.opensips.org ${OS_CODENAME} 3.6-releases" > /etc/apt/sources.list.d/opensips.list || {
            log_error "Failed to create OpenSIPS repository file"
            exit 1
        }
        
        log_success "OpenSIPS repository added successfully"
    else
        log_info "OpenSIPS repository already configured"
    fi
    
    log_info "Updating package lists..."
    apt-get update -qq
    
    log_info "Installing dependencies..."
    apt-get install -y \
        opensips \
        opensips-sqlite-module \
        libsqlite3-dev \
        sqlite3 \
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
        
        # Verify SQLite module is available
        if opensips -m 2>/dev/null | grep -q sqlite; then
            log_success "SQLite module is available"
        else
            log_warn "SQLite module not found - check OpenSIPS module installation"
        fi
    else
        log_error "OpenSIPS installation failed - opensips command not found"
        exit 1
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
    
    # Allow SSH (important!)
    ufw allow 22/tcp comment 'SSH'
    
    # Allow SIP
    ufw allow 5060/udp comment 'SIP UDP'
    ufw allow 5060/tcp comment 'SIP TCP'
    ufw allow 5061/tcp comment 'SIP TLS'
    
    # Allow RTP range (for endpoints, not handled by OpenSIPS but good to document)
    ufw allow 10000:20000/udp comment 'RTP range'
    
    log_success "Firewall configured"
    log_warn "Firewall rules applied. Ensure SSH access is working before disconnecting!"
}

# Litestream configuration removed - can be added back later

# Litestream service removed - can be added back later

create_opensips_config() {
    log_info "Creating OpenSIPS configuration..."
    
    OPENSIPS_CFG="${OPENSIPS_DIR}/opensips.cfg"
    
    if [[ -f "$OPENSIPS_CFG" ]]; then
        log_warn "OpenSIPS config already exists at ${OPENSIPS_CFG}"
        read -p "Backup existing config and create new? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping OpenSIPS config creation"
            return
        fi
        mv "$OPENSIPS_CFG" "${OPENSIPS_CFG}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Copy template - it must exist
    if [[ ! -f "${CONFIG_DIR}/opensips.cfg.template" ]]; then
        log_error "OpenSIPS template not found at ${CONFIG_DIR}/opensips.cfg.template"
        log_error "Please ensure the template file exists in the repository"
        return 1
    fi
    
    cp "${CONFIG_DIR}/opensips.cfg.template" "$OPENSIPS_CFG"
    log_success "Copied OpenSIPS config from template: ${CONFIG_DIR}/opensips.cfg.template"
    
    # Update database path if needed
    sed -i "s|/var/lib/opensips/routing.db|${OPENSIPS_DATA_DIR}/routing.db|g" "$OPENSIPS_CFG"
    
    # Update advertised_address if provided
    if [[ -n "$ADVERTISED_IP" ]]; then
        sed -i "s|advertised_address=\"CHANGE_ME\"|advertised_address=\"${ADVERTISED_IP}\"|g" "$OPENSIPS_CFG"
        log_success "Set advertised_address to ${ADVERTISED_IP}"
    else
        log_warn "advertised_address not set - you must manually update it in ${OPENSIPS_CFG}"
        log_warn "Set it to your server's public IP address for cloud deployments"
    fi
    
    log_success "OpenSIPS configuration created at ${OPENSIPS_CFG}"
}

initialize_database() {
    if [[ "$SKIP_DB" == true ]]; then
        log_info "Skipping database initialization"
        return
    fi
    
    log_info "Initializing SQLite database..."
    
    DB_PATH="${OPENSIPS_DATA_DIR}/routing.db"
    
    if [[ -f "$DB_PATH" ]]; then
        log_warn "Database already exists at ${DB_PATH}"
        read -p "Reinitialize database? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping full database reinitialization"
            # Still ensure endpoint_locations table exists and WAL mode is set (migration)
            log_info "Ensuring endpoint_locations table exists and WAL mode is enabled..."
            sqlite3 "$DB_PATH" <<MIGRATION_EOF
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA cache_size = -64000;
PRAGMA wal_autocheckpoint = 1000;

-- Endpoint locations table (for routing OPTIONS from Asterisk to endpoints)
CREATE TABLE IF NOT EXISTS endpoint_locations (
    aor TEXT PRIMARY KEY,
    contact_ip TEXT NOT NULL,
    contact_port TEXT NOT NULL,
    expires TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_endpoint_locations_expires ON endpoint_locations(expires);
MIGRATION_EOF
            log_success "Database migration complete"
            return
        fi
        rm -f "$DB_PATH" "${DB_PATH}-wal" "${DB_PATH}-shm"
    fi
    
    # Create database with schema
    sqlite3 "$DB_PATH" <<EOF
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA cache_size = -64000;
PRAGMA wal_autocheckpoint = 1000;

-- Version table (required by OpenSIPS modules)
CREATE TABLE version (
    table_name VARCHAR(32) PRIMARY KEY,
    table_version INTEGER DEFAULT 0 NOT NULL
);

-- Domain routing table
CREATE TABLE sip_domains (
    domain TEXT PRIMARY KEY,
    dispatcher_setid INTEGER NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    comment TEXT
);

CREATE INDEX idx_sip_domains_enabled ON sip_domains(enabled);

-- Dispatcher destinations table (OpenSIPS 3.6 version 9 schema)
-- Drop and recreate to ensure correct schema
DROP TABLE IF EXISTS dispatcher;
CREATE TABLE dispatcher (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    setid INTEGER DEFAULT 0 NOT NULL,
    destination TEXT DEFAULT '' NOT NULL,
    socket TEXT,
    state INTEGER DEFAULT 0 NOT NULL,
    probe_mode INTEGER DEFAULT 0 NOT NULL,
    weight TEXT DEFAULT '1' NOT NULL,
    priority INTEGER DEFAULT 0 NOT NULL,
    attrs TEXT,
    description TEXT
);

CREATE INDEX idx_dispatcher_setid ON dispatcher(setid);

-- Endpoint locations table (for routing OPTIONS from Asterisk to endpoints)
CREATE TABLE IF NOT EXISTS endpoint_locations (
    aor TEXT PRIMARY KEY,
    contact_ip TEXT NOT NULL,
    contact_port TEXT NOT NULL,
    expires TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_endpoint_locations_expires ON endpoint_locations(expires);

-- Initialize version table with dispatcher module version
-- OpenSIPS 3.6 expects version 9 for dispatcher table
INSERT INTO version (table_name, table_version) VALUES ('dispatcher', 9);

-- Example data (replace with your actual data)
-- INSERT INTO sip_domains (domain, dispatcher_setid, enabled, comment) 
-- VALUES ('example.com', 10, 1, 'Example tenant');

-- INSERT INTO dispatcher (setid, destination, flags, priority) 
-- VALUES (10, 'sip:10.0.1.10:5060', 0, 0);
EOF
    
    chown "${OPENSIPS_USER}:${OPENSIPS_GROUP}" "$DB_PATH"
    chmod 644 "$DB_PATH"
    
    log_success "Database initialized at ${DB_PATH}"
    log_info "Add your domains and dispatcher entries using sqlite3 or the provided scripts"
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
    
    # Check database
    if [[ -f "${OPENSIPS_DATA_DIR}/routing.db" ]]; then
        echo -e "${GREEN}✓${NC} Database exists: ${OPENSIPS_DATA_DIR}/routing.db"
        DB_SIZE=$(du -h "${OPENSIPS_DATA_DIR}/routing.db" | cut -f1)
        echo -e "  Size: ${DB_SIZE}"
    else
        echo -e "${RED}✗${NC} Database not found"
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
    echo "   sqlite3 ${OPENSIPS_DATA_DIR}/routing.db"
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
    
    log_info "Starting installation..."
    echo
    
    install_dependencies
    create_user
    create_directories
    setup_helper_scripts
    configure_firewall
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
    echo "  - Database: ${OPENSIPS_DATA_DIR}/routing.db"
    echo
}

# Run main function
main "$@"
