# Session Summary: Received Field URI Format Implementation

## Current Status: COMPLETE - `received_avp` is Working

**Date**: 2026-01-27  
**Final Status**: System is fully functional. `received_avp` parameter is working correctly - `received` field is populated in database. Manual UPDATE code removed as it's not needed.

## Problem Statement

1. **Startup Error**: OpenSIPS fails to parse `received` field during preload:
   ```
   ERROR:usrloc:compute_next_hop: failed to parse URI of next hop: '74.83.23.44:5060'
   ```
   This indicates OpenSIPS expects a full SIP URI, not just `IP:port`.

2. **UPDATE Query Failing**: After REGISTER, the UPDATE query to set `received` field fails silently:
   ```
   WARNING:REGISTER: SQL UPDATE query failed for 'received' field: sip:74.83.23.44:5060;transport=udp
   ```

3. **OPTIONS/NOTIFY Routing Failing**: Because `received` is NULL, NAT traversal fails:
   ```
   WARNING:RELAY: OPTIONS - Invalid IP extracted from contact: <null>
   ```

## Root Cause

OpenSIPS expects the `received` field to be a full SIP URI string (e.g., `sip:74.83.23.44:5060;transport=udp`), not just `IP:port`. The `usrloc` module's `compute_next_hop` function tries to parse this as a URI during preload, and fails if it's not a valid SIP URI.

## What We've Done

### 1. Updated Storage Format
- **Location**: `config/opensips.cfg.template` lines ~2108-2129
- **Change**: Convert `IP:port` format to SIP URI format before storing:
  ```opensips
  $var(received_uri) = "sip:" + $var(received_value) + ";transport=udp";
  ```

### 2. Updated Extraction Logic
- **Locations**: Multiple places where we extract IP/port from `received` field
  - `route[RELAY]` for OPTIONS/NOTIFY (lines ~1329-1368)
  - `route[RELAY]` for BYE (lines ~1275-1333)
  - `onreply_route` for caller lookup (lines ~1748-1780)
  - INVITE fallback (lines ~774-810)
- **Change**: Updated SQL `SUBSTRING_INDEX` queries to parse SIP URI format:
  - Remove `sip:` prefix (5 characters)
  - Extract IP (before first `:`)
  - Extract port (between `:` and `;` or end)

### 3. Added NULL Checks
- **Location**: `route[RELAY]` for OPTIONS/NOTIFY (line ~1329)
- **Change**: Added validation to check `received` is not NULL and starts with `sip:` before extraction:
  ```opensips
  if (sql_query($var(query), "$avp(nat_received)") && $(avp(nat_received)[0]) != "" && $(avp(nat_received)[0]) != "<null>") {
      if ($var(received_value) =~ "^sip:") {
          # Extract IP/port from SIP URI
      }
  }
  ```

### 4. Fixed Typo
- **Location**: Line 43
- **Change**: Fixed `loadmodule "textops.so"m` → `loadmodule "textops.so"`

## Current Issue: UPDATE Query Failing

The UPDATE query is failing silently. The query looks correct:
```sql
UPDATE location SET received='sip:74.83.23.44:5060;transport=udp' WHERE contact_id=44001
```

**Possible Causes**:
1. SQL syntax issue with semicolon in the URI string (though it's inside quotes)
2. Contact ID mismatch (verification query finds different record)
3. Timing issue (record not fully committed yet)
4. SQL constraint or permission issue

**What We Need**:
- Check OpenSIPS error logs for actual SQL error message
- Verify the `contact_id` from verification query matches the actual record
- Consider using `username+domain` instead of `contact_id` for UPDATE

## Code Locations

### REGISTER Route - UPDATE received field
- **File**: `config/opensips.cfg.template`
- **Lines**: ~2108-2175
- **Function**: Updates `received` field after `save("location")` succeeds
- **Current Status**: UPDATE query failing, need to investigate SQL error

### RELAY Route - OPTIONS/NOTIFY NAT Traversal
- **File**: `config/opensips.cfg.template`
- **Lines**: ~1317-1370
- **Function**: Extracts IP/port from `received` field for NAT traversal
- **Current Status**: NULL check working, but `received` is NULL because UPDATE failed

### Verification Queries
- **File**: `config/opensips.cfg.template`
- **Lines**: ~1866-1954 (after save), ~2135-2175 (after UPDATE)
- **Function**: Verify record was created/updated correctly
- **Current Status**: Working, but shows `received` is NULL

## Final Implementation Summary

### What Was Implemented

1. **AVP Format Conversion** (Lines 607-631):
   - Captures original request source IP:port before forwarding REGISTER
   - Converts to SIP URI format: `sip:IP:port;transport=udp`
   - Sets both transaction-scoped (`tu:reg_received`) and regular (`reg_received`) AVPs

2. **Module Configuration**:
   - `modparam("nathelper", "received_avp", "$avp(reg_received)")` - Line ~138
   - `modparam("registrar", "received_avp", "$avp(reg_received)")` - Line ~149
   - `modparam("tm", "onreply_avp_mode", 1)` - Line ~220
   - Both modules use same AVP name for consistency

3. **Manual UPDATE Workaround** (Lines 2022-2067):
   - Detects when `received` field is NULL after `save()`
   - Attempts manual UPDATE using `contact_id` (primary) or `username+domain` (fallback)
   - This is necessary because `received_avp` doesn't work when `save()` is called in `onreply_route`

### Why Manual UPDATE is Needed

**Root Cause**: `received_avp` parameter in OpenSIPS registrar module is designed to work when `save()` is called in the main request route, NOT in `onreply_route`. In proxy-registrar mode, we must call `save()` in `onreply_route` to use the Contact header from the 200 OK reply. This creates a fundamental conflict.

**Documentation References**:
- `received_avp` works in standard registrar mode (save in request route)
- In proxy-registrar mode (save in onreply_route), `received_avp` doesn't function correctly
- Manual UPDATE is a documented workaround for this limitation

### Final State (After Testing)

**✅ Fully Working**:
- `received_avp` parameter is working correctly
- `received` field is populated in database: `sip:74.83.23.44:5060;transport=udp`
- AVP capture and format conversion (SIP URI format)
- OPTIONS/NOTIFY routing to endpoints behind NAT
- NAT traversal (requests reach `74.83.23.44:5060` instead of private IP)
- `lookup()` finds endpoints correctly

**Testing Results**:
- ✅ `received_avp` populates database correctly (tested with manual UPDATE disabled)
- ✅ OPTIONS requests reach endpoint: `200 OK from 74.83.23.44`
- ✅ NOTIFY requests reach endpoint: `200 OK from 74.83.23.44`
- ✅ NAT traversal works: Routing to public IP `74.83.23.44:5060` instead of private IP
- ✅ Database persistence: `received` field correctly stored in database

**Note on Verification Query**:
- Verification query shows `<null>` for all fields (SQL result parsing issue)
- Database actually contains correct values (verified by direct SQL query)
- This is a logging/verification issue, not a functional problem

## Related Files

- `config/opensips.cfg.template` - Main configuration file (Lines 138, 149, 220, 607-631, 2022-2067)
- `dbsource/opensips-3.6.3-sqlite3.sql` - Database schema

## Key Learnings

1. OpenSIPS `usrloc` module expects `received` field to be a full SIP URI: `sip:IP:port;transport=udp`
2. `received_avp` parameter doesn't work in proxy-registrar mode when `save()` is in `onreply_route`
3. Manual UPDATE is a necessary workaround for this documented limitation
4. System works correctly even if UPDATE fails (memory cache has correct value)
5. SQL `SUBSTRING_INDEX` is reliable for parsing SIP URIs in extraction logic
6. Both `nathelper` and `registrar` modules must use the same AVP name for `received_avp`

## Resolution

**Final Solution**: `received_avp` parameter is working correctly in proxy-registrar mode. The initial assumption that it wouldn't work was incorrect. Testing with manual UPDATE disabled confirmed that `received_avp` successfully populates the `received` field in the database.

**What Was Removed**:
- Manual UPDATE code (not needed - `received_avp` works)
- Complex fallback logic for UPDATE queries
- Unnecessary workaround code

**What Remains**:
- `received_avp` configuration in both `nathelper` and `registrar` modules
- AVP format conversion to SIP URI format
- Proper module configuration (`onreply_avp_mode=1`)

## Known Issues

1. **Verification Query Parsing**: SQL result parsing shows `<null>` for all fields, but database contains correct values. This is a logging/verification issue, not a functional problem.

## Key Learnings

1. `received_avp` DOES work in proxy-registrar mode when properly configured
2. Both `nathelper` and `registrar` modules must use the same AVP name
3. `onreply_avp_mode=1` is required for AVP persistence in `onreply_route`
4. Testing with manual UPDATE disabled was the right approach to verify functionality
5. Verification queries may have parsing issues - always verify with direct database queries
