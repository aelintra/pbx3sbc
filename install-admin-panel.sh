#!/bin/bash
#
# OpenSIPS Admin Panel Installation Script
# Installs Laravel + Filament admin panel for OpenSIPS management
#
# Usage: sudo ./install-admin-panel.sh [--skip-deps] [--skip-db-config] [--install-path <PATH>] [--admin-email <EMAIL>]
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ADMIN_PANEL_DIR="${ADMIN_PANEL_DIR:-/var/www/admin-panel}"
ADMIN_PANEL_USER="${ADMIN_PANEL_USER:-www-data}"
ADMIN_PANEL_GROUP="${ADMIN_PANEL_GROUP:-www-data}"
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRED_FILE="/etc/opensips/.mysql_credentials"

# Flags
SKIP_DEPS=false
SKIP_DB_CONFIG=false
ADMIN_EMAIL=""
INSTALL_SHIELD=true

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-deps)
            SKIP_DEPS=true
            shift
            ;;
        --skip-db-config)
            SKIP_DB_CONFIG=true
            shift
            ;;
        --install-path)
            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}Error: --install-path requires a path${NC}"
                exit 1
            fi
            ADMIN_PANEL_DIR="$2"
            shift 2
            ;;
        --admin-email)
            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}Error: --admin-email requires an email address${NC}"
                exit 1
            fi
            ADMIN_EMAIL="$2"
            shift 2
            ;;
        --no-shield)
            INSTALL_SHIELD=false
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
        log_error "Cannot detect OS version (/etc/os-release not found)"
        exit 1
    fi
    
    source /etc/os-release
    
    # Require Ubuntu
    if [[ "$ID" != "ubuntu" ]]; then
        log_error "This script requires Ubuntu. Detected: ${ID}"
        exit 1
    fi
    
    log_success "Detected Ubuntu ${VERSION_ID}"
}

check_php_installed() {
    if command -v php &> /dev/null; then
        PHP_VERSION=$(php -v | head -n1 | cut -d' ' -f2 | cut -d'.' -f1,2)
        log_info "PHP is already installed: ${PHP_VERSION}"
        return 0
    else
        return 1
    fi
}

check_composer_installed() {
    if command -v composer &> /dev/null; then
        COMPOSER_VERSION=$(composer --version 2>&1 | head -n1 | cut -d' ' -f3 || echo "unknown")
        log_info "Composer is already installed: ${COMPOSER_VERSION}"
        return 0
    else
        return 1
    fi
}

install_php() {
    if [[ "$SKIP_DEPS" == true ]]; then
        log_info "Skipping PHP installation"
        if ! check_php_installed; then
            log_error "PHP is not installed and --skip-deps was specified"
            exit 1
        fi
        return
    fi
    
    if check_php_installed; then
        PHP_VERSION=$(php -v | head -n1 | cut -d' ' -f2 | cut -d'.' -f1,2)
        PHP_MAJOR=$(echo "$PHP_VERSION" | cut -d'.' -f1)
        PHP_MINOR=$(echo "$PHP_VERSION" | cut -d'.' -f2)
        
        # Check if PHP 8.1 or higher
        if [[ $PHP_MAJOR -ge 8 ]] && [[ $PHP_MINOR -ge 1 ]]; then
            log_info "PHP ${PHP_VERSION} is already installed and meets requirements"
            return
        else
            log_warn "PHP ${PHP_VERSION} is installed but may not meet requirements (need 8.1+)"
        fi
    fi
    
    log_info "Installing PHP 8.2 and required extensions..."
    
    # Add PHP repository (if not already added)
    if [[ ! -f /etc/apt/sources.list.d/php.list ]] && [[ ! -d /etc/apt/sources.list.d/php.list.d ]]; then
        log_info "Adding PHP repository..."
        apt-get install -y software-properties-common
        add-apt-repository -y ppa:ondrej/php
        apt-get update -qq
    else
        log_info "PHP repository already configured"
        apt-get update -qq
    fi
    
    # Install PHP and extensions
    apt-get install -y \
        php8.2 \
        php8.2-cli \
        php8.2-fpm \
        php8.2-mysql \
        php8.2-xml \
        php8.2-mbstring \
        php8.2-curl \
        php8.2-zip \
        php8.2-bcmath \
        php8.2-intl \
        || {
            log_error "Failed to install PHP and extensions"
            exit 1
        }
    
    # Verify installation
    if command -v php &> /dev/null; then
        PHP_VERSION=$(php -v | head -n1)
        log_success "PHP installed: ${PHP_VERSION}"
    else
        log_error "PHP installation failed - php command not found"
        exit 1
    fi
}

install_composer() {
    if [[ "$SKIP_DEPS" == true ]]; then
        log_info "Skipping Composer installation"
        if ! check_composer_installed; then
            log_error "Composer is not installed and --skip-deps was specified"
            exit 1
        fi
        return
    fi
    
    if check_composer_installed; then
        log_info "Composer is already installed"
        return
    fi
    
    log_info "Installing Composer..."
    
    # Download and install Composer
    cd /tmp
    curl -sS https://getcomposer.org/installer -o composer-installer.php
    php composer-installer.php --install-dir=/usr/local/bin --filename=composer
    rm composer-installer.php
    
    # Verify installation
    if command -v composer &> /dev/null; then
        COMPOSER_VERSION=$(composer --version 2>&1 | head -n1)
        log_success "Composer installed: ${COMPOSER_VERSION}"
    else
        log_error "Composer installation failed"
        exit 1
    fi
}

load_database_credentials() {
    if [[ -f "$CRED_FILE" ]]; then
        log_info "Loading database credentials from ${CRED_FILE}"
        source "$CRED_FILE"
        
        if [[ -z "${DB_NAME:-}" ]] || [[ -z "${DB_USER:-}" ]] || [[ -z "${DB_PASS:-}" ]]; then
            log_error "Database credentials file exists but is missing required fields"
            return 1
        fi
        
        log_success "Database credentials loaded"
        return 0
    else
        log_warn "Database credentials file not found: ${CRED_FILE}"
        log_info "You will be prompted for database credentials"
        return 1
    fi
}

get_database_credentials() {
    if [[ "$SKIP_DB_CONFIG" == true ]]; then
        log_info "Skipping database configuration"
        DB_NAME="opensips"
        DB_USER="opensips"
        DB_PASS=""
        return
    fi
    
    if load_database_credentials; then
        # Credentials loaded from file
        return
    fi
    
    # Prompt for credentials
    echo
    log_info "Database Configuration"
    echo "Connecting to OpenSIPS MySQL database..."
    echo
    
    # Try to get defaults from existing OpenSIPS config
    DB_NAME="opensips"
    DB_USER="opensips"
    
    read -p "Database name [${DB_NAME}]: " input_db_name
    DB_NAME="${input_db_name:-$DB_NAME}"
    
    read -p "Database user [${DB_USER}]: " input_db_user
    DB_USER="${input_db_user:-$DB_USER}"
    
    read -sp "Database password for '${DB_USER}': " DB_PASS
    echo
    
    if [[ -z "$DB_PASS" ]]; then
        log_error "Database password cannot be empty"
        exit 1
    fi
    
    # Test connection
    log_info "Testing database connection..."
    if mysql -u "$DB_USER" -p"$DB_PASS" -h localhost "$DB_NAME" -e "SELECT 1" &>/dev/null 2>&1; then
        log_success "Database connection successful"
    else
        log_error "Database connection failed. Please check credentials."
        exit 1
    fi
}

create_laravel_project() {
    if [[ -d "$ADMIN_PANEL_DIR" ]]; then
        if [[ -f "$ADMIN_PANEL_DIR/artisan" ]]; then
            log_info "Laravel project already exists at ${ADMIN_PANEL_DIR}"
            log_info "Skipping project creation (use --install-path to specify different location)"
            return
        else
            log_warn "Directory ${ADMIN_PANEL_DIR} exists but doesn't appear to be a Laravel project"
            read -p "Remove directory and create new project? [y/N]: " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -rf "$ADMIN_PANEL_DIR"
            else
                log_error "Cannot proceed - directory exists and is not empty"
                exit 1
            fi
        fi
    fi
    
    log_info "Creating Laravel project at ${ADMIN_PANEL_DIR}..."
    
    # Create parent directory if needed
    mkdir -p "$(dirname "$ADMIN_PANEL_DIR")"
    
    # Create Laravel project
    cd "$(dirname "$ADMIN_PANEL_DIR")"
    composer create-project laravel/laravel:^12.0 "$(basename "$ADMIN_PANEL_DIR")" --no-interaction --prefer-dist || {
        log_error "Failed to create Laravel project"
        exit 1
    }
    
    log_success "Laravel project created"
}

install_filament() {
    log_info "Installing Filament..."
    
    cd "$ADMIN_PANEL_DIR"
    
    # Install Filament
    composer require filament/filament:"^3.0" --no-interaction || {
        log_error "Failed to install Filament"
        exit 1
    }
    
    # Install Filament panel
    php artisan filament:install --panels --no-interaction || {
        log_error "Failed to install Filament panels"
        exit 1
    }
    
    log_success "Filament installed"
}

configure_database() {
    log_info "Configuring database connection..."
    
    cd "$ADMIN_PANEL_DIR"
    
    # Update .env file
    if [[ -f .env ]]; then
        # Escape password for sed (escape special characters)
        ESCAPED_PASS=$(printf '%s\n' "$DB_PASS" | sed 's/[[\.*^$()+?{|]/\\&/g')
        
        # Update database configuration (handle both commented and uncommented lines)
        sed -i "s/^DB_CONNECTION=.*/DB_CONNECTION=mysql/" .env
        sed -i "s/^#\?DB_HOST=.*/DB_HOST=127.0.0.1/" .env
        sed -i "s/^#\?DB_PORT=.*/DB_PORT=3306/" .env
        sed -i "s/^#\?DB_DATABASE=.*/DB_DATABASE=${DB_NAME}/" .env
        sed -i "s/^#\?DB_USERNAME=.*/DB_USERNAME=${DB_USER}/" .env
        sed -i "s/^#\?DB_PASSWORD=.*/DB_PASSWORD=${ESCAPED_PASS}/" .env
        
        log_success "Database configuration updated in .env"
    else
        log_error ".env file not found"
        exit 1
    fi
    
    # Test database connection
    log_info "Testing Laravel database connection..."
    if php artisan db:show &>/dev/null; then
        log_success "Database connection verified"
    else
        log_warn "Could not verify database connection (this may be normal if migrations haven't run)"
    fi
}

run_migrations() {
    log_info "Running database migrations..."
    
    cd "$ADMIN_PANEL_DIR"
    
    # Run migrations
    php artisan migrate --force || {
        log_error "Failed to run database migrations"
        exit 1
    }
    
    log_success "Database migrations completed"
}

install_shield() {
    if [[ "$INSTALL_SHIELD" != true ]]; then
        log_info "Skipping Filament Shield installation"
        return
    fi
    
    log_info "Installing Filament Shield (RBAC)..."
    
    cd "$ADMIN_PANEL_DIR"
    
    # Install Spatie Permission
    composer require spatie/laravel-permission --no-interaction || {
        log_error "Failed to install Spatie Laravel Permission"
        exit 1
    }
    
    # Install Filament Shield
    composer require bezhansalleh/filament-shield --no-interaction || {
        log_error "Failed to install Filament Shield"
        exit 1
    }
    
    # Publish Shield config
    php artisan vendor:publish --tag=filament-shield-config --no-interaction || {
        log_warn "Failed to publish Shield config (may already be published)"
    }
    
    # Run Shield install (panel name is 'admin' by default)
    php artisan shield:install admin --no-interaction || {
        log_error "Failed to install Shield"
        exit 1
    }
    
    log_success "Filament Shield installed"
}

create_admin_user() {
    log_info "Admin user creation..."
    
    cd "$ADMIN_PANEL_DIR"
    
    # Check if users table exists
    if ! php artisan db:show &>/dev/null; then
        log_info "Running migrations first..."
        run_migrations
    fi
    
    # Check if admin user already exists (check users table)
    USER_COUNT=$(php artisan tinker --execute="echo \App\Models\User::count();" 2>/dev/null | grep -oE '[0-9]+' | head -n1 || echo "0")
    if [[ "$USER_COUNT" -gt 0 ]]; then
        log_info "Users already exist in database (${USER_COUNT} user(s))"
        log_info "Skipping user creation (users can be created via web interface)"
        return
    fi
    
    # Note: make:filament-user requires HTTP context and doesn't work in CLI
    # Users must be created via the web interface after starting the server
    log_warn "Filament's make:filament-user command requires HTTP context"
    log_info "User creation will be skipped - create users via the web interface"
    log_info "After starting the server, visit /admin/register to create the first user"
}

set_permissions() {
    log_info "Setting file permissions..."
    
    # Set ownership
    chown -R "${ADMIN_PANEL_USER}:${ADMIN_PANEL_GROUP}" "$ADMIN_PANEL_DIR"
    
    # Set directory permissions
    find "$ADMIN_PANEL_DIR" -type d -exec chmod 755 {} \;
    
    # Set file permissions
    find "$ADMIN_PANEL_DIR" -type f -exec chmod 644 {} \;
    
    # Set executable permissions for artisan and scripts
    chmod +x "$ADMIN_PANEL_DIR/artisan"
    
    # Set storage and cache permissions
    chmod -R 775 "$ADMIN_PANEL_DIR/storage" 2>/dev/null || true
    chmod -R 775 "$ADMIN_PANEL_DIR/bootstrap/cache" 2>/dev/null || true
    
    # Ensure proper ownership
    chown -R "${ADMIN_PANEL_USER}:${ADMIN_PANEL_GROUP}" "$ADMIN_PANEL_DIR/storage" 2>/dev/null || true
    chown -R "${ADMIN_PANEL_USER}:${ADMIN_PANEL_GROUP}" "$ADMIN_PANEL_DIR/bootstrap/cache" 2>/dev/null || true
    
    log_success "Permissions set"
}

generate_app_key() {
    log_info "Generating application key..."
    
    cd "$ADMIN_PANEL_DIR"
    
    if grep -q "APP_KEY=$" .env 2>/dev/null || ! grep -q "APP_KEY=" .env 2>/dev/null; then
        php artisan key:generate --force || {
            log_error "Failed to generate application key"
            exit 1
        }
        log_success "Application key generated"
    else
        log_info "Application key already exists"
    fi
}

create_systemd_service() {
    log_info "Creating systemd service (optional)..."
    
    SERVICE_FILE="/etc/systemd/system/admin-panel.service"
    
    if [[ -f "$SERVICE_FILE" ]]; then
        log_info "Systemd service already exists"
        return
    fi
    
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=OpenSIPS Admin Panel
After=network.target mysql.service

[Service]
Type=simple
User=${ADMIN_PANEL_USER}
WorkingDirectory=${ADMIN_PANEL_DIR}
ExecStart=/usr/bin/php artisan serve --host=127.0.0.1 --port=8000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    log_success "Systemd service created (not enabled by default)"
    log_info "To enable: systemctl enable admin-panel"
    log_info "To start: systemctl start admin-panel"
}

print_summary() {
    echo
    log_success "Admin Panel Installation Complete!"
    echo
    log_info "Installation Summary:"
    echo "  - Location: ${ADMIN_PANEL_DIR}"
    echo "  - Database: ${DB_NAME} (user: ${DB_USER})"
    echo "  - Filament: Installed"
    if [[ "$INSTALL_SHIELD" == true ]]; then
        echo "  - Shield (RBAC): Installed"
    fi
    echo
    log_info "Next Steps:"
    echo "  1. Start development server:"
    echo "     cd ${ADMIN_PANEL_DIR}"
    echo "     php artisan serve --host=0.0.0.0 --port=8000"
    echo
    echo "  2. Create your first admin user:"
    echo "     Visit: http://$(hostname -I | awk '{print $1}'):8000/admin/register"
    echo "     (or http://localhost:8000/admin/register from the server)"
    echo "     Note: User creation must be done via web interface"
    echo
    echo "  3. Access admin panel:"
    echo "     http://$(hostname -I | awk '{print $1}'):8000/admin"
    echo "     (or http://localhost:8000/admin from the server)"
    echo
    echo "  4. Create Filament resources for your models:"
    echo "     php artisan make:filament-resource Domain"
    echo "     php artisan make:filament-resource Dispatcher"
    echo
    if [[ -f /etc/systemd/system/admin-panel.service ]]; then
        echo "  5. Optional - Enable systemd service:"
        echo "     systemctl enable admin-panel"
        echo "     systemctl start admin-panel"
        echo
    fi
    echo "  6. For production deployment, configure nginx/Apache"
    echo "     and set up proper virtual host configuration"
    echo
}

# Main installation flow
main() {
    echo
    echo "=========================================="
    echo "OpenSIPS Admin Panel Installation"
    echo "=========================================="
    echo
    
    check_root
    check_ubuntu
    
    log_info "Starting installation..."
    echo
    
    install_php
    install_composer
    get_database_credentials
    create_laravel_project
    install_filament
    configure_database
    generate_app_key
    run_migrations
    install_shield
    create_admin_user
    set_permissions
    create_systemd_service
    
    print_summary
}

# Run main function
main "$@"
