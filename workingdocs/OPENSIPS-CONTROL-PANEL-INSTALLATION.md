# OpenSIPS Control Panel Installation & Configuration

**Date:** January 2026  
**OpenSIPS Version:** 3.6.3  
**Control Panel Version:** 9.3.5 (from GitHub master branch)  
**Status:** ✅ Fully operational

## Overview

This document captures the complete installation and configuration process for the OpenSIPS Control Panel (OCP), including all decisions, issues encountered, and solutions implemented. This serves as a reference for future maintenance and troubleshooting.

## Key Decisions

### 1. Database: MySQL from Start

**Decision:** Use MySQL for OpenSIPS routing database from initial installation  
**Reason:** 
- Control panel works better with MySQL
- Future fault tolerance requires MySQL for dual OpenSIPS nodes
- Better performance for web interface
- No migration needed - start with MySQL from the beginning

**Implementation:**
- Database: `opensips`
- User: `opensips`
- Password: `your-password` (stored in config files)
- Database setup done during initial installation (not migrated)

### 2. Domain Table: Custom → Standard

**Decision:** Migrate from custom `sip_domains` table to standard OpenSIPS `domain` table  
**Reason:**
- Control panel natively supports standard `domain` table
- Eliminates need to "hack" control panel configuration
- Uses `domain.id` as `dispatcher_setid` (simpler mapping)
- Standard table structure is better maintained

**Implementation:**
- Updated OpenSIPS config to query `domain.id` instead of `sip_domains.dispatcher_setid`
- Configured control panel to use `domain` table
- Removed `AND enabled=1` clause (standard table doesn't have `enabled` column)
- Old `sip_domains` table can be dropped (currently still exists but unused)

## Installation Steps

### 1. Prerequisites

- Apache web server
- PHP 8.x with extensions: `php-mysql`, `php-xml`, `php-json`, `php-curl`, `php-mbstring`, `php-gd`
- MySQL database (for OpenSIPS routing database)
- OpenSIPS 3.6.3 installed and running

### 2. Control Panel Installation

```bash
# Download from GitHub (use .zip, not .tar.gz)
cd /var/www
sudo wget https://github.com/OpenSIPS/opensips-cp/archive/refs/heads/master.zip
sudo unzip master.zip
sudo mv opensips-cp-master opensips-cp
sudo chown -R www-data:www-data opensips-cp
```

### 3. Apache Configuration

**File:** `/etc/apache2/sites-available/opensips-cp.conf`

```apache
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot /var/www/opensips-cp/web
    
    <Directory /var/www/opensips-cp/web>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog ${APACHE_LOG_DIR}/opensips-cp-error.log
    CustomLog ${APACHE_LOG_DIR}/opensips-cp-access.log combined
</VirtualHost>
```

```bash
sudo a2ensite opensips-cp
sudo a2enmod rewrite
sudo systemctl restart apache2
```

### 4. Database Setup

The control panel uses the same MySQL database as OpenSIPS (`opensips` database). Database connection configured in:

**File:** `/var/www/opensips-cp/config/db.inc.php`

```php
$config->db_host = "localhost";
$config->db_port = "3306";
$config->db_user = "opensips";
$config->db_pass = "your-password";  // Must match MySQL user password
$config->db_name = "opensips";
```

### 5. OpenSIPS Management Interface (MI) Configuration

**Decision:** Use HTTP/JSON-RPC MI interface (not FIFO)  
**Reason:** Control panel expects JSON-RPC format

**OpenSIPS Configuration (`/etc/opensips/opensips.cfg`):**

```opensips
# Load HTTP and MI HTTP modules
loadmodule "httpd.so"
loadmodule "mi_http.so"

# Configure HTTP server
modparam("httpd", "port", 8888)

# Domain module (for control panel domain management)
loadmodule "domain.so"
modparam("domain", "db_url", "mysql://opensips:your-password@localhost/opensips")
modparam("domain", "domain_table", "domain")
modparam("domain", "domain_col", "domain")
modparam("domain", "db_mode", 1)
```

**Firewall:**
```bash
sudo ufw allow 8888/tcp
```

**Control Panel Box Configuration (database):**

Table: `ocp_boxes_config`

```sql
UPDATE ocp_boxes_config 
SET mi_conn='json:127.0.0.1:8888/mi', 
    name='opensips-server', 
    `desc`='OpenSIPS Server' 
WHERE id=1;
```

### 6. Domain Tool Configuration

**Decision:** Use standard `domain` table (not custom `sip_domains`)

**Control Panel Configuration (database):**

Table: `ocp_tools_config`

```sql
INSERT INTO ocp_tools_config (module, param, value, box_id) 
VALUES ('domains', 'table_domains', 'domain', 1) 
ON DUPLICATE KEY UPDATE value='domain';
```

## Critical Issues & Solutions

### Issue 1: Submit Button Greyed Out (Disabled)

**Problem:** Domain tool "Add" and "Edit" buttons were permanently disabled

**Root Cause:** 
- Hardcoded `disabled=true` in template file
- Missing `form_init_status()` JavaScript call to initialize form validation
- **Additional Issue:** Inline `oninput` attribute wasn't firing (browser wasn't attaching the event handler)

**Solution:**
1. Removed `disabled=true` from `/var/www/opensips-cp/web/tools/system/domains/template/domains.main.php`
2. Added `<script> form_init_status(); </script>` before closing `</form>` tag
3. **Added JavaScript event listener** to manually attach input event handler (inline oninput attribute wasn't working):

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

**File Modified:** `/var/www/opensips-cp/web/tools/system/domains/template/domains.main.php`

**Location:** After `<script> form_init_status(); </script>` and before closing `</form>` tag

**Note:** The grey/green button behavior is actually a feature - buttons are disabled (grey) when form is invalid and enabled (green) when valid. This is controlled by JavaScript validation in `/var/www/opensips-cp/web/common/forms.php`. The event listener workaround was needed because the inline `oninput` attribute generated by `form_generate_input_text()` wasn't being processed correctly by browsers (tested in Safari and Chrome). This appears to be a bug in control panel version 9.3.5 that requires a workaround.

### Issue 2: 500 Internal Server Error on Add Domain Page

**Problem:** Accessing `domains.php?action=add` returned 500 Internal Server Error

**Root Cause:** The code was trying to INSERT into database even when just displaying the form (GET request). It attempted to insert NULL values, causing a database constraint violation.

**Solution:** Added POST request check in `/var/www/opensips-cp/web/tools/system/domains/domains.php`:

```php
if ($action=="add")
{
    # Only process INSERT if this is a POST request (form submission)
    if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['add']))
    {
        # ... INSERT code here ...
    }
    # If GET request, just display the form (handled by template)
}
```

**File Modified:** `/var/www/opensips-cp/web/tools/system/domains/domains.php` (lines ~46-67)

**Note:** The dispatcher tool handles this correctly by checking for POST, but the domain tool was missing this check.

### Issue 3: Edit Form Blank Screen

**Problem:** Clicking "Edit" on a domain showed a blank screen

**Root Cause:** Missing JavaScript initialization causing form validation to fail

**Solution:** Same as Issue 1 - adding `form_init_status()` script call fixed both issues

### Issue 3: Database Connection Errors

**Problem:** Control panel couldn't connect to MySQL database

**Solution:** Updated `/var/www/opensips-cp/config/db.inc.php` with correct password (`your-password`)

### Issue 4: MI Connection Failed

**Problem:** Control panel couldn't connect to OpenSIPS MI interface (port 8888)

**Solution:**
1. Installed `opensips-http-modules` package
2. Added `httpd` and `mi_http` modules to OpenSIPS config
3. Configured port 8888
4. Opened firewall port 8888
5. Updated `ocp_boxes_config` table with correct MI connection string

### Issue 5: Domain Module Method Not Found

**Problem:** "MI command failed with code -32601 (Method not found)" when reloading domains

**Root Cause:** `domain` module not loaded in OpenSIPS

**Solution:**
1. Added `loadmodule "domain.so"`
2. Configured domain module parameters
3. Added `domain` table version entry to `version` table:
   ```sql
   INSERT INTO version (table_name, table_version) 
   VALUES ('domain', 4) 
   ON DUPLICATE KEY UPDATE table_version=4;
   ```

### Issue 6: Domain Table Schema Mismatch

**Problem:** Domain module failed to load with error about missing columns

**Root Cause:** Initially tried to use custom `sip_domains` table which had different schema than standard `domain` table

**Solution:** Switched to standard `domain` table which has correct schema:
- `id` (auto-increment primary key)
- `domain` (CHAR(64), UNIQUE)
- `attrs` (CHAR(255), nullable)
- `accept_subdomain` (INT UNSIGNED, default 0)
- `last_modified` (DATETIME, default '1900-01-01 00:00:01')

## OpenSIPS Configuration Changes

### Domain Routing Logic

**Before (using custom `sip_domains` table):**
```opensips
$var(query) = "SELECT dispatcher_setid FROM sip_domains WHERE domain='" + $var(domain) + "' AND enabled=1";
```

**After (using standard `domain` table):**
```opensips
$var(query) = "SELECT id FROM domain WHERE domain='" + $var(domain) + "'";
```

**Key Changes:**
- Use `domain.id` as `dispatcher_setid` (simplifies mapping)
- Remove `AND enabled=1` clause (standard table doesn't have `enabled` column)
- Domain IDs map directly to dispatcher set IDs

## File Locations

### Control Panel Files
- **Web Root:** `/var/www/opensips-cp/web`
- **Config:** `/var/www/opensips-cp/config/`
- **Database Config:** `/var/www/opensips-cp/config/db.inc.php`
- **Domain Tool Config:** `/var/www/opensips-cp/config/tools/system/domains/settings.inc.php`
- **Domain Tool Template:** `/var/www/opensips-cp/web/tools/system/domains/template/domains.main.php`

### OpenSIPS Files
- **Config:** `/etc/opensips/opensips.cfg`
- **Database:** MySQL database `opensips` (user: `opensips`, password: `your-password`)

### Database Tables (Control Panel)
- `ocp_boxes_config` - OpenSIPS instance configuration
- `ocp_tools_config` - Tool-specific configuration
- `domain` - SIP domains (standard OpenSIPS table)
- `dispatcher` - Dispatcher sets and destinations (standard OpenSIPS table)

## Useful Commands

### Clear PHP Sessions (if UI issues)
```bash
sudo rm -rf /var/lib/php/sessions/*
sudo systemctl restart apache2
```

### Test MySQL Connection
```bash
mysql opensips -u opensips -p'your-password' -e "SELECT COUNT(*) FROM domain;"
```

### Test OpenSIPS MI (JSON-RPC)
```bash
curl -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"domain_dump","id":1}' \
  http://127.0.0.1:8888/mi
```

### View Control Panel Logs
```bash
sudo tail -f /var/log/apache2/error.log
sudo tail -f /var/log/apache2/opensips-cp-error.log
```

## Current State

### Working Features
- ✅ Control panel web interface accessible
- ✅ Login and authentication working
- ✅ OpenSIPS box connection (MI interface)
- ✅ Dispatcher tool - fully functional (view, add, edit, delete, reload)
- ✅ Domain tool - fully functional (view, add, edit, delete, reload)

### Database Tables Status
- ✅ `domain` - Active, managed via control panel
- ✅ `dispatcher` - Active, managed via control panel
- ✅ `endpoint_locations` - Self-managing (populated by REGISTER requests)
- ⚠️ `sip_domains` - Legacy table, can be dropped (not used)

### Known Limitations
- Control panel UX could be better (button states confusing but functional)
- `endpoint_locations` table is custom (not standard OpenSIPS, but self-managing)

## Troubleshooting Checklist

1. **Control panel shows database error:**
   - Check `/var/www/opensips-cp/config/db.inc.php` password
   - Verify MySQL user has access: `mysql opensips -u opensips -p'your-password'`

2. **MI connection fails:**
   - Check OpenSIPS logs: `sudo journalctl -u opensips -f`
   - Verify modules loaded: `grep -i "httpd\|mi_http" /etc/opensips/opensips.cfg`
   - Test MI endpoint: `curl http://127.0.0.1:8888/mi`
   - Check firewall: `sudo ufw status | grep 8888`

3. **Domain tool buttons disabled:**
   - Check browser console for JavaScript errors
   - Verify `form_init_status()` script call exists in template
   - Clear PHP sessions and browser cache

4. **Edit form shows blank screen:**
   - Check Apache error logs
   - Verify form template file exists and is readable
   - Check PHP errors: `php -l /var/www/opensips-cp/web/tools/system/domains/domains.php`

5. **Changes not saving:**
   - Verify database connection
   - Check MySQL user permissions
   - Review Apache error logs for PHP errors

## Future Considerations

1. **Drop `sip_domains` table** - No longer needed, can be removed
2. **Consider using standard `location` table** - Currently using custom `endpoint_locations`, but standard `location` table exists in schema
3. **HTTPS/SSL** - Consider adding SSL certificate for production
4. **Backup strategy** - Document backup procedures for control panel database
5. **Multi-node setup** - When implementing fault tolerance, will need to configure control panel for multiple OpenSIPS instances

## References

- OpenSIPS Control Panel: https://controlpanel.opensips.org/
- OpenSIPS Control Panel GitHub: https://github.com/OpenSIPS/opensips-cp
- OpenSIPS Domain Module: https://opensips.org/docs/modules/3.4.x/domain.html
- OpenSIPS MI HTTP Module: https://opensips.org/docs/modules/3.4.x/mi_http.html

## Notes

- Control panel default admin credentials are set during installation (check installation logs or reset via database)
- PHP sessions stored in `/var/lib/php/sessions/` (clearing can fix UI issues)
- Control panel configuration is stored in database tables (`ocp_*` tables), not just config files
- Domain tool uses JavaScript form validation - buttons enable/disable based on form validity (this is a feature, not a bug)
- Dispatcher tool works out of the box because it uses standard OpenSIPS table structure
- Domain tool required fixes because it was originally designed for standard tables, not custom ones

