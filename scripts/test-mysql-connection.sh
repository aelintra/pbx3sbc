#!/bin/bash
#
# Test MySQL connection and user creation
# This helps debug password issues
#

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <password_for_opensips_user> [mysql_root_password]"
    echo
    echo "This script will:"
    echo "  1. Test MySQL root connection"
    echo "  2. Create opensips user with the provided password"
    echo "  3. Test logging in with that password"
    exit 1
fi

OPENSIPS_PASSWORD="$1"
MYSQL_ROOT_PASSWORD="${2:-}"

echo "Testing MySQL connection..."
echo

# Test root connection
if [[ -n "$MYSQL_ROOT_PASSWORD" ]]; then
    echo "Method 1: Trying with root password..."
    export MYSQL_PWD="${MYSQL_ROOT_PASSWORD}"
    if mysql -u root -e "SELECT 1;" > /dev/null 2>&1; then
        echo "✓ Root connection successful with password"
        ROOT_CMD="mysql -u root"
    else
        echo "✗ Root connection failed with password"
        unset MYSQL_PWD
        exit 1
    fi
elif sudo mysql -e "SELECT 1;" > /dev/null 2>&1; then
    echo "✓ Root connection successful with sudo (socket auth)"
    ROOT_CMD="sudo mysql"
elif mysql -u root -e "SELECT 1;" > /dev/null 2>&1; then
    echo "✓ Root connection successful without password"
    ROOT_CMD="mysql -u root"
else
    echo "✗ Cannot connect to MySQL as root"
    echo "  Try: sudo mysql_secure_installation"
    exit 1
fi

echo
echo "Creating opensips user with password..."
echo "Password length: ${#OPENSIPS_PASSWORD} characters"

# Drop user if exists (for testing)
$ROOT_CMD <<EOF 2>&1 | grep -v "Unknown user" || true
DROP USER IF EXISTS 'opensips'@'localhost';
EOF

# Create user
$ROOT_CMD <<EOF
CREATE DATABASE IF NOT EXISTS opensips CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'opensips'@'localhost' IDENTIFIED BY '${OPENSIPS_PASSWORD}';
GRANT ALL PRIVILEGES ON opensips.* TO 'opensips'@'localhost';
FLUSH PRIVILEGES;
SELECT 'User created successfully' AS status;
EOF

if [[ $? -eq 0 ]]; then
    echo "✓ User created"
else
    echo "✗ Failed to create user"
    exit 1
fi

echo
echo "Testing login with opensips user..."

# Test login
export MYSQL_PWD="${OPENSIPS_PASSWORD}"
if mysql -u opensips opensips -e "SELECT 'Login successful' AS status;" 2>&1; then
    echo "✓ Login successful!"
    unset MYSQL_PWD
    exit 0
else
    echo "✗ Login failed"
    echo
    echo "Troubleshooting:"
    echo "  1. Check if password has special characters that need escaping"
    echo "  2. Try a simple password first: $0 'testpass123'"
    echo "  3. Check MySQL error log: sudo tail -f /var/log/mysql/error.log"
    unset MYSQL_PWD
    exit 1
fi

