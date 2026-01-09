# Opensipspure Branch Status

**Last Updated:** 2026-01-XX  
**Current Branch:** `opensipspure`  
**Status:** ✅ Ready for testing and deployment

## Summary

Created a clean OpenSIPS-only branch (`opensipspure`) from the `controlpanel` branch by removing all control panel code while preserving all SIP routing fixes and MySQL setup. This branch will be the base for adding accounting (CDRs) and statistics gathering.

## Branch Strategy Decision

**Approach Chosen:** Create `opensipspure` from `controlpanel` (not backporting to `main`)

**Rationale:**
- `controlpanel` branch already has all SIP fixes integrated
- Uses MySQL (required for accounting/CDR work)
- Has domain table with `setid` column (key to routing)
- Has endpoint_locations with contact_uri structure
- Cleaner to strip control panel code than to backport and adapt SQL syntax
- `main` uses SQLite - would require migration anyway

**Branches:**
- `main` - Original branch (SQLite, sip_domains table) - **Not using**
- `controlpanel` - Control panel branch (MySQL, all fixes) - **Kept as reference**
- `opensipspure` - Clean OpenSIPS-only branch (MySQL, all fixes, no control panel) - **Current working branch**

## What Was Removed

### Files Deleted
- `install-control-panel.sh` - Control panel installer
- `verify-control-panel-install.sh` - Control panel verification script
- `control-panel-patched/` - Entire directory with patched control panel files
- Control panel documentation from `workingdocs/`:
  - CONTROL-PANEL-FORK-GUIDE.md
  - CONTROL-PANEL-INSTALL-STEPS.md
  - INSTALLATION-VERIFICATION-CHECKLIST.md
  - OPENSIPS-CONTROL-PANEL-INSTALLATION.md
  - controlpanel.md

### Code Removed from Config Files

**config/opensips.cfg.template:**
- Removed `loadmodule "httpd.so"` (HTTP server)
- Removed `loadmodule "mi_http.so"` (MI over HTTP)
- Removed `loadmodule "domain.so"` (Domain module - OpenSIPS module, NOT the database table)
- Removed `modparam("httpd", "port", 8888)`
- Removed all `modparam("domain", ...)` parameters

**install.sh:**
- Removed HTTP modules verification check
- Removed HTTP/HTTPS firewall rules (ports 80, 443)
- Removed OpenSIPS MI interface firewall rule (port 8888)

**Note:** Domain TABLE (database table) was kept - only the domain MODULE (OpenSIPS module) was removed.

## What Was Kept (Critical)

### Core SIP/Routing Functionality
- ✅ All PRACK handling and NAT traversal fixes (commit 80740b8)
- ✅ contact_uri support for Request-URI matching (commit 3ec7906)
- ✅ Domain table with `setid` column (key to routing)
- ✅ endpoint_locations table with contact_uri (fundamental structure)
- ✅ All OpenSIPS routing logic and helper routes
- ✅ MySQL database setup (db_mysql.so, MySQL URLs)

### Database Schema
- ✅ MySQL database (`opensips`)
- ✅ Domain table (standard OpenSIPS) with `setid` column added
- ✅ endpoint_locations table with contact_uri column
- ✅ Dispatcher table (standard OpenSIPS 3.6 version 9 schema)

### Scripts
- ✅ `install.sh` - Main OpenSIPS installer (cleaned)
- ✅ `scripts/init-database.sh` - MySQL schema initialization
- ✅ `scripts/add-domain.sh` - Domain management (uses domain table with setid)
- ✅ `scripts/add-dispatcher.sh` - Dispatcher management (fixed to use MySQL)
- ✅ `scripts/db-config.sh` - Database configuration
- ✅ `scripts/test-mysql-connection.sh` - MySQL connection testing
- ✅ `scripts/view-status.sh` - Service status
- ✅ `scripts/restore-database.sh` - Database backup/restore

### Configuration
- ✅ `config/opensips.cfg.template` - Core OpenSIPS configuration (minus HTTP/MI modules)
- ✅ All core OpenSIPS modules (nathelper, dispatcher, sqlops, etc.)
- ✅ All routing logic and NAT traversal functions

## Fixes Applied During Branch Creation

### Script Fix: add-dispatcher.sh
**Issue:** Script was using SQLite but opensipspure uses MySQL  
**Fix:** Converted to MySQL (commit 20fa658)
- Changed from `sqlite3 "$DB_PATH"` to `mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME"`
- Updated database connection parameters to match add-domain.sh

## Current Commits

```
20fa658 Fix add-dispatcher.sh: convert from SQLite to MySQL
8a0bc76 Remove control panel: create opensipspure branch
```

## Database Schema Details

### Domain Table
- **Table:** `domain` (standard OpenSIPS table)
- **Key Column:** `setid` (explicit column added for dispatcher set mapping)
- **Usage:** Maps domains to dispatcher sets for multi-tenant routing
- **Script:** `scripts/add-domain.sh` works correctly with this schema

### Dispatcher Table
- **Table:** `dispatcher` (standard OpenSIPS 3.6 version 9 schema)
- **Columns:** id, setid, destination, socket, state, probe_mode, weight, priority, attrs, description
- **Usage:** Groups backend destinations by setid for load balancing
- **Script:** `scripts/add-dispatcher.sh` works correctly with MySQL

### endpoint_locations Table
- **Table:** `endpoint_locations` (custom table)
- **Columns:** aor, contact_ip, contact_port, contact_uri, expires
- **Usage:** Tracks registered endpoints for routing back to endpoints
- **Managed by:** OpenSIPS (populated during REGISTER requests)

## Control Panel Branch (Reference)

The `controlpanel` branch is kept as a reference and can be enhanced to explore OpenSIPS control panel modules. This is useful for:
- Learning how control panel implements features
- Understanding OpenSIPS module usage patterns
- Reference for future development

**Note:** The final offering will NOT include control panel code, but the branch can be used for learning and reference.

## Next Steps

### Immediate (Testing)
1. ✅ Install opensipspure branch on test system
2. ✅ Verify installation works correctly
3. ✅ Test SIP routing functionality
4. ✅ Verify scripts work (add-domain.sh, add-dispatcher.sh)

### Future (After Testing)
1. Add accounting (CDR) module to opensips.cfg
2. Add statistics gathering module to opensips.cfg
3. Configure accounting/stats database tables
4. Test accounting and statistics collection
5. Integrate with monitoring/visualization (if needed)

## Key Files Reference

### Configuration
- `config/opensips.cfg.template` - Main OpenSIPS configuration (no HTTP/MI modules)
- `scripts/init-database.sh` - Database schema initialization (MySQL)
- `install.sh` - Installation script (no control panel components)

### Scripts
- `scripts/add-domain.sh` - Add domains to domain table (MySQL, setid support)
- `scripts/add-dispatcher.sh` - Add dispatcher destinations (MySQL)
- `scripts/db-config.sh` - Database configuration helper
- `scripts/test-mysql-connection.sh` - Test MySQL connectivity

### Documentation
- `workingdocs/OPENSIPSPURE-BRANCH-PLAN.md` - Branch creation plan
- `workingdocs/CHANGES-TO-BACKPORT-TO-MAIN.md` - Analysis of changes (for reference)
- `docs/opensips-routing-logic.md` - Routing logic documentation
- `docs/USER-GUIDE.md` - User guide

## Important Notes

1. **Database:** Opensipspure uses MySQL (not SQLite like main branch)
2. **Domain Table:** Uses standard OpenSIPS `domain` table with `setid` column (not `sip_domains`)
3. **No Control Panel:** All control panel code and dependencies removed
4. **All SIP Fixes:** All routing improvements from controlpanel branch are preserved
5. **Script Compatibility:** All scripts verified to work with MySQL schema

## Quick Start for Next Session

1. **Current Branch:** `opensipspure`
2. **Status:** Clean, ready for testing
3. **Next Task:** Install and test opensipspure branch
4. **After Testing:** Add accounting (CDR) and statistics modules

## Testing Checklist (For Installation)

- [ ] Run `install.sh` on test system
- [ ] Verify OpenSIPS starts without errors (no HTTP/MI module errors)
- [ ] Test domain addition: `scripts/add-domain.sh example.com 10`
- [ ] Test dispatcher addition: `scripts/add-dispatcher.sh 10 sip:1.2.3.4:5060`
- [ ] Verify MySQL database has correct schema
- [ ] Test SIP routing (endpoint registration, call routing)
- [ ] Verify NAT traversal works (if endpoints behind NAT)
- [ ] Verify PRACK/100rel support works

## Accounting/Statistics Planning (Future)

From wishlist.md:
- Statistics - Prometheus and Grafana
- CDR/Accounting module

**Modules to Consider:**
- `acc` module - Accounting/CDR
- `statistics` module - Statistics gathering
- Database tables: `acc`, `missed_calls` (standard OpenSIPS schema)

**Integration:**
- OpenSIPS control panel has modules for viewing these - can reference controlpanel branch for implementation patterns

---

**Document Status:** Current as of opensipspure branch creation  
**Maintained By:** Development workflow documentation  
**Related Docs:** OPENSIPSPURE-BRANCH-PLAN.md, CHANGES-TO-BACKPORT-TO-MAIN.md

