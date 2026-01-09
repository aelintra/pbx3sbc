# OpenSIPS Control Panel Installation Steps

## Overview

We have two options for installing the control panel:

### Option A: Use Installer Script (Recommended if no fork exists)
- Uses upstream code (unpatched)
- Requires manual patch application after installation
- Simpler initial setup

### Option B: Use Forked Repository (Recommended if fork exists)
- All patches pre-applied
- Clean installation
- Requires fork to be created first

## Prerequisites Check

Before installation, verify:
- ✅ OpenSIPS is installed and running
- ✅ MySQL database `opensips` exists
- ✅ OpenSIPS HTTP/MI modules loaded (port 8888)
- ✅ Database password is known

## Installation Steps (Option A: Using Installer Script - Upstream)

### Step 1: Run the Installer Script

```bash
cd /home/tech/pbx3sbc
sudo ./install-control-panel.sh --db-password rigmarole
```

**What this does:**
- Installs Apache and PHP (with required extensions)
- Downloads OpenSIPS Control Panel 9.3.5 from upstream GitHub
- Configures Apache virtual host
- Configures database connection
- Configures control panel database tables (ocp_boxes_config, ocp_tools_config)
- Opens firewall ports (80, 443) if not skipped

### Step 2: Apply Manual Patches (Required if using upstream)

After installation, you need to manually patch the domain tool files:

#### 2.1. Fix domains.php (POST request check)
**File:** `/var/www/opensips-cp/web/tools/system/domains/domains.php`
**Location:** Around lines 46-67 in the `if ($action=="add")` block

Add POST check:
```php
if ($action=="add")
{
    # Only process INSERT if this is a POST request (form submission)
    if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['add']))
    {
        # ... existing INSERT code ...
    }
    # If GET request, just display the form (handled by template)
}
```

Also update `if ($action=="save")` to include setid in UPDATE statement.

#### 2.2. Fix domains.form.php (Add setid field)
**File:** `/var/www/opensips-cp/web/tools/system/domains/template/domains.form.php`

Add setid input field after domain field:
```php
form_generate_input_text("Set ID", "Dispatcher Set ID for routing to backend servers",
    "setid", "n", isset($domain_form['setid']) ? $domain_form['setid'] : '', 10, "^[0-9]+$");
```

#### 2.3. Fix domains.main.php (Multiple changes)
**File:** `/var/www/opensips-cp/web/tools/system/domains/template/domains.main.php`

Changes needed:
1. Remove `disabled=true` from submit button
2. Add ID and Set ID columns to table header
3. Add ID and Set ID columns to table rows
4. Add JavaScript initialization scripts (form_init_status and event listener)

See CONTROL-PANEL-FORK-GUIDE.md for exact code changes.

### Step 3: Verify Installation

1. Access control panel: `http://<server-ip>/`
2. Login with default credentials (check installation logs)
3. Verify domain tool works (add/edit domains)
4. Verify dispatcher tool works

## Installation Steps (Option B: Using Forked Repository)

If you have a forked repository with patches already applied:

```bash
cd /home/tech/pbx3sbc
sudo ./install-control-panel.sh --db-password rigmarole --fork-repo YOUR_USERNAME/opensips-cp
```

This will:
- Download from your fork (tag: v9.3.5-pbx3sbc)
- All patches already applied
- No manual patching needed

## Database Configuration

The installer automatically:
- Configures `/var/www/opensips-cp/config/db.inc.php` with database credentials
- Sets up `ocp_boxes_config` table (OpenSIPS MI connection)
- Sets up `ocp_tools_config` table (domain table configuration)
- Adds domain table version to `version` table

## OpenSIPS Configuration

Ensure OpenSIPS config has:
- `httpd` and `mi_http` modules loaded
- Port 8888 configured for MI interface
- `domain` module loaded (for domain management)

These should already be configured from the OpenSIPS installation.

## Files That Need Modification (If Using Upstream)

1. `/var/www/opensips-cp/web/tools/system/domains/domains.php`
2. `/var/www/opensips-cp/web/tools/system/domains/template/domains.form.php`
3. `/var/www/opensips-cp/web/tools/system/domains/template/domains.main.php`

## Verification Checklist

After installation:
- [ ] Control panel accessible via web browser
- [ ] Can login to control panel
- [ ] Domain tool shows ID and Set ID columns
- [ ] Can add new domain
- [ ] Can edit existing domain
- [ ] Dispatcher tool works
- [ ] OpenSIPS MI connection works (test domain reload)

## Troubleshooting

If domain tool doesn't work:
1. Check Apache error logs: `sudo tail -f /var/log/apache2/error.log`
2. Check PHP errors: `php -l /var/www/opensips-cp/web/tools/system/domains/domains.php`
3. Clear PHP sessions: `sudo rm -rf /var/lib/php/sessions/*`
4. Verify patches were applied correctly
5. Check browser console for JavaScript errors

See OPENSIPS-CONTROL-PANEL-INSTALLATION.md for detailed troubleshooting.

