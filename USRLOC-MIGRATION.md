# usrloc Module Migration Summary

**Date:** January 2026  
**Branch:** `fulldb`  
**Status:** ✅ Migration complete, ready for testing

## Overview

Migrated from custom `endpoint_locations` table to OpenSIPS usrloc module's `location` table for automatic endpoint registration management.

## Changes Made

### 1. Database Initialization (`scripts/init-database.sh`)

**Updated to:**
- Load full OpenSIPS 3.6.3 schema from `dbsource/opensips-3.6.3-sqlite3.sql`
- Add custom `sip_domains` table (still required for routing)
- Keep `endpoint_locations` table as fallback/legacy support
- Ensure `location` table (usrloc) is created with correct version (1013)

**Key Changes:**
- Loads full schema first, then adds custom tables
- Maintains backward compatibility with legacy `endpoint_locations` table

### 2. OpenSIPS Configuration (`config/opensips.cfg.template`)

#### Module Loading
- ✅ Added `loadmodule "usrloc.so"`

#### Module Parameters
- ✅ Added usrloc configuration:
  ```opensips
  modparam("usrloc", "db_url", "sqlite:///etc/opensips/opensips.db")
  modparam("usrloc", "db_mode", 2)  # Write-back mode for performance
  modparam("usrloc", "db_table", "location")
  modparam("usrloc", "timer_interval", 60)
  ```

#### REGISTER Handling (lines 279-390)
- ✅ Replaced manual `INSERT INTO endpoint_locations` with `save("location")`
- ✅ Kept legacy table insert for fallback/compatibility
- ✅ usrloc `save()` automatically:
  - Extracts username and domain from To header
  - Extracts contact from Contact header
  - Handles expires from Expires header
  - Stores in `location` table with NAT support (`received` parameter)

#### Endpoint Lookup (`route[ENDPOINT_LOOKUP]`, lines 579-680)
- ✅ Updated to use usrloc `lookup("location")` as primary method
- ✅ Falls back to legacy `endpoint_locations` table if usrloc lookup fails
- ✅ Also queries `location` table directly as secondary fallback
- ✅ Extracts IP and port from contact URI returned by usrloc

#### Response Logging (`onreply_route`, lines 864-910)
- ✅ Updated to use `route[ENDPOINT_LOOKUP]` for consistency
- ✅ Uses usrloc/legacy hybrid lookup for diagnostic logging

#### NAT IP Fix (`route[RELAY]`, lines 744-860)
- ✅ Already uses `route[ENDPOINT_LOOKUP]`, so automatically benefits from usrloc
- ✅ No changes needed

## How It Works

### Registration Flow (with usrloc)

1. **Endpoint sends REGISTER:**
   ```
   REGISTER sip:example.com SIP/2.0
   To: <sip:user@example.com>
   Contact: <sip:user@192.168.1.100:5060>
   Expires: 3600
   ```

2. **OpenSIPS processes:**
   - Extracts endpoint info (IP, port, expires)
   - Calls `save("location")` - usrloc automatically stores:
     - `username` = "user"
     - `domain` = "example.com"
     - `contact` = "sip:user@192.168.1.100:5060"
     - `expires` = current_time + 3600 (Unix timestamp)
     - `received` = NAT IP if applicable
   - Also stores in legacy `endpoint_locations` table (fallback)

3. **Database contains:**
   - `location` table: Full usrloc entry with all fields
   - `endpoint_locations` table: Legacy entry (for compatibility)

### Endpoint Lookup Flow (with usrloc)

1. **Need to find endpoint for user "user":**
   - Set Request-URI: `sip:user@example.com`
   - Call `lookup("location")`
   - usrloc finds matching contact in `location` table
   - Sets `$du` = `sip:user@192.168.1.100:5060`
   - Extract IP and port from `$du`

2. **Fallback if usrloc fails:**
   - Query legacy `endpoint_locations` table
   - Or query `location` table directly via SQL

## Benefits of usrloc Module

1. **Automatic Management:**
   - ✅ Automatic expiration handling
   - ✅ Automatic contact updates
   - ✅ Built-in NAT traversal support (`received` parameter)

2. **Standard Approach:**
   - ✅ Uses OpenSIPS standard location table
   - ✅ Compatible with other OpenSIPS modules
   - ✅ Well-tested and maintained

3. **Performance:**
   - ✅ Write-back mode (db_mode=2) for better performance
   - ✅ Cached lookups in memory
   - ✅ Periodic database sync (timer_interval)

4. **Features:**
   - ✅ Multiple contacts per AoR support
   - ✅ Path header support
   - ✅ SIP instance support
   - ✅ Q value support for contact prioritization

## Testing Checklist

### 1. Database Initialization
```bash
# Test database initialization
sudo ./scripts/init-database.sh

# Verify tables exist
sqlite3 /var/lib/opensips/routing.db ".tables"

# Should show: location, endpoint_locations, sip_domains, dispatcher, version, etc.
```

### 2. Configuration Syntax
```bash
# Check OpenSIPS config syntax
sudo opensips -C -f /etc/opensips/opensips.cfg

# Should show no errors
```

### 3. Endpoint Registration
```bash
# Register an endpoint
# Monitor logs
sudo journalctl -u opensips -f

# Expected log messages:
# - "REGISTER received from ..."
# - "Stored endpoint location via usrloc: ..."
# - "Also stored in legacy endpoint_locations table: ..."

# Verify in database
sqlite3 /var/lib/opensips/routing.db "SELECT * FROM location WHERE username='USERNAME';"
sqlite3 /var/lib/opensips/routing.db "SELECT * FROM endpoint_locations WHERE aor LIKE 'USERNAME@%';"
```

### 4. Endpoint Lookup
```bash
# Send OPTIONS from Asterisk to registered endpoint
# Monitor logs for:
# - "ENDPOINT_LOOKUP: Looking up user=..."
# - "ENDPOINT_LOOKUP: Trying usrloc lookup for AoR=..."
# - "ENDPOINT_LOOKUP: usrloc lookup found contact: ..."
# - "ENDPOINT_LOOKUP: Success - IP=..., Port=..."

# Verify routing works correctly
```

### 5. NAT Traversal
```bash
# Test with endpoint behind NAT
# Verify usrloc stores 'received' parameter correctly
sqlite3 /var/lib/opensips/routing.db "SELECT contact, received FROM location WHERE username='USERNAME';"

# Should show:
# contact: sip:user@192.168.1.100:5060 (private IP)
# received: sip:user@PUBLIC_IP:PORT (NAT IP)
```

### 6. Expiration Handling
```bash
# Wait for registration to expire
# Verify usrloc automatically removes expired entries
# Check logs for expiration messages
```

## Rollback Plan

If issues are encountered:

1. **Disable usrloc temporarily:**
   - Comment out `loadmodule "usrloc.so"`
   - Comment out usrloc modparam lines
   - System will fall back to legacy `endpoint_locations` table

2. **Revert code changes:**
   ```bash
   git checkout HEAD~1 config/opensips.cfg.template
   ```

3. **Keep legacy table:**
   - Legacy `endpoint_locations` table is still populated
   - All lookups fall back to legacy table if usrloc fails

## Known Limitations

1. **Username-only lookup:**
   - usrloc `lookup()` requires full Request-URI
   - For username-only lookups, we fall back to SQL queries
   - This is acceptable for our use case

2. **Legacy table still populated:**
   - Both tables are updated during registration
   - This provides fallback but creates some duplication
   - Can be removed once usrloc is fully tested

3. **Contact URI parsing:**
   - Need to extract IP/port from contact URI using regex
   - usrloc returns full contact URI, not separate IP/port
   - This is handled in `route[ENDPOINT_LOOKUP]`

## Next Steps

1. **Test thoroughly:**
   - Register multiple endpoints
   - Test OPTIONS routing from Asterisk
   - Test NOTIFY routing
   - Test NAT traversal scenarios

2. **Monitor performance:**
   - Check database sync timing
   - Monitor memory usage
   - Verify lookup performance

3. **Remove legacy table (after testing):**
   - Once confident in usrloc, remove `endpoint_locations` table
   - Remove legacy INSERT in REGISTER handling
   - Simplify `route[ENDPOINT_LOOKUP]` to use usrloc only

4. **Documentation:**
   - Update `OPENSIPS-MIGRATION-KNOWLEDGE.md` with usrloc findings
   - Update `PROJECT-STATUS.md` with migration status

## Files Modified

- ✅ `scripts/init-database.sh` - Load full schema + custom tables
- ✅ `config/opensips.cfg.template` - Added usrloc module and updated logic

## Files Created

- ✅ `USRLOC-MIGRATION.md` - This document
- ✅ `DATABASE-SCHEMA-COMPARISON.md` - Schema comparison
- ✅ `DATABASE-UPDATE-SUMMARY.md` - Update summary

## References

- OpenSIPS usrloc module documentation
- OpenSIPS 3.6.3 database schema
- `OPENSIPS-MIGRATION-KNOWLEDGE.md` - Migration knowledge base

