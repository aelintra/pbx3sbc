#!/bin/bash
#
# OpenSIPS SIP Edge Router Installation Script
# Installs and configures OpenSIPS with SQLite routing database and Litestream replication
#
# Usage: sudo ./install.sh [--skip-deps] [--skip-firewall] [--skip-db]
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
LITESTREAM_CONFIG="/etc/litestream.yml"
LITESTREAM_SERVICE="/etc/systemd/system/litestream.service"
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="${INSTALL_DIR}/scripts"
CONFIG_DIR="${INSTALL_DIR}/config"

# Flags
SKIP_DEPS=false
SKIP_FIREWALL=false
SKIP_DB=false

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
    
    log_info "Updating package lists..."
    apt-get update -qq
    
    log_info "Installing dependencies..."
    apt-get install -y \
        opensips \
        opensips-sqlite-modules \
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
    else
        log_success "Dependencies installed"
    fi
}

install_litestream() {
    log_info "Installing Litestream..."
    
    # Check if already installed
    if command -v litestream &> /dev/null; then
        LITESTREAM_VERSION=$(litestream version | head -n1)
        log_info "Litestream already installed: ${LITESTREAM_VERSION}"
        return
    fi
    
    # Check if jq is available (needed for version detection)
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed. Install it manually or run without --skip-deps"
        exit 1
    fi
    
    # Detect architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        *)
            log_error "Unsupported architecture: ${ARCH}"
            exit 1
            ;;
    esac

    log_info "Installing Litestream for architecture ${ARCH}..."
    
    # Get latest version
    log_info "Fetching latest Litestream version..."
    LITESTREAM_VERSION=$(curl -s https://api.github.com/repos/benbjohnson/litestream/releases/latest | jq -r '.tag_name' | sed 's/v//')
    
    if [[ -z "$LITESTREAM_VERSION" ]]; then
        log_error "Failed to fetch Litestream version"
        exit 1
    fi
    
    log_info "Installing Litestream ${LITESTREAM_VERSION}..."
    
    # Download and install
    cd /tmp
    DEB_FILE="litestream-${LITESTREAM_VERSION}-linux-${ARCH}.deb"
    wget -q "https://github.com/benbjohnson/litestream/releases/download/v${LITESTREAM_VERSION}/${DEB_FILE}" || {
        log_error "Failed to download Litestream"
        exit 1
    }

    # Install the .deb package
    log_info "Installing ${DEB_FILE}..."
    dpkg -i "${DEB_FILE}" || {
        log_error "Failed to install Litestream package"
        rm -f "${DEB_FILE}"
        exit 1
    }
    
    # Clean up downloaded file
    rm -f "${DEB_FILE}"
    
    # Verify installation
    if command -v litestream &> /dev/null; then
        log_success "Litestream installed: $(litestream version | head -n1)"
    else
        log_error "Litestream installation failed"
        exit 1
    fi
}

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

create_litestream_config() {
    log_info "Creating Litestream configuration..."
    
    if [[ -f "$LITESTREAM_CONFIG" ]]; then
        log_warn "Litestream config already exists at ${LITESTREAM_CONFIG}"
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping Litestream config creation"
            return
        fi
    fi
    
    # Prompt for S3/MinIO configuration
    echo
    log_info "Litestream S3/MinIO Configuration"
    echo "======================================"
    read -p "Replica type (s3/minio) [s3]: " REPLICA_TYPE
    REPLICA_TYPE=${REPLICA_TYPE:-s3}
    
    read -p "Bucket name: " BUCKET_NAME
    if [[ -z "$BUCKET_NAME" ]]; then
        log_error "Bucket name is required"
        exit 1
    fi
    
    read -p "Path in bucket [routing.db]: " BUCKET_PATH
    BUCKET_PATH=${BUCKET_PATH:-routing.db}
    
    if [[ "$REPLICA_TYPE" == "minio" ]]; then
        read -p "MinIO endpoint (e.g., http://minio:9000): " ENDPOINT
        read -p "Access Key ID: " ACCESS_KEY
        read -p "Secret Access Key: " SECRET_KEY
        read -p "Skip TLS verify? (y/N): " -n 1 -r
        echo
        SKIP_VERIFY="false"
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            SKIP_VERIFY="true"
        fi
    else
        read -p "AWS Region [us-east-1]: " REGION
        REGION=${REGION:-us-east-1}
        read -p "Use IAM role? (Y/n): " -n 1 -r
        echo
        USE_IAM=true
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            USE_IAM=false
            read -p "Access Key ID: " ACCESS_KEY
            read -p "Secret Access Key: " SECRET_KEY
        fi
    fi
    
    # Create config file
    cat > "$LITESTREAM_CONFIG" <<EOF
# Litestream configuration for OpenSIPS routing database
# Generated by install.sh on $(date)

dbs:
  - path: ${OPENSIPS_DATA_DIR}/routing.db
    replicas:
      - type: s3
        bucket: ${BUCKET_NAME}
        path: ${BUCKET_PATH}
EOF
    
    if [[ "$REPLICA_TYPE" == "minio" ]]; then
        cat >> "$LITESTREAM_CONFIG" <<EOF
        endpoint: ${ENDPOINT}
        access-key-id: ${ACCESS_KEY}
        secret-access-key: ${SECRET_KEY}
        skip-verify: ${SKIP_VERIFY}
EOF
    else
        cat >> "$LITESTREAM_CONFIG" <<EOF
        region: ${REGION}
EOF
        if [[ "$USE_IAM" == false ]]; then
            cat >> "$LITESTREAM_CONFIG" <<EOF
        access-key-id: ${ACCESS_KEY}
        secret-access-key: ${SECRET_KEY}
EOF
        fi
    fi
    
    chmod 640 "$LITESTREAM_CONFIG"
    chown root:${OPENSIPS_GROUP} "$LITESTREAM_CONFIG"
    
    log_success "Litestream configuration created at ${LITESTREAM_CONFIG}"
    
    if [[ "$REPLICA_TYPE" == "s3" && "$USE_IAM" == true ]]; then
        log_info "Using IAM role for S3 access. Ensure EC2 instance has appropriate IAM role."
    else
        log_warn "Credentials stored in config file. Consider using IAM roles or environment variables."
    fi
}

create_litestream_service() {
    log_info "Creating Litestream systemd service..."
    
    cat > "$LITESTREAM_SERVICE" <<EOF
[Unit]
Description=Litestream replication service for OpenSIPS routing database
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=${OPENSIPS_USER}
ExecStart=/usr/bin/litestream replicate -config ${LITESTREAM_CONFIG}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    log_success "Litestream service created"
}

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

-- Dispatcher destinations table
CREATE TABLE dispatcher (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    setid INTEGER NOT NULL,
    destination TEXT NOT NULL,
    flags INTEGER DEFAULT 0,
    priority INTEGER DEFAULT 0,
    attrs TEXT
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
INSERT INTO version (table_name, table_version) VALUES ('dispatcher', 4);

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
    
    # Enable Litestream
    systemctl enable litestream || {
        log_error "Failed to enable Litestream service"
        exit 1
    }
    
    # Enable OpenSIPS
    systemctl enable opensips || {
        log_error "Failed to enable OpenSIPS service"
        exit 1
    }
    
    log_success "Services enabled"
}

start_services() {
    log_info "Starting services..."
    
    # Start Litestream
    systemctl start litestream || {
        log_error "Failed to start Litestream"
        exit 1
    }
    
    sleep 2
    
    # Check Litestream status
    if systemctl is-active --quiet litestream; then
        log_success "Litestream started"
    else
        log_error "Litestream failed to start. Check logs: journalctl -u litestream"
    fi
    
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
    
    # Check Litestream
    if command -v litestream &> /dev/null; then
        echo -e "${GREEN}✓${NC} Litestream installed: $(litestream version | head -n1)"
    else
        echo -e "${RED}✗${NC} Litestream not found"
    fi
    
    # Check Litestream service
    if systemctl is-enabled --quiet litestream 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Litestream service enabled"
    else
        echo -e "${YELLOW}⚠${NC} Litestream service not enabled"
    fi
    
    if systemctl is-active --quiet litestream 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Litestream service running"
    else
        echo -e "${RED}✗${NC} Litestream service not running"
    fi
    
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
    
    # Check replication
    if systemctl is-active --quiet litestream 2>/dev/null; then
        echo
        echo "Litestream replication status:"
        litestream databases 2>/dev/null || echo "  (Check logs if replication not working)"
    fi
    
    echo
    echo "=== Next Steps ==="
    echo
    echo "1. Add domains and dispatcher entries to the database:"
    echo "   sqlite3 ${OPENSIPS_DATA_DIR}/routing.db"
    echo
    echo "2. Check service status:"
    echo "   systemctl status litestream"
    echo "   systemctl status opensips"
    echo
    echo "3. View logs:"
    echo "   journalctl -u litestream -f"
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
    install_litestream
    create_user
    create_directories
    setup_helper_scripts
    configure_firewall
    create_litestream_config
    create_litestream_service
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
    echo "  - Litestream: ${LITESTREAM_CONFIG}"
    echo "  - Database: ${OPENSIPS_DATA_DIR}/routing.db"
    echo
}

# Run main function
main "$@"
