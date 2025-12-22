#!/bin/bash
#
# Kamailio SIP Edge Router Installation Script
# Installs and configures Kamailio with SQLite routing database and Litestream replication
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
KAMAILIO_USER="kamailio"
KAMAILIO_GROUP="kamailio"
KAMAILIO_DIR="/etc/kamailio"
KAMAILIO_DATA_DIR="/var/lib/kamailio"
KAMAILIO_LOG_DIR="/var/log/kamailio"
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
        kamailio \
        kamailio-mysql-modules \
        kamailio-sqlite-modules \
        kamailio-tls-modules \
        sqlite3 \
        curl \
        wget \
        ufw \
        jq \
        || {
            log_error "Failed to install dependencies"
            exit 1
        }
    
    log_success "Dependencies installed"
}

install_litestream() {
    log_info "Installing Litestream..."
    
    # Check if already installed
    if command -v litestream &> /dev/null; then
        LITESTREAM_VERSION=$(litestream version | head -n1)
        log_info "Litestream already installed: ${LITESTREAM_VERSION}"
        return
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
    wget -q "https://github.com/benbjohnson/litestream/releases/download/v${LITESTREAM_VERSION}/litestream-v${LITESTREAM_VERSION}-linux-${ARCH}.tar.gz" || {
        log_error "Failed to download Litestream"
        exit 1
    }
    
    tar -xzf "litestream-v${LITESTREAM_VERSION}-linux-${ARCH}.tar.gz"
    mv litestream /usr/local/bin/
    chmod +x /usr/local/bin/litestream
    rm -f "litestream-v${LITESTREAM_VERSION}-linux-${ARCH}.tar.gz"
    
    # Verify installation
    if command -v litestream &> /dev/null; then
        log_success "Litestream installed: $(litestream version | head -n1)"
    else
        log_error "Litestream installation failed"
        exit 1
    fi
}

create_user() {
    log_info "Creating kamailio user and group..."
    
    if id "$KAMAILIO_USER" &>/dev/null; then
        log_info "User ${KAMAILIO_USER} already exists"
    else
        useradd -r -s /bin/false -d /var/run/kamailio -c "Kamailio SIP Server" "$KAMAILIO_USER" || {
            log_error "Failed to create kamailio user"
            exit 1
        }
        log_success "Created user ${KAMAILIO_USER}"
    fi
}

create_directories() {
    log_info "Creating directories..."
    
    mkdir -p "$KAMAILIO_DIR"
    mkdir -p "$KAMAILIO_DATA_DIR"
    mkdir -p "$KAMAILIO_LOG_DIR"
    mkdir -p /var/run/kamailio
    
    chown -R "${KAMAILIO_USER}:${KAMAILIO_GROUP}" "$KAMAILIO_DATA_DIR"
    chown -R "${KAMAILIO_USER}:${KAMAILIO_GROUP}" "$KAMAILIO_LOG_DIR"
    chown -R "${KAMAILIO_USER}:${KAMAILIO_GROUP}" /var/run/kamailio
    
    log_success "Directories created"
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
    
    # Allow RTP range (for endpoints, not handled by Kamailio but good to document)
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
# Litestream configuration for Kamailio routing database
# Generated by install.sh on $(date)

dbs:
  - path: ${KAMAILIO_DATA_DIR}/routing.db
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
    
    chmod 600 "$LITESTREAM_CONFIG"
    chown root:root "$LITESTREAM_CONFIG"
    
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
Description=Litestream replication service for Kamailio routing database
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=${KAMAILIO_USER}
ExecStart=/usr/local/bin/litestream replicate -config ${LITESTREAM_CONFIG}
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

create_kamailio_config() {
    log_info "Creating Kamailio configuration..."
    
    KAMAILIO_CFG="${KAMAILIO_DIR}/kamailio.cfg"
    
    if [[ -f "$KAMAILIO_CFG" ]]; then
        log_warn "Kamailio config already exists at ${KAMAILIO_CFG}"
        read -p "Backup existing config and create new? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping Kamailio config creation"
            return
        fi
        mv "$KAMAILIO_CFG" "${KAMAILIO_CFG}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Copy template if it exists, otherwise create default
    if [[ -f "${CONFIG_DIR}/kamailio.cfg.template" ]]; then
        cp "${CONFIG_DIR}/kamailio.cfg.template" "$KAMAILIO_CFG"
        log_info "Using template from ${CONFIG_DIR}/kamailio.cfg.template"
    else
        # Create default config from documentation
        cat > "$KAMAILIO_CFG" <<'KAMAILIO_EOF'
#!KAMAILIO

####### Global Parameters #########

debug=2
log_stderror=no
fork=yes
children=4

listen=udp:0.0.0.0:5060

####### Modules ########

loadmodule "sl.so"
loadmodule "tm.so"
loadmodule "rr.so"
loadmodule "pv.so"
loadmodule "xlog.so"
loadmodule "siputils.so"
loadmodule "maxfwd.so"
loadmodule "textops.so"
loadmodule "sanity.so"
loadmodule "dispatcher.so"
loadmodule "sqlops.so"
loadmodule "db_sqlite.so"

####### Module Parameters ########

# --- SQLite routing database ---
modparam("sqlops", "sqlcon",
    "cb=>sqlite:///var/lib/kamailio/routing.db")

# --- Dispatcher (health checks via SIP OPTIONS) ---
modparam("dispatcher", "db_url",
    "sqlite:///var/lib/kamailio/routing.db")

modparam("dispatcher", "ds_ping_method", "OPTIONS")
modparam("dispatcher", "ds_ping_interval", 30)
modparam("dispatcher", "ds_probing_threshold", 2)
modparam("dispatcher", "ds_inactive_threshold", 2)
modparam("dispatcher", "ds_ping_reply_codes", "200")

# --- Transaction timers ---
modparam("tm", "fr_timer", 5)
modparam("tm", "fr_inv_timer", 30)

####### Routing Logic ########

request_route {

    # ---- Basic hygiene ----
    if (!mf_process_maxfwd_header("10")) {
        sl_send_reply("483", "Too Many Hops");
        exit;
    }

    if (!sanity_check("1511", "7")) {
        xlog("L_WARN", "Malformed SIP from $si\n");
        exit;
    }

    # ---- Drop known scanners ----
    if ($ua =~ "(?i)sipvicious|friendly-scanner|sipcli|nmap") {
        exit;
    }

    # ---- In-dialog requests ----
    if (has_totag()) {
        route(WITHINDLG);
        exit;
    }

    # ---- Allowed methods only ----
    if (!is_method("REGISTER|INVITE|ACK|BYE|CANCEL|OPTIONS")) {
        sl_send_reply("405", "Method Not Allowed");
        exit;
    }

    route(DOMAIN_CHECK);
}

####### Domain validation / door-knocker protection ########

route[DOMAIN_CHECK] {

    $var(domain) = $rd;

    if ($var(domain) == "") {
        exit;
    }

    # Optional extra hardening: domain consistency
    if ($rd != $td) {
        xlog("L_WARN",
             "R-URI / To mismatch domain=$rd src=$si\n");
        exit;
    }

    # Lookup dispatcher set for this domain
    if (!sql_query("cb",
        "SELECT dispatcher_setid \
         FROM sip_domains \
         WHERE domain='$var(domain)' AND enabled=1")) {

        xlog("L_NOTICE",
             "Door-knock blocked: domain=$var(domain) src=$si\n");
        exit;
    }

    sql_result("cb", "dispatcher_setid", "$var(setid)");

    route(TO_DISPATCHER);
}

####### Health-aware routing ########

route[TO_DISPATCHER] {

    # Select a healthy Asterisk from the dispatcher set
    if (!ds_select_dst($var(setid), "4")) {
        xlog("L_ERR",
             "No healthy Asterisk nodes for domain=$rd\n");
        sl_send_reply("503", "Service Unavailable");
        exit;
    }

    record_route();

    if (!t_relay()) {
        sl_reply_error();
    }

    exit;
}

####### In-dialog handling ########

route[WITHINDLG] {

    if (loose_route()) {
        route(RELAY);
        exit;
    }

    sl_send_reply("404", "Not Here");
    exit;
}

route[RELAY] {
    if (!t_relay()) {
        sl_reply_error();
    }
    exit;
}

####### Dispatcher events (visibility) ########

event_route[dispatcher:dst-up] {
    xlog("L_INFO", "Asterisk UP: $du\n");
}

event_route[dispatcher:dst-down] {
    xlog("L_WARN", "Asterisk DOWN: $du\n");
}
KAMAILIO_EOF
        log_info "Created default Kamailio configuration"
    fi
    
    # Update database path if needed
    sed -i "s|/var/lib/kamailio/routing.db|${KAMAILIO_DATA_DIR}/routing.db|g" "$KAMAILIO_CFG"
    
    log_success "Kamailio configuration created at ${KAMAILIO_CFG}"
}

initialize_database() {
    if [[ "$SKIP_DB" == true ]]; then
        log_info "Skipping database initialization"
        return
    fi
    
    log_info "Initializing SQLite database..."
    
    DB_PATH="${KAMAILIO_DATA_DIR}/routing.db"
    
    if [[ -f "$DB_PATH" ]]; then
        log_warn "Database already exists at ${DB_PATH}"
        read -p "Reinitialize database? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping database initialization"
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

-- Example data (replace with your actual data)
-- INSERT INTO sip_domains (domain, dispatcher_setid, enabled, comment) 
-- VALUES ('example.com', 10, 1, 'Example tenant');

-- INSERT INTO dispatcher (setid, destination, flags, priority) 
-- VALUES (10, 'sip:10.0.1.10:5060', 0, 0);
EOF
    
    chown "${KAMAILIO_USER}:${KAMAILIO_GROUP}" "$DB_PATH"
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
    
    # Enable Kamailio
    systemctl enable kamailio || {
        log_error "Failed to enable Kamailio service"
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
    
    # Start Kamailio
    systemctl start kamailio || {
        log_error "Failed to start Kamailio"
        exit 1
    }
    
    sleep 2
    
    # Check Kamailio status
    if systemctl is-active --quiet kamailio; then
        log_success "Kamailio started"
    else
        log_error "Kamailio failed to start. Check logs: journalctl -u kamailio"
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
    if [[ -f "${KAMAILIO_DATA_DIR}/routing.db" ]]; then
        echo -e "${GREEN}✓${NC} Database exists: ${KAMAILIO_DATA_DIR}/routing.db"
        DB_SIZE=$(du -h "${KAMAILIO_DATA_DIR}/routing.db" | cut -f1)
        echo -e "  Size: ${DB_SIZE}"
    else
        echo -e "${RED}✗${NC} Database not found"
    fi
    
    # Check Kamailio
    if command -v kamailio &> /dev/null; then
        echo -e "${GREEN}✓${NC} Kamailio installed: $(kamailio -V 2>&1 | head -n1)"
    else
        echo -e "${RED}✗${NC} Kamailio not found"
    fi
    
    # Check Kamailio service
    if systemctl is-enabled --quiet kamailio 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Kamailio service enabled"
    else
        echo -e "${YELLOW}⚠${NC} Kamailio service not enabled"
    fi
    
    if systemctl is-active --quiet kamailio 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Kamailio service running"
    else
        echo -e "${RED}✗${NC} Kamailio service not running"
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
    echo "   sqlite3 ${KAMAILIO_DATA_DIR}/routing.db"
    echo
    echo "2. Check service status:"
    echo "   systemctl status litestream"
    echo "   systemctl status kamailio"
    echo
    echo "3. View logs:"
    echo "   journalctl -u litestream -f"
    echo "   journalctl -u kamailio -f"
    echo
    echo "4. Test SIP connectivity:"
    echo "   sip_client -s sip:your-domain.com -u test"
    echo
}

# Main installation flow
main() {
    echo
    echo "=========================================="
    echo "Kamailio SIP Edge Router Installation"
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
    configure_firewall
    create_litestream_config
    create_litestream_service
    create_kamailio_config
    initialize_database
    enable_services
    start_services
    verify_installation
    
    echo
    log_success "Installation complete!"
    echo
    log_info "Configuration files:"
    echo "  - Kamailio: ${KAMAILIO_DIR}/kamailio.cfg"
    echo "  - Litestream: ${LITESTREAM_CONFIG}"
    echo "  - Database: ${KAMAILIO_DATA_DIR}/routing.db"
    echo
}

# Run main function
main "$@"
