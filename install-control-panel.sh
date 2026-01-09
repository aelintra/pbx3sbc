#!/bin/bash
#
# OpenSIPS Control Panel Installation Script
# Installs and configures the OpenSIPS Control Panel (OCP)
#
# Usage: sudo ./install-control-panel.sh [--db-password <PASSWORD>] [--skip-firewall] [--fork-repo <USERNAME/REPO>]
#
# Options:
#   --db-password <PASSWORD>   MySQL database password (will prompt if not provided)
#   --skip-firewall            Skip firewall configuration
#   --fork-repo <REPO>         Use patched fork (e.g., "username/opensips-cp" or full GitHub URL)
#
# Example:
#   sudo ./install-control-panel.sh --db-password mypass --fork-repo myuser/opensips-cp
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
OCP_VERSION="9.3.5"
OCP_TAG="v9.3.5-pbx3sbc"  # Use forked version with patches
OCP_WEB_ROOT="/var/www/opensips-cp"
OCP_CONFIG_DIR="${OCP_WEB_ROOT}/config"
OCP_WEB_DIR="${OCP_WEB_ROOT}/web"
APACHE_SITES_DIR="/etc/apache2/sites-available"
APACHE_SITES_ENABLED="/etc/apache2/sites-enabled"

# Fork repository (set this to your GitHub fork)
# Format: "username/repo" or full URL
OCP_FORK_REPO="${OCP_FORK_REPO:-}"  # e.g., "yourusername/opensips-cp"

# Database configuration (defaults, can be overridden)
DB_NAME="${DB_NAME:-opensips}"
DB_USER="${DB_USER:-opensips}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-3306}"
DB_PASSWORD=""
SKIP_FIREWALL=false

    # Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --db-password)
            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}Error: --db-password requires a password${NC}"
                exit 1
            fi
            DB_PASSWORD="$2"
            shift 2
            ;;
        --skip-firewall)
            SKIP_FIREWALL=true
            shift
            ;;
        --fork-repo)
            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}Error: --fork-repo requires a repository (username/repo or URL)${NC}"
                exit 1
            fi
            OCP_FORK_REPO="$2"
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

check_database() {
    log_info "Checking database connection..."
    
    if [[ -z "$DB_PASSWORD" ]]; then
        echo
        read -sp "Enter MySQL database password for user '${DB_USER}': " DB_PASSWORD
        echo
        if [[ -z "$DB_PASSWORD" ]]; then
            log_error "Database password cannot be empty"
            exit 1
        fi
    fi
    
    # Test database connection
    if mysql -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" -P "$DB_PORT" -e "USE ${DB_NAME};" 2>/dev/null; then
        log_success "Database connection successful"
    else
        log_error "Cannot connect to MySQL database"
        log_error "Please ensure OpenSIPS is installed and database is accessible"
        exit 1
    fi
    
    # Check if domain table exists
    if mysql -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" -P "$DB_PORT" "$DB_NAME" -e "DESCRIBE domain;" 2>/dev/null | grep -q "setid"; then
        log_success "Domain table with setid column found"
    else
        log_warn "Domain table setid column not found - ensure OpenSIPS is installed first"
        log_warn "The control panel requires the setid column in the domain table"
    fi
}

install_dependencies() {
    log_info "Installing Apache and PHP..."
    
    # Update package lists
    apt-get update -qq
    
    # Install Apache
    apt-get install -y apache2 || {
        log_error "Failed to install Apache"
        exit 1
    }
    
    # Install PHP and required extensions
    apt-get install -y \
        php \
        php-mysql \
        php-xml \
        php-json \
        php-curl \
        php-mbstring \
        php-gd \
        unzip \
        wget \
        || {
        log_error "Failed to install PHP and extensions"
        exit 1
    }
    
    log_success "Apache and PHP installed"
}

download_control_panel() {
    log_info "Downloading OpenSIPS Control Panel ${OCP_VERSION}..."
    
    # Create web root directory
    mkdir -p "$OCP_WEB_ROOT"
    
    # Check if control panel is already installed (idempotency check)
    if [[ -d "$OCP_WEB_DIR" ]] && [[ -f "${OCP_CONFIG_DIR}/db.inc.php" ]] && [[ -f "${OCP_WEB_DIR}/index.php" ]]; then
        log_info "Control panel files already exist at ${OCP_WEB_ROOT}"
        log_info "Skipping download and installation (idempotent)"
        return 0
    fi
    
    # Determine download URL (fork if specified, otherwise upstream)
    if [[ -n "$OCP_FORK_REPO" ]]; then
        # Extract username/repo from fork URL if full URL provided
        FORK_REPO=$(echo "$OCP_FORK_REPO" | sed 's|https://github.com/||' | sed 's|\.git$||')
        DOWNLOAD_URL="https://github.com/${FORK_REPO}/archive/refs/tags/${OCP_TAG}.zip"
        log_info "Using forked repository: ${FORK_REPO}"
    else
        # Use upstream repository (original, unpatched version)
        # Use master branch as tag 9.3.5 doesn't exist
        DOWNLOAD_URL="https://github.com/OpenSIPS/opensips-cp/archive/refs/heads/master.zip"
        log_warn "Using upstream repository (no patches applied)"
        log_warn "Set OCP_FORK_REPO environment variable to use patched fork"
    fi
    
    TEMP_ZIP="/tmp/opensips-cp-${OCP_VERSION}.zip"
    
    log_info "Downloading from: ${DOWNLOAD_URL}"
    if wget -q -O "$TEMP_ZIP" "$DOWNLOAD_URL"; then
        log_success "Downloaded control panel"
    else
        log_error "Failed to download control panel"
        exit 1
    fi
    
    # Extract to temporary location
    TEMP_EXTRACT="/tmp/opensips-cp-extract"
    rm -rf "$TEMP_EXTRACT"
    mkdir -p "$TEMP_EXTRACT"
    
    log_info "Extracting control panel..."
    if unzip -q "$TEMP_ZIP" -d "$TEMP_EXTRACT"; then
        log_success "Extracted control panel"
    else
        log_error "Failed to extract control panel"
        exit 1
    fi
    
    # Find the extracted directory (should be opensips-cp-${OCP_VERSION})
    EXTRACTED_DIR=$(find "$TEMP_EXTRACT" -maxdepth 1 -type d -name "opensips-cp-*" | head -1)
    
    if [[ -z "$EXTRACTED_DIR" ]] || [[ ! -d "$EXTRACTED_DIR" ]]; then
        log_error "Could not find extracted control panel directory"
        exit 1
    fi
    
    # Copy files to web root
    log_info "Installing control panel files..."
    cp -r "${EXTRACTED_DIR}"/* "$OCP_WEB_ROOT/"
    
    # Clean up
    rm -rf "$TEMP_EXTRACT" "$TEMP_ZIP"
    
    log_success "Control panel files installed to ${OCP_WEB_ROOT}"
}

configure_database() {
    log_info "Configuring control panel database connection..."
    
    # Ensure config directory exists
    mkdir -p "$OCP_CONFIG_DIR"
    
    DB_CONFIG_FILE="${OCP_CONFIG_DIR}/db.inc.php"
    
    # Backup original config only if it exists and backup doesn't exist (idempotency)
    if [[ -f "$DB_CONFIG_FILE" ]] && [[ ! -f "${DB_CONFIG_FILE}.backup" ]]; then
        cp "$DB_CONFIG_FILE" "${DB_CONFIG_FILE}.backup"
        log_info "Backed up original database config"
    fi
    
    # Update database configuration
    cat > "$DB_CONFIG_FILE" <<EOF
<?php
if (!isset(\$config)) {
    \$config = new stdClass();
}

\$config->db_driver = "mysql";
\$config->db_host = "${DB_HOST}";
\$config->db_port = "${DB_PORT}";
\$config->db_user = "${DB_USER}";
\$config->db_pass = "${DB_PASSWORD}";
\$config->db_name = "${DB_NAME}";
?>
EOF
    
    # Set proper permissions
    chown www-data:www-data "$DB_CONFIG_FILE"
    chmod 640 "$DB_CONFIG_FILE"
    
    log_success "Database configuration updated"
}

configure_apache() {
    log_info "Configuring Apache virtual host..."
    
    # Enable required Apache modules
    a2enmod rewrite headers || true
    
    # Create virtual host configuration
    VHOST_FILE="${APACHE_SITES_DIR}/opensips-cp.conf"
    
    cat > "$VHOST_FILE" <<EOF
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot ${OCP_WEB_DIR}
    
    <Directory ${OCP_WEB_DIR}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/opensips-cp-error.log
    CustomLog \${APACHE_LOG_DIR}/opensips-cp-access.log combined
</VirtualHost>
EOF
    
    # Enable the site
    a2ensite opensips-cp.conf || true
    
    # Disable default site if it exists
    a2dissite 000-default.conf 2>/dev/null || true
    
    # Set proper ownership
    chown -R www-data:www-data "$OCP_WEB_ROOT"
    
    # Test Apache configuration
    if apache2ctl configtest >/dev/null 2>&1; then
        log_success "Apache configuration valid"
        systemctl restart apache2 || {
            log_error "Failed to restart Apache"
            exit 1
        }
        log_success "Apache restarted"
    else
        log_error "Apache configuration test failed"
        apache2ctl configtest
        exit 1
    fi
}

configure_control_panel_database() {
    log_info "Configuring control panel database tables..."
    
    # Check if control panel tables exist (they are created by the web installation wizard)
    if ! mysql -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" -P "$DB_PORT" "$DB_NAME" -e "DESCRIBE ocp_boxes_config;" &>/dev/null; then
        log_warn "Control panel database tables do not exist yet"
        log_warn "Please access http://$(hostname -I | awk '{print $1}')/ and complete the installation wizard first"
        log_warn "After the wizard completes, re-run this script to configure the database entries"
        return 0
    fi
    
    # Configure ocp_boxes_config (OpenSIPS instance)
    mysql -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" -P "$DB_PORT" "$DB_NAME" <<EOF
INSERT INTO ocp_boxes_config (id, name, \`desc\`, mi_conn)
VALUES (1, 'opensips-server', 'OpenSIPS Server', 'json:127.0.0.1:8888/mi')
ON DUPLICATE KEY UPDATE 
    mi_conn='json:127.0.0.1:8888/mi',
    name='opensips-server',
    \`desc\`='OpenSIPS Server';
EOF
    
    # Configure ocp_tools_config (domain tool)
    mysql -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" -P "$DB_PORT" "$DB_NAME" <<EOF
INSERT INTO ocp_tools_config (module, param, value, box_id) 
VALUES ('domains', 'table_domains', 'domain', 1) 
ON DUPLICATE KEY UPDATE value='domain';
EOF
    
    # Ensure domain table version is set (required for domain module MI commands)
    mysql -u "$DB_USER" -p"$DB_PASSWORD" -h "$DB_HOST" -P "$DB_PORT" "$DB_NAME" <<EOF
INSERT INTO version (table_name, table_version) 
VALUES ('domain', 4) 
ON DUPLICATE KEY UPDATE table_version=4;
EOF
    
    log_success "Control panel database tables configured"
}

apply_domain_tool_fixes() {
    log_info "Applying domain tool patches from control-panel-patched/..."
    
    # Get the script directory to find control-panel-patched relative to script location
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PATCHED_DIR="${SCRIPT_DIR}/control-panel-patched"
    
    if [[ ! -d "$PATCHED_DIR" ]]; then
        log_error "Patched files directory not found: ${PATCHED_DIR}"
        log_error "Please ensure control-panel-patched/ directory exists in the repository"
        exit 1
    fi
    
    # Ensure target directories exist (idempotency: mkdir -p is safe to run multiple times)
    mkdir -p "${OCP_WEB_ROOT}/web/tools/system/domains/template"
    
    # Copy patched domain tool files (idempotent: cp overwrites, same result each time)
    if [[ -f "${PATCHED_DIR}/web/tools/system/domains/domains.php" ]]; then
        cp "${PATCHED_DIR}/web/tools/system/domains/domains.php" "${OCP_WEB_ROOT}/web/tools/system/domains/domains.php"
        chown www-data:www-data "${OCP_WEB_ROOT}/web/tools/system/domains/domains.php"
        log_info "Applied patched domains.php"
    else
        log_warn "Patched domains.php not found, skipping..."
    fi
    
    if [[ -f "${PATCHED_DIR}/web/tools/system/domains/template/domains.main.php" ]]; then
        cp "${PATCHED_DIR}/web/tools/system/domains/template/domains.main.php" "${OCP_WEB_ROOT}/web/tools/system/domains/template/domains.main.php"
        chown www-data:www-data "${OCP_WEB_ROOT}/web/tools/system/domains/template/domains.main.php"
        log_info "Applied patched domains.main.php"
    else
        log_warn "Patched domains.main.php not found, skipping..."
    fi
    
    if [[ -f "${PATCHED_DIR}/web/tools/system/domains/template/domains.form.php" ]]; then
        cp "${PATCHED_DIR}/web/tools/system/domains/template/domains.form.php" "${OCP_WEB_ROOT}/web/tools/system/domains/template/domains.form.php"
        chown www-data:www-data "${OCP_WEB_ROOT}/web/tools/system/domains/template/domains.form.php"
        log_info "Applied patched domains.form.php"
    else
        log_warn "Patched domains.form.php not found, skipping..."
    fi
    
    # Copy patched config file (db.inc.php is already configured by configure_database, but we keep the patch structure)
    # Note: configure_database() already handles db.inc.php with the $config initialization fix
    
    log_success "Domain tool patches applied from control-panel-patched/"
}

configure_firewall() {
    if [[ "$SKIP_FIREWALL" == true ]]; then
        log_info "Skipping firewall configuration"
        return
    fi
    
    log_info "Configuring firewall..."
    
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
    
    # Enable UFW if not already enabled
    ufw --force enable || true
    
    # Allow HTTP/HTTPS
    add_ufw_rule_if_missing "80/tcp" "HTTP"
    add_ufw_rule_if_missing "443/tcp" "HTTPS"
    
    log_success "Firewall configured"
}

verify_installation() {
    log_info "Verifying installation..."
    
    echo
    echo "=== Installation Verification ==="
    echo
    
    # Check Apache
    if systemctl is-active --quiet apache2; then
        echo -e "${GREEN}✓${NC} Apache is running"
    else
        echo -e "${RED}✗${NC} Apache is not running"
    fi
    
    # Check PHP
    if command -v php &> /dev/null; then
        PHP_VERSION=$(php -v | head -n1)
        echo -e "${GREEN}✓${NC} PHP installed: ${PHP_VERSION}"
    else
        echo -e "${RED}✗${NC} PHP not found"
    fi
    
    # Check control panel files
    if [[ -d "$OCP_WEB_DIR" ]]; then
        echo -e "${GREEN}✓${NC} Control panel files installed"
    else
        echo -e "${RED}✗${NC} Control panel files not found"
    fi
    
    # Check database config
    if [[ -f "${OCP_CONFIG_DIR}/db.inc.php" ]]; then
        echo -e "${GREEN}✓${NC} Database configuration file exists"
    else
        echo -e "${RED}✗${NC} Database configuration file not found"
    fi
    
    echo
    echo "=== Next Steps ==="
    echo
    echo "1. Access the control panel at: http://$(hostname -I | awk '{print $1}')"
    echo "   Default credentials: admin / opensips"
    echo
    echo "2. Verify domain tool shows ID and Set ID columns"
    echo
    echo "3. Check logs if issues occur:"
    echo "   tail -f /var/log/apache2/opensips-cp-error.log"
    echo "   journalctl -u apache2 -f"
    echo
}

# Main installation flow
main() {
    echo
    echo "=========================================="
    echo "OpenSIPS Control Panel Installation"
    echo "=========================================="
    echo
    
    check_root
    check_database
    install_dependencies
    download_control_panel
    configure_database
    configure_control_panel_database
    configure_apache
    apply_domain_tool_fixes
    configure_firewall
    verify_installation
    
    echo
    log_success "Control panel installation complete!"
    echo
    log_info "Control panel is available at: http://$(hostname -I | awk '{print $1}')"
    echo
}

# Run main function
main "$@"

