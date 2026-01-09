# Changes to Backport from controlpanel → main

**Analysis Date:** 2026-01-XX  
**Branches:** `controlpanel` → `main`  
**Purpose:** Identify SIP/config fixes that should be backported, excluding control panel work

## Summary

The `controlpanel` branch contains important SIP routing fixes that were developed alongside control panel work. These fixes should be backported to `main` since the final offering won't include the OpenSIPS Control Panel code.

## Key Changes to Backport

### 1. PRACK Handling and NAT Traversal (Commit: 80740b8) ✅ **HIGH PRIORITY**

**Files Changed:**
- `config/opensips.cfg.template`

**Changes:**
- Added `nathelper` module for NAT traversal
- Added PRACK to allowed methods
- Added PRACK handling in `route[WITHINDLG]`
- Added PRACK to NAT IP fix in `route[RELAY]`
- Added `fix_nated_contact()` in `onreply_route` for Contact header fixes
- Added `fix_nated_sdp("rewrite-media-ip")` in `onreply_route` for SDP fixes
- Added `fix_nated_register()` for REGISTER requests

**Why This Matters:**
- Fixes PRACK/100rel support (resolves snom phone issues)
- Fixes audio issues by correcting SDP IP addresses
- Enables proper NAT traversal for endpoints behind NAT
- Critical for call completion and audio quality

**Backport Method:** Cherry-pick commit `80740b8`, but will need to adapt database URLs if main uses SQLite

---

### 2. contact_uri Support for Request-URI Matching (Commit: 3ec7906) ✅ **MEDIUM PRIORITY**

**Files Changed:**
- `config/opensips.cfg.template`
- `scripts/init-database.sh`

**Changes:**
- Added `contact_uri` column to `endpoint_locations` table
- Store `contact_uri` during REGISTER (constructed as `sip:user@IP:port`)
- Retrieve and use `contact_uri` in `ENDPOINT_LOOKUP` for Request-URI matching
- Updated `BUILD_ENDPOINT_URI` to use stored `contact_uri` when available

**Why This Matters:**
- Improves Request-URI matching for endpoints
- Better support for Snom endpoints and similar devices
- More robust endpoint routing

**Backport Method:** Cherry-pick commit `3ec7906`, adapt SQL syntax for SQLite if needed

---

### 3. Domain Table Changes (Commit: 1054f22, ee9c62c) ⚠️ **NEEDS REVIEW**

**Files Changed:**
- `config/opensips.cfg.template` (domain lookup query)
- `scripts/init-database.sh` (schema changes)
- `scripts/add-domain.sh` (script updates)

**Changes:**
- Switched from custom `sip_domains` table to standard OpenSIPS `domain` table
- Added `setid` column to domain table for dispatcher set mapping
- Updated queries to use `domain.setid` instead of `sip_domains.dispatcher_setid`

**Why This Matters:**
- Uses standard OpenSIPS schema (better compatibility)
- Aligns with OpenSIPS best practices
- However: This might be tied to control panel requirements

**Decision Needed:** 
- Does `main` use `sip_domains` or `domain` table?
- Is this change necessary for the final offering?

**Backport Method:** Review if needed, may require schema migration

---

## Changes NOT to Backport (Control Panel Related)

### ❌ Exclude These:
- `install-control-panel.sh` - Control panel installer
- `verify-control-panel-install.sh` - Control panel verification
- `control-panel-patched/` - Patched control panel files
- `workingdocs/` - Working documentation (unless needed)
- HTTP/MI modules in `opensips.cfg.template` (httpd, mi_http, domain.so)
- Database URL changes if they're MySQL-specific for control panel

---

## Database Considerations

**Important:** The `controlpanel` branch uses **MySQL**, but `main` uses **SQLite**.

**Confirmed:** `main` uses SQLite (`db_sqlite.so`, `sqlite:///var/lib/opensips/routing.db`)

When backporting, you'll need to:
1. Keep SQLite database URLs in `opensips.cfg.template`
2. Adapt SQL syntax in queries (e.g., `datetime('now', '+N seconds')` vs `DATE_ADD(NOW(), INTERVAL N SECOND)`)
3. Adapt `INSERT OR REPLACE` (SQLite) vs `INSERT ... ON DUPLICATE KEY UPDATE` (MySQL)
4. Keep `db_sqlite.so` instead of `db_mysql.so`

**Recommendation:** Check what `main` currently uses before backporting.

---

## Recommended Backport Strategy

### Option 1: Cherry-pick Individual Commits (Recommended)
```bash
# Switch to main
git checkout main

# Cherry-pick PRACK/NAT fix (will need conflict resolution for database URLs)
git cherry-pick 80740b8

# Cherry-pick contact_uri support (will need conflict resolution)
git cherry-pick 3ec7906

# Review and manually apply domain table changes if needed
```

### Option 2: Manual Backport
1. Create a new branch from `main`
2. Manually apply the changes from commits `80740b8` and `3ec7906`
3. Adapt SQL syntax for SQLite if needed
4. Test thoroughly
5. Merge to `main`

---

## Checklist for Backport

- [ ] Review current `main` branch database setup (SQLite vs MySQL)
- [ ] Cherry-pick or manually apply PRACK/NAT fix (commit 80740b8)
- [ ] Adapt database URLs if main uses SQLite
- [ ] Cherry-pick or manually apply contact_uri support (commit 3ec7906)
- [ ] Adapt SQL syntax for SQLite if needed (datetime functions, INSERT syntax)
- [ ] Review domain table changes - decide if needed
- [ ] Test PRACK/100rel support
- [ ] Test NAT traversal with endpoints behind NAT
- [ ] Test audio quality with endpoints behind NAT
- [ ] Verify no control panel dependencies remain

---

## Files to Review During Backport

1. **config/opensips.cfg.template**
   - Module loading (nathelper, db_mysql vs db_sqlite)
   - Database URLs
   - PRACK handling changes
   - NAT traversal functions
   - contact_uri handling
   - Domain table queries

2. **scripts/init-database.sh**
   - Database schema (SQLite vs MySQL)
   - endpoint_locations table schema (contact_uri column)
   - Domain table schema (if applicable)

3. **scripts/add-domain.sh**
   - Domain table operations (if domain table changes are backported)

---

## Questions to Answer

1. Does `main` use SQLite or MySQL?
2. Does `main` use `sip_domains` table or standard `domain` table?
3. Should domain table changes be backported, or keep `sip_domains`?
4. Are there any other SIP fixes in controlpanel branch not listed here?

---

## Commit References

- `80740b8` - PRACK handling and NAT traversal
- `3ec7906` - contact_uri support
- `1054f22` - Domain table usage (standard domain table)
- `ee9c62c` - setid column in domain table

