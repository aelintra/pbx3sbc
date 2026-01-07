# OpenSIPS Control Panel Installation Plan

## Overview

This document outlines the plan for installing and configuring the OpenSIPS Control Panel (OCP) version 9.x to manage the OpenSIPS SIP Edge Router. The control panel provides a web-based interface for provisioning, monitoring, and managing OpenSIPS servers.

**Documentation Reference:** https://controlpanel.opensips.org/documentation.php

## Prerequisites

### Current System State
- **OpenSIPS Version:** 3.6.3
- **Database:** SQLite (`/etc/opensips/opensips.db`)
- **OpenSIPS User:** `opensips`
- **OpenSIPS Group:** `opensips`
- **OpenSIPS Config:** `/etc/opensips/opensips.cfg`
- **OS:** Ubuntu 24.04 (noble)

### Required Components

1. **Web Server**
   - Apache 2.4+ (recommended)
   - Alternative: Nginx (with PHP-FPM)

2. **PHP**
   - PHP 7.4+ or PHP 8.x
   - Required PHP extensions:
     - php-mysql (or php-pgsql for PostgreSQL)
     - php-xml
     - php-json
     - php-curl
     - php-mbstring
     - php-gd (for graphics/charts)
     - php-zip (for installation/updates)

3. **Database**
   - **Current:** SQLite (for OpenSIPS routing)
   - **Control Panel:** MySQL/MariaDB or PostgreSQL (recommended for control panel)
   - **Decision Needed:** Use existing SQLite or migrate/add MySQL for control panel?

4. **OpenSIPS Modules**
   - `mi_datagram` or `mi_fifo` or `mi_json` (Management Interface)
   - `httpd` module (for REST API, if using newer features)
   - Database modules already installed (`db_sqlite.so`)

## Installation Steps

### Phase 1: Database Setup

**Decision Point:** Control Panel Database Selection

**Option A: Use MySQL/MariaDB (Recommended)**
- Install MySQL/MariaDB server
- Create database and user for control panel
- Control panel can connect to OpenSIPS SQLite via tools/scripts
- Better performance for web interface
- Supports multiple OpenSIPS instances

**Option B: Use SQLite (Simpler)**
- Control panel uses SQLite
- May have limitations with concurrent access
- Simpler setup, no additional database server

**Recommended:** Option A (MySQL/MariaDB) for production use

### Phase 2: Web Server and PHP Installation

1. **Install Apache**
   ```bash
   apt-get install -y apache2
   ```

2. **Install PHP and Required Extensions**
   ```bash
   apt-get install -y php php-mysql php-xml php-json php-curl php-mbstring php-gd php-zip
   ```

3. **Enable Apache Modules**
   ```bash
   a2enmod rewrite
   a2enmod ssl  # If using HTTPS
   ```

4. **Configure PHP**
   - Set appropriate `upload_max_filesize` and `post_max_size`
   - Configure `memory_limit` if needed
   - Enable required PHP extensions

### Phase 3: Download and Install Control Panel

1. **Download Control Panel**
   - Download latest version 9.x from OpenSIPS Solutions
   - Extract to web server directory (e.g., `/var/www/opensips-cp`)

2. **Set Permissions**
   - Web server user (www-data) needs read access
   - May need write access for certain directories (uploads, cache, etc.)

3. **Run Installation Wizard**
   - Access via web browser
   - Follow installation wizard steps
   - Configure database connection
   - Set admin credentials

### Phase 4: OpenSIPS Integration

1. **Configure Management Interface (MI)**
   - Enable MI module in OpenSIPS config
   - Choose MI transport: `mi_datagram`, `mi_fifo`, or `mi_json`
   - Configure MI socket/endpoint
   - Test MI connectivity

2. **Database Connection**
   - Configure control panel to connect to OpenSIPS database
   - For SQLite: May need special handling or conversion tools
   - For MySQL: If OpenSIPS uses MySQL, direct connection possible

3. **Configure OpenSIPS Box**
   - Add OpenSIPS instance to control panel
   - Configure connection details (IP, MI interface, database)
   - Test connectivity

### Phase 5: Module Configuration

Configure control panel modules relevant to our setup:

1. **Dispatcher Module**
   - Already using dispatcher for Asterisk backends
   - Configure in control panel for monitoring and management
   - View dispatcher sets and destinations
   - Monitor health status

2. **Domains Module**
   - Manage `sip_domains` table via control panel
   - Add/edit/remove domains
   - Link domains to dispatcher sets

3. **CDR Viewer** (if enabled)
   - View call detail records
   - Search and filter CDRs

4. **Statistics Monitor**
   - View OpenSIPS statistics
   - Monitor system health
   - Track performance metrics

5. **SIPtrace** (if enabled)
   - View SIP message traces
   - Debug call flows

### Phase 6: Access Control and Security

1. **Configure Access Control**
   - Set up user accounts and permissions
   - Configure role-based access control
   - Restrict access to sensitive operations

2. **SSL/TLS Setup** (Recommended)
   - Configure HTTPS for web interface
   - Obtain SSL certificate (Let's Encrypt recommended)
   - Configure Apache SSL virtual host

3. **Firewall Configuration**
   - Allow HTTP/HTTPS access (ports 80/443)
   - Restrict access to control panel IP if needed
   - Ensure OpenSIPS MI interface is secured

### Phase 7: Integration with Existing Setup

1. **Database Migration Considerations**
   - Current: SQLite at `/etc/opensips/opensips.db`
   - Control panel may prefer MySQL
   - Options:
     a. Keep SQLite for OpenSIPS, use MySQL for control panel only
     b. Migrate OpenSIPS to MySQL (more complex)
     c. Use SQLite for both (may have limitations)

2. **Preserve Existing Configuration**
   - Backup current OpenSIPS config
   - Ensure control panel changes don't break existing routing
   - Test all routing scenarios after installation

3. **Update Install Script**
   - Add control panel installation to `install.sh` (optional)
   - Or create separate `install-controlpanel.sh` script
   - Document manual installation steps

## Configuration Details

### OpenSIPS MI Configuration

Add to `opensips.cfg`:

```opensips
# Management Interface - for control panel access
loadmodule "mi_datagram.so"
# or
loadmodule "mi_fifo.so"
# or  
loadmodule "mi_json.so"

# Configure MI socket
modparam("mi_datagram", "socket_name", "udp:127.0.0.1:8080")
# or for FIFO
modparam("mi_fifo", "fifo_name", "/tmp/opensips_fifo")
```

### Apache Virtual Host Configuration

Example configuration for `/etc/apache2/sites-available/opensips-cp.conf`:

```apache
<VirtualHost *:80>
    ServerName opensips-cp.example.com
    DocumentRoot /var/www/opensips-cp
    
    <Directory /var/www/opensips-cp>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog ${APACHE_LOG_DIR}/opensips-cp-error.log
    CustomLog ${APACHE_LOG_DIR}/opensips-cp-access.log combined
</VirtualHost>
```

### Database Configuration

**If using MySQL for control panel:**

```sql
CREATE DATABASE opensips_cp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'opensips_cp'@'localhost' IDENTIFIED BY 'secure_password';
GRANT ALL PRIVILEGES ON opensips_cp.* TO 'opensips_cp'@'localhost';
FLUSH PRIVILEGES;
```

## Testing Checklist

- [ ] Web interface accessible
- [ ] Can log in with admin credentials
- [ ] OpenSIPS box connection successful
- [ ] Can view dispatcher sets and destinations
- [ ] Can view domains
- [ ] Can add/edit domains via control panel
- [ ] Can add/edit dispatcher entries via control panel
- [ ] Statistics display correctly
- [ ] CDR viewer works (if enabled)
- [ ] Changes made via control panel persist
- [ ] OpenSIPS routing still works after control panel changes
- [ ] MI commands work from control panel

## Potential Issues and Solutions

### Issue 1: SQLite vs MySQL
**Problem:** Control panel may prefer MySQL, but we use SQLite
**Solution:** 
- Use MySQL for control panel database only
- Control panel can read OpenSIPS SQLite via tools/scripts
- Or use SQLite adapter if available

### Issue 2: MI Interface Security
**Problem:** MI interface exposed to control panel
**Solution:**
- Use localhost-only binding
- Use Unix sockets (FIFO) instead of network sockets
- Implement firewall rules

### Issue 3: Database Permissions
**Problem:** Control panel needs database access
**Solution:**
- Ensure proper file permissions for SQLite
- Or configure MySQL user with appropriate privileges
- Use read-only access where possible

### Issue 4: Configuration Conflicts
**Problem:** Control panel changes may conflict with manual config
**Solution:**
- Use control panel as primary management tool
- Or use read-only mode for certain tables
- Document which tool manages which configuration

## Post-Installation Tasks

1. **Backup Strategy**
   - Backup control panel database
   - Backup OpenSIPS configuration
   - Document backup procedures

2. **Monitoring**
   - Set up monitoring for control panel availability
   - Monitor OpenSIPS MI interface
   - Alert on control panel errors

3. **Documentation**
   - Document control panel URL and credentials
   - Document which features are enabled
   - Create user guide for common tasks

4. **Maintenance**
   - Schedule regular control panel updates
   - Monitor disk space for logs/database
   - Review access logs periodically

## Integration with Existing Scripts

Consider updating helper scripts to work with control panel:

- `scripts/add-domain.sh` - May be replaced by control panel UI
- `scripts/add-dispatcher.sh` - May be replaced by control panel UI
- `scripts/view-status.sh` - Can complement control panel statistics

## References

- **Official Documentation:** https://controlpanel.opensips.org/documentation.php
- **Installation Guide:** https://controlpanel.opensips.org/htmldoc/INSTALL.html
- **GitHub Repository:** https://github.com/OpenSIPS/opensips-cp
- **OpenSIPS MI Module Docs:** https://opensips.org/docs/modules/

## Next Steps

1. Review and approve this installation plan
2. Decide on database approach (SQLite vs MySQL)
3. Prepare installation environment
4. Download control panel software
5. Begin Phase 1 installation

