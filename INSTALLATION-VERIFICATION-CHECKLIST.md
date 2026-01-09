# Control Panel Installation Verification Checklist

This document outlines all the issues found during installation testing and how to verify they are fixed.

## Issues Found During Testing

### 1. Nested Directory Problem ✅ FIXED
**Issue:** Files ended up in `opensips-cp-master/` subdirectory instead of directly in `/var/www/opensips-cp/`

**Fix Applied:** Added cleanup before copy in `download_control_panel()` function
- Removes existing files in `OCP_WEB_ROOT` before copying
- Uses `rsync` for reliable copying

**Verification:**
- [ ] Check that `/var/www/opensips-cp/web/index.php` exists (not in opensips-cp-master subdirectory)
- [ ] Verify no nested `opensips-cp-master` directory exists

---

### 2. Missing Config Files ⚠️ SHOULD BE FIXED
**Issue:** Required config files were missing:
- `local.inc.php`
- `globals.php`
- `modules.inc.php`
- `session.inc.php`
- `db_schema.mysql`
- `config/tools/` directory
- Other config files

**Fix Applied:** 
- Fixed nested directory issue (should allow rsync to copy everything)
- Added verification check for `local.inc.php` in `configure_database()`

**Verification:**
- [ ] Check that all config files exist in `/var/www/opensips-cp/config/`
- [ ] Verify `config/tools/` directory exists and has subdirectories
- [ ] Check that `db_schema.mysql` exists

**Required Files:**
- `db.inc.php` (created by installer)
- `local.inc.php` (from source archive)
- `globals.php` (from source archive)
- `modules.inc.php` (from source archive)
- `session.inc.php` (from source archive)
- `boxes.load.php` (from source archive)
- `boxes.global.inc.php` (from source archive)
- `db_schema.mysql` (from source archive)

---

### 3. Database Schema Not Loaded ✅ FIXED
**Issue:** `configure_control_panel_database()` only checked if tables exist but didn't create them

**Fix Applied:** 
- Modified `configure_control_panel_database()` to automatically load `db_schema.mysql` if tables don't exist
- Checks for schema file existence before loading

**Verification:**
- [ ] Check that control panel database tables exist:
  - `ocp_boxes_config`
  - `ocp_tools_config`
  - `ocp_admin_privileges`
  - `ocp_dashboard`
  - `ocp_monitoring_stats`
  - etc.
- [ ] Verify admin user exists in `ocp_admin_privileges` table

**SQL Check:**
```sql
SHOW TABLES LIKE 'ocp%';
SELECT COUNT(*) FROM ocp_admin_privileges;
```

---

### 4. Patched Files Not Applied ✅ SHOULD WORK
**Issue:** Domain tool patches weren't applied because we manually fixed files

**Fix Applied:** 
- `apply_domain_tool_fixes()` function exists and should run on clean install
- Patched files exist in `control-panel-patched/` directory

**Verification:**
- [ ] Check that patched files are in place:
  - `/var/www/opensips-cp/web/tools/system/domains/domains.php`
  - `/var/www/opensips-cp/web/tools/system/domains/template/domains.main.php`
  - `/var/www/opensips-cp/web/tools/system/domains/template/domains.form.php`

**Content Checks:**
- [ ] `domains.php` INSERT query includes `setid`
- [ ] `domains.php` UPDATE query includes `setid`
- [ ] `domains.main.php` shows "Set ID" column in table
- [ ] `domains.main.php` includes `form_init_status()` JavaScript
- [ ] `domains.form.php` includes "Set ID" input field

---

### 5. Incomplete Patched File ✅ FIXED
**Issue:** INSERT query in `domains.php` was missing `setid` field support

**Fix Applied:** 
- Updated `control-panel-patched/web/tools/system/domains/domains.php`
- INSERT query now includes `setid` field
- Added POST request check
- Added auto-set setid = id if setid was 0

**Verification:**
- [ ] Check INSERT query includes `setid`:
  ```bash
  grep -A 10 "if.*action.*add" /var/www/opensips-cp/web/tools/system/domains/domains.php | grep -q "setid"
  ```
- [ ] Test adding a new domain and verify setid is saved

---

## Verification Script

Use the automated verification script:
```bash
sudo ./verify-control-panel-install.sh --db-password <PASSWORD>
```

The script checks:
1. ✅ Directory structure
2. ✅ Required config files
3. ✅ Web files
4. ✅ File permissions
5. ✅ Database connection
6. ✅ Database tables
7. ✅ Admin user
8. ✅ Patched files (content verification)
9. ✅ Apache configuration
10. ✅ HTTP accessibility

---

## Manual Verification Steps

If you prefer manual verification:

### 1. Check File Structure
```bash
# Check main directories
ls -la /var/www/opensips-cp/
ls -la /var/www/opensips-cp/config/
ls -la /var/www/opensips-cp/web/

# Check no nested directory exists
test ! -d /var/www/opensips-cp/opensips-cp-master && echo "OK" || echo "NESTED DIRECTORY EXISTS!"
```

### 2. Check Config Files
```bash
# Required config files
test -f /var/www/opensips-cp/config/local.inc.php && echo "OK" || echo "MISSING!"
test -f /var/www/opensips-cp/config/globals.php && echo "OK" || echo "MISSING!"
test -f /var/www/opensips-cp/config/db_schema.mysql && echo "OK" || echo "MISSING!"
test -d /var/www/opensips-cp/config/tools && echo "OK" || echo "MISSING!"
```

### 3. Check Database
```bash
mysql -u opensips -p'<PASSWORD>' opensips -e "SHOW TABLES LIKE 'ocp%';"
mysql -u opensips -p'<PASSWORD>' opensips -e "SELECT COUNT(*) FROM ocp_admin_privileges;"
```

### 4. Check Patched Files
```bash
# Check INSERT query has setid
grep -q "setid.*INSERT INTO\|INSERT INTO.*setid" /var/www/opensips-cp/web/tools/system/domains/domains.php && echo "OK" || echo "MISSING!"

# Check UPDATE query has setid
grep -q "setid.*UPDATE\|UPDATE.*setid" /var/www/opensips-cp/web/tools/system/domains/domains.php && echo "OK" || echo "MISSING!"

# Check table shows Set ID column
grep -q "Set ID" /var/www/opensips-cp/web/tools/system/domains/template/domains.main.php && echo "OK" || echo "MISSING!"

# Check form has Set ID field
grep -q "Set ID" /var/www/opensips-cp/web/tools/system/domains/template/domains.form.php && echo "OK" || echo "MISSING!"
```

### 5. Check Apache
```bash
systemctl status apache2
apache2ctl configtest
curl -I http://localhost/
```

### 6. Test Login
- Open browser: `http://<SERVER_IP>/`
- Should see login page (not blank screen, not 500 error)
- Login with: `admin` / `opensips`
- Should successfully log in (not blank screen)

### 7. Test Domain Tool
- Navigate to domain tool
- Should see "ID" and "Set ID" columns in table
- "Add New Domain" button should activate when typing in domain field
- Set ID field should be visible in add/edit form
- Adding a domain should save setid correctly

---

## Expected Outcomes

### Successful Installation:
- ✅ All files in correct locations (no nested directories)
- ✅ All config files present
- ✅ Database tables created
- ✅ Admin user exists
- ✅ Patched files applied correctly
- ✅ Apache running and accessible
- ✅ Login page works
- ✅ Domain tool shows Set ID column
- ✅ Domain tool saves setid correctly

### Common Issues:
- ❌ Nested directory: Files in wrong location
- ❌ Missing config files: 500 errors, blank screens
- ❌ Missing database tables: Login fails with database errors
- ❌ Unpatched files: Domain tool doesn't show setid, button doesn't activate
- ❌ Permission issues: 403 Forbidden errors

---

## Next Steps After Verification

If verification passes:
1. ✅ Installation is complete and correct
2. Test domain tool functionality:
   - Add a new domain with setid
   - Edit existing domain
   - Verify setid is saved and displayed correctly

If verification fails:
1. Review failed checks
2. Check error logs: `/var/log/apache2/error.log`
3. Re-run installer or fix issues manually
4. Re-run verification script

