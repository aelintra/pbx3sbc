# Manual Installation Steps - OpenSIPS with Control Panel

**Date:** January 2026  
**System:** Fresh Ubuntu installation (VM rolled back)  
**Goal:** Install OpenSIPS with MySQL database and OpenSIPS Control Panel

## Overview

This document outlines the step-by-step process to manually install:
1. OpenSIPS SIP Edge Router with MySQL database
2. OpenSIPS Control Panel (web-based administration)

## Prerequisites

- Fresh Ubuntu system (22.04 or 24.04)
- Root/sudo access
- Internet connectivity

---

## Part 1: OpenSIPS Installation

### Step 1.1: Install System Dependencies

```bash
# Update package lists
sudo apt-get update

# Install MySQL/MariaDB server
sudo apt-get install -y mariadb-server

# Install other dependencies (will be used by OpenSIPS install script)
sudo apt-get install -y curl wget ufw jq
```

### Step 1.2: Set Up MySQL Database and User

```bash
# Secure MySQL installation (optional, but recommended for production)
sudo mysql_secure_installation

# Create OpenSIPS database and user
sudo mysql <<EOF
CREATE DATABASE IF NOT EXISTS opensips CHARACTER SET utf8 COLLATE utf8_general_ci;
CREATE USER IF NOT EXISTS 'opensips'@'localhost' IDENTIFIED BY 'your-password';
GRANT ALL PRIVILEGES ON opensips.* TO 'opensips'@'localhost';
FLUSH PRIVILEGES;
EOF

# Verify connection
mysql -u opensips -p'your-password' opensips -e "SELECT 'Connection successful' AS status;"
```

### Step 1.3: Run OpenSIPS Installation Script

**Note:** The current `install.sh` is designed for SQLite. We'll need to adapt it for MySQL during the process.

```bash
# Navigate to repository
cd /home/tech/pbx3sbc

# Run install script (this will install OpenSIPS packages)
sudo ./install.sh --skip-db  # Skip database init since we'll do MySQL manually
```

**What this does:**
- Adds OpenSIPS APT repository
- Installs OpenSIPS packages (opensips, opensips-mysql-module, opensips-http-modules)
- Installs opensips-cli
- Creates opensips user
- Creates directories
- Configures firewall (ports 5060 UDP/TCP, 5061 TCP, 10000-20000 UDP)
- Creates OpenSIPS config from template (but it's SQLite-based - will need updating)

### Step 1.4: Initialize MySQL Database Schema

```bash
# Find MySQL schema files (installed with OpenSIPS packages)
ls -la /usr/share/opensips/mysql/

# Load core schema
mysql -u opensips -p'your-password' opensips < /usr/share/opensips/mysql/standard-create.sql

# Load dispatcher schema
mysql -u opensips -p'your-password' opensips < /usr/share/opensips/mysql/dispatcher-create.sql

# Load domain schema
mysql -u opensips -p'your-password' opensips < /usr/share/opensips/mysql/domain-create.sql

# Create custom endpoint_locations table
mysql -u opensips -p'your-password' opensips <<EOF
CREATE TABLE IF NOT EXISTS endpoint_locations (
    aor VARCHAR(255) PRIMARY KEY,
    contact_ip VARCHAR(45) NOT NULL,
    contact_port VARCHAR(10) NOT NULL,
    expires DATETIME NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_endpoint_locations_expires ON endpoint_locations(expires);
EOF
```

### Step 1.5: Update OpenSIPS Configuration for MySQL

Edit `/etc/opensips/opensips.cfg`:

**Changes needed:**
1. Replace `db_sqlite.so` with `db_mysql.so`
2. Update `modparam("sqlops", "db_url")` to MySQL connection string
3. Update `modparam("dispatcher", "db_url")` to MySQL connection string
4. Add HTTP and MI HTTP modules for control panel
5. Add domain module for control panel
6. Update SQL queries to use MySQL syntax (datetime functions)

**Key changes:**
```opensips
# Replace SQLite module
loadmodule "db_mysql.so"

# Update database URLs
modparam("sqlops", "db_url", "mysql://opensips:your-password@localhost/opensips")
modparam("dispatcher", "db_url", "mysql://opensips:your-password@localhost/opensips")

# Add HTTP and MI modules (for control panel)
loadmodule "httpd.so"
loadmodule "mi_http.so"
modparam("httpd", "port", 8888)

# Add domain module (for control panel)
loadmodule "domain.so"
modparam("domain", "db_url", "mysql://opensips:your-password@localhost/opensips")
modparam("domain", "domain_table", "domain")
modparam("domain", "domain_col", "domain")
modparam("domain", "db_mode", 1)
```

**Also update SQL queries:**
- Replace `datetime('now')` with `NOW()` (MySQL syntax)
- Check all SQL queries in routing logic

### Step 1.6: Update Advertised Address

```bash
# Set advertised address (replace with your server's IP)
sudo sed -i 's/advertised_address="CHANGE_ME"/advertised_address="YOUR_IP_ADDRESS"/' /etc/opensips/opensips.cfg
```

### Step 1.7: Open Firewall Port for MI Interface

```bash
sudo ufw allow 8888/tcp comment 'OpenSIPS MI HTTP'
```

### Step 1.8: Test OpenSIPS Configuration and Start

```bash
# Test configuration syntax
sudo opensips -C -f /etc/opensips/opensips.cfg

# If syntax OK, start OpenSIPS
sudo systemctl start opensips
sudo systemctl enable opensips

# Check status
sudo systemctl status opensips

# Check logs
sudo journalctl -u opensips -f
```

---

## Part 2: Control Panel Installation

### Step 2.1: Install Apache and PHP

```bash
sudo apt-get install -y apache2

# Install PHP 8.x and required extensions
sudo apt-get install -y php php-mysql php-xml php-json php-curl php-mbstring php-gd

# Enable Apache modules
sudo a2enmod rewrite
sudo systemctl restart apache2
```

### Step 2.2: Download and Install Control Panel

```bash
cd /var/www
sudo wget https://github.com/OpenSIPS/opensips-cp/archive/refs/heads/master.zip
sudo unzip master.zip
sudo mv opensips-cp-master opensips-cp
sudo chown -R www-data:www-data opensips-cp
```

### Step 2.3: Configure Apache Virtual Host

```bash
sudo tee /etc/apache2/sites-available/opensips-cp.conf <<EOF
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot /var/www/opensips-cp/web
    
    <Directory /var/www/opensips-cp/web>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/opensips-cp-error.log
    CustomLog \${APACHE_LOG_DIR}/opensips-cp-access.log combined
</VirtualHost>
EOF

sudo a2ensite opensips-cp
sudo a2dissite 000-default  # Disable default site (optional)
sudo systemctl reload apache2
```

### Step 2.4: Configure Control Panel Database Connection

```bash
# Edit database configuration
sudo nano /var/www/opensips-cp/config/db.inc.php
```

Set:
```php
$config->db_host = "localhost";
$config->db_port = "3306";
$config->db_user = "opensips";
$config->db_pass = "your-password";
$config->db_name = "opensips";
```

### Step 2.5: Access Control Panel Web Interface

1. Open browser: `http://YOUR_SERVER_IP/`
2. Default credentials (check installation or reset via database if needed)
3. Login

### Step 2.6: Configure OpenSIPS Box in Control Panel

After login, configure the OpenSIPS server connection:

**Via Database:**
```bash
mysql -u opensips -p'your-password' opensips <<EOF
INSERT INTO ocp_boxes_config (id, name, \`desc\`, mi_conn, db_host, db_port, db_user, db_pass, db_name)
VALUES (1, 'opensips-server', 'OpenSIPS Server', 'json:127.0.0.1:8888/mi', 'localhost', 3306, 'opensips', 'your-password', 'opensips')
ON DUPLICATE KEY UPDATE 
    mi_conn='json:127.0.0.1:8888/mi',
    name='opensips-server',
    \`desc\`='OpenSIPS Server';
EOF
```

### Step 2.7: Configure Domain Tool

```bash
mysql -u opensips -p'your-password' opensips <<EOF
INSERT INTO ocp_tools_config (module, param, value, box_id) 
VALUES ('domains', 'table_domains', 'domain', 1) 
ON DUPLICATE KEY UPDATE value='domain';
EOF
```

### Step 2.8: Add Domain Table Version Entry

```bash
mysql -u opensips -p'your-password' opensips <<EOF
INSERT INTO version (table_name, table_version) 
VALUES ('domain', 4) 
ON DUPLICATE KEY UPDATE table_version=4;
EOF
```

### Step 2.9: Fix Domain Tool Template (if needed)

If "Add" and "Edit" buttons are disabled:

```bash
# Edit domain tool template
sudo nano /var/www/opensips-cp/web/tools/system/domains/template/domains.main.php
```

**Changes:**
1. Remove `disabled=true` from submit button (line ~64)
2. Add `<script> form_init_status(); </script>` before closing `</form>` tag (after `</table>`, before `</form>`)
3. **Add JavaScript event listener** to fix oninput event not firing:

Add this script block after `<script> form_init_status(); </script>`:

```javascript
<script>
(function() {
  var domainField = document.getElementById("domain");
  if (domainField) {
    domainField.addEventListener("input", function() {
      validate_input("domain", "domain_ok", "^(([0-9]{1,3}\\.){3}[0-9]{1,3})|(([A-Za-z0-9-]+\\.)+[a-zA-Z]+)$", null, "");
    });
  }
})();
</script>
```

**Why:** The inline `oninput` attribute generated by PHP's `form_generate_input_text()` function isn't being processed correctly by browsers. The `addEventListener()` approach ensures the validation fires when typing in the domain field.

### Step 2.10: Clear PHP Sessions and Restart

```bash
sudo rm -rf /var/lib/php/sessions/*
sudo systemctl restart apache2
```

---

## Part 3: Verification

### Step 3.1: Verify OpenSIPS

```bash
# Check service status
sudo systemctl status opensips

# Test MI interface
curl -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"domain_dump","id":1}' \
  http://127.0.0.1:8888/mi

# Check logs
sudo journalctl -u opensips -n 50
```

### Step 3.2: Verify Control Panel

1. Access web interface: `http://YOUR_SERVER_IP/`
2. Login
3. Check "System Tools" → "Dispatcher" (should work)
4. Check "System Tools" → "Domain" (should work - can add domains)
5. Test adding a domain
6. Test adding dispatcher entries

### Step 3.3: Test Domain and Dispatcher Integration

```bash
# Add a test domain (will get auto-generated ID)
mysql -u opensips -p'your-password' opensips -e "INSERT INTO domain (domain) VALUES ('test.example.com');"

# Get the domain ID
DOMAIN_ID=$(mysql -u opensips -p'your-password' opensips -sN -e "SELECT id FROM domain WHERE domain='test.example.com';")

# Add dispatcher entry using domain ID as setid
mysql -u opensips -p'your-password' opensips -e "INSERT INTO dispatcher (setid, destination, priority, state, probe_mode) VALUES ($DOMAIN_ID, 'sip:10.0.1.10:5060', 0, 0, 0);"
```

---

## Known Issues and Manual Fixes

### Issue: SQLite syntax in OpenSIPS config

**Problem:** Template uses SQLite-specific functions like `datetime('now')`  
**Fix:** Replace with MySQL syntax:
- `datetime('now')` → `NOW()`
- Check all SQL queries in routing logic

### Issue: Control panel can't connect to MI

**Problem:** Port 8888 not accessible or modules not loaded  
**Fix:**
1. Check OpenSIPS config has `httpd` and `mi_http` modules
2. Check port 8888 is open in firewall
3. Check OpenSIPS logs for errors

### Issue: Domain tool buttons disabled

**Problem:** Template has hardcoded `disabled=true`  
**Fix:** Edit template file as described in Step 2.9

---

## Next Steps After Installation

1. Add your actual SIP domains via control panel
2. Add dispatcher destinations for each domain
3. Configure firewall rules for production
4. Set up SSL/HTTPS for control panel (recommended)
5. Test SIP registration and routing

---

## Notes

- Database password `your-password` is stored in multiple config files - consider using a secrets manager for production
- Control panel stores configuration in database tables (`ocp_*` tables)
- OpenSIPS config file location: `/etc/opensips/opensips.cfg`
- Control panel web root: `/var/www/opensips-cp/web`
- MySQL database: `opensips` (user: `opensips`, password: `your-password`)

