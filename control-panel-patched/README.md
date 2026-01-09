# OpenSIPS Control Panel - Patched Files

This directory contains patched versions of OpenSIPS Control Panel files that have been modified to support the pbx3sbc project.

## Files Included

### Domain Tool
- `web/tools/system/domains/domains.php` - Domain management handler
- `web/tools/system/domains/template/domains.main.php` - Domain list/main template
- `web/tools/system/domains/template/domains.form.php` - Domain add/edit form template

### Configuration
- `config/db.inc.php` - Database configuration with $config object initialization fix

## Patches Applied

### 1. Domain Tool (`domains.php`)
- Added POST request check for add action (prevents INSERT on GET requests)
- Added `setid` support to INSERT queries
- Added `setid` support to UPDATE queries
- Added logic to auto-set `setid = id` when `setid = 0` after insertion

### 2. Domain Tool Main Template (`domains.main.php`)
- Removed `disabled=true` from submit button
- Added ID and Set ID columns to table header
- Added ID and Set ID columns to table rows
- Added JavaScript initialization (`form_init_status()`)
- Added event listeners for `domain` and `setid` fields
- Added validation triggers on page load for edit forms
- Updated colspan for "no results" row

### 3. Domain Tool Form Template (`domains.form.php`)
- Added Set ID input field between Domain and Attributes fields
- Field uses regex validation: `^[0-9]+$`

### 4. Database Config (`db.inc.php`)
- Added `$config` object initialization to prevent PHP fatal errors

## Usage

To use these patched files, copy them to the OpenSIPS Control Panel installation directory:

```bash
# Copy domain tool files
sudo cp -r control-panel-patched/web/tools/system/domains/* /var/www/opensips-cp/web/tools/system/domains/

# Copy config file
sudo cp control-panel-patched/config/db.inc.php /var/www/opensips-cp/config/db.inc.php

# Fix permissions
sudo chown -R www-data:www-data /var/www/opensips-cp/web/tools/system/domains/
sudo chown www-data:www-data /var/www/opensips-cp/config/db.inc.php
```

## Notes

- These patches are based on OpenSIPS Control Panel version 9.3.5 (master branch)
- The dispatcher tool works correctly without patches
- All patches maintain backward compatibility
- The Set ID field defaults to the domain ID if not explicitly set

