# Opensipspure Branch Creation Plan

**Goal:** Create `opensipspure` branch from `controlpanel`, stripping out all control panel code while keeping core SIP fixes and MySQL setup.

**Rationale:** Instead of backporting fixes from controlpanel → main (SQLite), start with controlpanel (which has all fixes + MySQL) and remove control panel components. This is cleaner and preserves all the improvements.

## What to KEEP ✅

### Core SIP/Routing Functionality
- ✅ All PRACK handling and NAT traversal fixes (commit 80740b8)
- ✅ contact_uri support for Request-URI matching (commit 3ec7906)
- ✅ Domain table with `setid` column (key to routing)
- ✅ endpoint_locations table structure with contact_uri (fundamental)
- ✅ All OpenSIPS routing logic and helper routes
- ✅ MySQL database setup (db_mysql.so, MySQL URLs)
- ✅ All core modules (nathelper, dispatcher, sqlops, etc.)

### Database Schema
- ✅ MySQL database (opensips)
- ✅ Domain table with setid column
- ✅ endpoint_locations table with contact_uri column
- ✅ Dispatcher table (standard OpenSIPS schema)

### Scripts
- ✅ install.sh (main OpenSIPS installer)
- ✅ scripts/init-database.sh (MySQL schema)
- ✅ scripts/add-domain.sh (domain management)
- ✅ scripts/add-dispatcher.sh
- ✅ scripts/db-config.sh
- ✅ scripts/test-mysql-connection.sh
- ✅ scripts/view-status.sh
- ✅ scripts/restore-database.sh

### Configuration
- ✅ config/opensips.cfg.template (minus HTTP/MI/domain module)
- ✅ All core OpenSIPS configuration

### Documentation
- ✅ docs/opensips-routing-logic.md
- ✅ docs/USER-GUIDE.md (if not control panel specific)
- ✅ docs/OPENSIPS-LOGIC-DIAGRAM.md
- ✅ Core documentation

---

## What to REMOVE ❌

### Control Panel Files
- ❌ `install-control-panel.sh` - Control panel installer
- ❌ `verify-control-panel-install.sh` - Control panel verification
- ❌ `control-panel-patched/` - Entire directory with patched files

### OpenSIPS Config - HTTP/MI Modules
From `config/opensips.cfg.template`, remove:
- ❌ `loadmodule "httpd.so"` (line ~54)
- ❌ `loadmodule "mi_http.so"` (line ~55)
- ❌ `loadmodule "domain.so"` (line ~57)
- ❌ `modparam("httpd", "port", 8888)` (line ~69)
- ❌ `modparam("domain", ...)` - All domain module parameters (lines ~71-75)

**Note:** Keep `domain` TABLE (database table), just remove the `domain.so` MODULE (OpenSIPS module used by control panel).

### Control Panel Documentation (from workingdocs/)
- ❌ CONTROL-PANEL-FORK-GUIDE.md
- ❌ CONTROL-PANEL-INSTALL-STEPS.md
- ❌ OPENSIPS-CONTROL-PANEL-INSTALLATION.md
- ❌ INSTALLATION-VERIFICATION-CHECKLIST.md
- ❌ MANUAL-INSTALL-STEPS.md (if control panel specific)
- ❌ controlpanel.md
- ❌ INSTALL-REVIEW.md (if control panel specific)

### Other Files to Review
- ❌ Any references to control panel in install.sh (check if any)

---

## Files to MODIFY

### 1. config/opensips.cfg.template

**Remove these lines:**
```opensips
# HTTP and MI modules (for control panel)
loadmodule "httpd.so"
loadmodule "mi_http.so"
# Domain module (for control panel domain management)
loadmodule "domain.so"
```

```opensips
# --- HTTP server (for MI interface) ---
modparam("httpd", "port", 8888)

# --- Domain module (for control panel) ---
modparam("domain", "db_url", "mysql://opensips:your-password@localhost/opensips")
modparam("domain", "domain_table", "domain")
modparam("domain", "domain_col", "domain")
modparam("domain", "db_mode", 1)
```

**Keep:**
- All other modules (nathelper, db_mysql, sqlops, dispatcher, etc.)
- All routing logic
- Domain TABLE queries (SQL queries to domain table)
- All NAT traversal functions
- All PRACK handling

### 2. install.sh

**Found control panel references:**
- Lines ~220-224: HTTP modules verification (for control panel)
- Lines ~358-371: HTTP/HTTPS firewall rules and port 8888 (for control panel)

**Action:** 
- Remove HTTP modules verification check
- Remove HTTP/HTTPS firewall rules (80, 443)
- Remove port 8888 firewall rule
- Keep MySQL setup and all other functionality

---

## Step-by-Step Process

### Step 1: Create Branch from controlpanel
```bash
git checkout controlpanel
git checkout -b opensipspure
```

### Step 2: Remove Control Panel Files
```bash
git rm install-control-panel.sh
git rm verify-control-panel-install.sh
git rm -r control-panel-patched/
```

### Step 3: Remove Control Panel Documentation
```bash
cd workingdocs/
git rm CONTROL-PANEL-FORK-GUIDE.md
git rm CONTROL-PANEL-INSTALL-STEPS.md
git rm OPENSIPS-CONTROL-PANEL-INSTALLATION.md
git rm INSTALLATION-VERIFICATION-CHECKLIST.md
git rm controlpanel.md
# Review and remove other control panel specific docs
cd ..
```

### Step 4: Clean opensips.cfg.template
- Remove HTTP/MI/domain module loading
- Remove HTTP/domain module parameters
- Keep all routing logic and SQL queries to domain table

### Step 5: Review install.sh
- Check for control panel references
- Remove if any, keep MySQL setup

### Step 6: Commit Changes
```bash
git add -A
git commit -m "Remove control panel: create opensipspure branch

- Remove control panel installer and verification scripts
- Remove control-panel-patched directory
- Remove HTTP/MI/domain modules from OpenSIPS config
- Remove control panel documentation
- Keep all SIP routing fixes and MySQL setup
- Keep domain table with setid and endpoint_locations structure"
```

### Step 7: Verify
- [ ] OpenSIPS config loads without HTTP/MI/domain modules
- [ ] Database schema is correct (domain table with setid, endpoint_locations with contact_uri)
- [ ] All SIP routing fixes are present (PRACK, NAT traversal, contact_uri)
- [ ] No control panel references remain
- [ ] Installer works without control panel components

---

## Key Points

1. **Domain Table vs Domain Module:**
   - **KEEP:** Domain TABLE (database table with setid) - used for routing
   - **REMOVE:** Domain MODULE (domain.so) - used by control panel for domain management

2. **MySQL Setup:**
   - KEEP MySQL (not SQLite) - controlpanel branch uses MySQL
   - This is the direction for the final offering

3. **Core Functionality:**
   - All SIP fixes remain intact
   - All routing logic remains intact
   - Only control panel management interface is removed

4. **Database Schema:**
   - Domain table with setid column (key to routing)
   - endpoint_locations with contact_uri (fundamental)
   - All standard OpenSIPS tables (dispatcher, version, etc.)

---

## Verification Checklist

After creating the branch:

- [ ] `config/opensips.cfg.template` has no httpd/mi_http/domain.so modules
- [ ] `config/opensips.cfg.template` has all NAT traversal functions
- [ ] `config/opensips.cfg.template` has PRACK handling
- [ ] `config/opensips.cfg.template` has contact_uri support
- [ ] `config/opensips.cfg.template` queries domain table (not using domain module)
- [ ] `scripts/init-database.sh` creates domain table with setid
- [ ] `scripts/init-database.sh` creates endpoint_locations with contact_uri
- [ ] No control panel files remain
- [ ] No control panel documentation remains
- [ ] `install.sh` has no control panel references
- [ ] MySQL database setup is intact

---

## Expected Result

A clean branch (`opensipspure`) that:
- Contains all SIP routing fixes from controlpanel
- Uses MySQL (not SQLite)
- Has domain table with setid for routing
- Has endpoint_locations with contact_uri
- Has no control panel code or dependencies
- Ready to be the base for accounting/CDR and statistics work

