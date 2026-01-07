# Database Schema Update Summary

**Date:** January 2026  
**Context:** Full OpenSIPS 3.6.3 database schema loaded from `dbsource/opensips-3.6.3-sqlite3.sql`

## Current Situation

You've loaded the complete OpenSIPS 3.6.3 standard database schema. This includes many tables we weren't using before, most importantly:

- ✅ **`location` table** (usrloc module, version 1013) - Could replace our custom `endpoint_locations`
- ✅ **`dispatcher` table** (version 9) - Matches our schema, compatible
- ⚠️ **`domain` table** (version 4) - Different from our custom `sip_domains` (missing `dispatcher_setid`)

## Tables Currently Used in Code

### 1. `sip_domains` (Custom Table)
**Status:** ✅ **KEEP** - Required for routing logic

**Used in:**
- `config/opensips.cfg.template` - `route[DOMAIN_CHECK]` (line 432)
- `scripts/add-domain.sh` - Adds domains
- `scripts/init-database.sh` - Creates table

**Why keep:**
- Standard `domain` table doesn't have `dispatcher_setid` field
- We need to link domains to dispatcher sets for routing
- Custom table is essential for our routing logic

### 2. `endpoint_locations` (Custom Table)
**Status:** 🤔 **EVALUATE** - Could migrate to usrloc `location` table

**Used in:**
- `config/opensips.cfg.template`:
  - REGISTER handling (line 363) - Stores endpoint info
  - `route[ENDPOINT_LOOKUP]` (lines 571, 589, 601, 606) - Queries endpoint
  - `route[RELAY]` (line 768) - NAT IP lookup for ACK/BYE/NOTIFY
  - Response handling (lines 829, 839) - Logging endpoint IPs

**Decision needed:**
- Keep custom table? (continue current approach)
- Migrate to usrloc `location` table? (use usrloc module)
- Hybrid? (use both)

### 3. `dispatcher` (Standard Table)
**Status:** ✅ **COMPATIBLE** - Standard schema works fine

**Used in:**
- Dispatcher module (automatic)
- `scripts/add-dispatcher.sh` - Adds destinations
- `scripts/init-database.sh` - Creates table

**Note:**
- Standard schema uses `CHAR()` types vs our `TEXT`
- Both are compatible (SQLite treats them similarly)
- Standard schema is fine

## Required Actions

### Immediate: Update `init-database.sh`

The initialization script needs to be updated to work with the new schema. Options:

#### Option A: Load Full Schema + Add Custom Tables
```bash
# Load full OpenSIPS schema first
sqlite3 "$DB_PATH" < dbsource/opensips-3.6.3-sqlite3.sql

# Then add our custom tables
sqlite3 "$DB_PATH" <<EOF
-- Our custom domain routing table
CREATE TABLE IF NOT EXISTS sip_domains (
    domain TEXT PRIMARY KEY,
    dispatcher_setid INTEGER NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    comment TEXT
);
CREATE INDEX IF NOT EXISTS idx_sip_domains_enabled ON sip_domains(enabled);

-- Keep endpoint_locations if not migrating to usrloc
CREATE TABLE IF NOT EXISTS endpoint_locations (
    aor TEXT PRIMARY KEY,
    contact_ip TEXT NOT NULL,
    contact_port TEXT NOT NULL,
    expires TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_endpoint_locations_expires ON endpoint_locations(expires);
EOF
```

#### Option B: Keep Current Approach (Custom Tables Only)
Continue using current `init-database.sh` which creates:
- `version` table
- `sip_domains` (custom)
- `dispatcher` (standard schema)
- `endpoint_locations` (custom)

**Recommendation:** Option A - Load full schema, then add custom tables. This gives you access to all OpenSIPS tables while maintaining compatibility.

### Decision Point: usrloc Module Evaluation

You're evaluating the usrloc module. Here's what you need to decide:

#### If Using usrloc Module:
1. **Load usrloc module** in `config/opensips.cfg.template`:
   ```opensips
   loadmodule "usrloc.so"
   modparam("usrloc", "db_url", "sqlite:///etc/opensips/opensips.db")
   modparam("usrloc", "db_mode", 2)  # Write-back mode
   ```

2. **Update REGISTER handling** (lines 262-372):
   - Replace manual `INSERT INTO endpoint_locations` with `save("location")`
   - Remove custom SQL queries

3. **Update endpoint lookup** (`route[ENDPOINT_LOOKUP]`, lines 553-636):
   - Replace manual `SELECT` queries with `lookup("location")`
   - Extract IP/port from `contact` URI

4. **Keep or remove `endpoint_locations` table:**
   - If fully migrating: Remove custom table
   - If hybrid: Keep both (data duplication)

#### If Keeping Custom Table:
1. **No code changes needed** - Current approach works
2. **Consider adding cleanup** - Remove expired entries periodically
3. **Keep `endpoint_locations` table** in init script

## Recommended Next Steps

1. **Update `init-database.sh`:**
   - Load full OpenSIPS schema from `dbsource/opensips-3.6.3-sqlite3.sql`
   - Add custom `sip_domains` table
   - Decide: Keep `endpoint_locations` or migrate to usrloc

2. **Test usrloc module:**
   - Load module in config
   - Test REGISTER handling with `save()`
   - Test endpoint lookup with `lookup()`
   - Verify NAT traversal works correctly

3. **Make decision:**
   - If usrloc works well: Migrate code to use it
   - If issues: Keep custom table approach
   - Document decision in `DATABASE-SCHEMA-COMPARISON.md`

4. **Update documentation:**
   - Update `OPENSIPS-MIGRATION-KNOWLEDGE.md` with usrloc findings
   - Update `PROJECT-STATUS.md` with decision
   - Update `scripts/init-database.sh` comments

## Code Locations to Review

### If Migrating to usrloc:

**REGISTER Handling:**
- File: `config/opensips.cfg.template`
- Lines: 262-372
- Change: Replace `sql_query()` INSERT with `save("location")`

**Endpoint Lookup:**
- File: `config/opensips.cfg.template`
- Route: `route[ENDPOINT_LOOKUP]` (lines 553-636)
- Change: Replace `sql_query()` SELECT with `lookup("location")`

**NAT IP Fix:**
- File: `config/opensips.cfg.template`
- Route: `route[RELAY]` (lines 744-801)
- Change: Use usrloc lookup instead of custom table query

**Response Logging:**
- File: `config/opensips.cfg.template`
- Route: `onreply_route` (lines 805-865)
- Change: Use usrloc lookup for endpoint IP logging

## Compatibility Notes

### Version Table
The standard schema includes version entries for all modules:
- `dispatcher` = 9 ✅ (matches our requirement)
- `location` = 1013 (usrloc module)
- `domain` = 4 (standard domain table)
- Many others (acc, subscriber, dialog, etc.)

**Action:** Ensure version table has correct entries after loading schema.

### Table Naming
- Standard uses `location` (usrloc module)
- We use `endpoint_locations` (custom)
- Both can coexist if needed

### Data Types
- Standard uses `CHAR()` for fixed-length strings
- Our custom tables use `TEXT`
- SQLite treats them similarly, both work

## Questions to Answer

1. **Will you use usrloc module?**
   - If yes: Migrate code to use `location` table
   - If no: Keep `endpoint_locations` table

2. **Do you need other OpenSIPS tables?**
   - `subscriber` - Authentication (not currently used)
   - `acc` - Accounting (not currently used)
   - `dialog` - Dialog tracking (not currently used)
   - Others - Evaluate as needed

3. **How to handle initialization?**
   - Load full schema + add custom tables? (Recommended)
   - Keep current minimal schema? (Simpler, but less flexible)

## Summary

**Current Status:**
- ✅ Full OpenSIPS 3.6.3 schema loaded
- ✅ `dispatcher` table compatible
- ✅ `sip_domains` table still needed (custom)
- 🤔 `endpoint_locations` vs `location` (usrloc) - decision needed

**Next Actions:**
1. Update `init-database.sh` to load full schema + custom tables
2. Evaluate usrloc module functionality
3. Make decision on endpoint location storage
4. Update code if migrating to usrloc
5. Test and document

