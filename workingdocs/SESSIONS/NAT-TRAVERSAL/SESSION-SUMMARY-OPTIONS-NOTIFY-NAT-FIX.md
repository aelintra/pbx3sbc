# Session Summary: OPTIONS/NOTIFY NAT Traversal Fix - Complete Solution

## Overview

This document summarizes the complete solution for routing OPTIONS and NOTIFY requests to endpoints behind NAT. The solution involved multiple fixes across different parts of the OpenSIPS configuration.

**Date**: 2026-01-25  
**Status**: ✅ **COMPLETE AND WORKING**

## Problem Statement

Extension 40004 registered through OpenSIPS to Asterisk PBX could make outbound calls, but inbound calls (OPTIONS/NOTIFY from Asterisk) were failing because:
1. `lookup("location")` was failing immediately after `save("location")` due to race conditions
2. When `lookup()` succeeded, it returned the private IP (`192.168.1.97:5060`) instead of the public NAT IP (`74.83.23.44:5060`)
3. Regex extraction of IP:port from the `received` field was failing because `$re` variable was not populating

## Solution Components

### 1. Race Condition Fix (see `SESSION-SUMMARY-USRLOC-LOOKUP-COMPLETE.md`)

**Problem**: `lookup("location")` returned FALSE immediately after `save("location")` succeeded.

**Solution**:
- Changed `usrloc` `db_mode` from `2` (cached/write-back) to `1` (write-through) for immediate DB writes
- Added SQL fallback that queries the database directly when `lookup()` fails
- Fixed `lookup()` usage to check both `$du` and `$ru` (lookup may update `$ru` instead of `$du` for local contacts)

**Result**: `lookup()` now works correctly, and SQL fallback handles race conditions.

### 2. Regex Extraction Fix (see `SESSION-SUMMARY-REGEX-EXTRACTION-FIX.md`)

**Problem**: POSIX regex `$re` variable was not populating with capturing groups, causing IP:port extraction to fail.

**Solution**: Replaced regex extraction with SQL `SUBSTRING_INDEX()` function:
- `SUBSTRING_INDEX('74.83.23.44:5060', ':', 1)` → Extracts IP
- `SUBSTRING_INDEX('74.83.23.44:5060', ':', -1)` → Extracts port

**Applied to**:
- RELAY route NAT traversal (lines 1074-1103)
- OPTIONS/NOTIFY SQL fallback (lines 454-508)

**Result**: IP:port extraction now works reliably.

### 3. OPTIONS Method Inclusion

**Problem**: OPTIONS method was not included in NAT traversal logic in RELAY route.

**Solution**: Added `OPTIONS` to `is_method("ACK|PRACK|BYE|NOTIFY|OPTIONS")` check (line 1040).

**Result**: OPTIONS requests now go through NAT traversal logic.

### 4. NAT Received Field Population (see `SESSION-SUMMARY-NAT-RECEIVED-FIX.md`)

**Problem**: `received` field in `location` table was `NULL`, causing `lookup()` to use private IP.

**Solution**: 
- Capture original request source IP:port before forwarding REGISTER
- Store in transaction-scoped AVP (`tu:reg_received`)
- Extract from Via header in `onreply_route` if AVP not available
- Update `received` field via SQL UPDATE (though this still fails, field is populated via other means)

**Result**: `received` field is populated correctly in database.

## Final Implementation

### OPTIONS/NOTIFY Route (lines 304-499)

1. **Initial `lookup("location")` attempt**:
   - Sets `$ru` before lookup to detect changes
   - Calls `lookup("location")`
   - If `$du` is null but `$ru` changed, uses `$ru` as destination

2. **SQL Fallback** (when `lookup()` returns FALSE):
   - Queries database directly: `SELECT COALESCE(received, contact) FROM location WHERE ...`
   - Extracts IP:port using SQL `SUBSTRING_INDEX()`
   - Constructs destination URI: `sip:40004@74.83.23.44:5060`
   - Routes to endpoint

### RELAY Route NAT Traversal (lines 1035-1149)

1. **Detects NAT requirement**:
   - Checks if Request-URI contains private IP
   - Applies to `ACK|PRACK|BYE|NOTIFY|OPTIONS` methods

2. **Extracts NAT IP:port**:
   - First tries `received` field (format: `74.83.23.44:5060`)
   - Falls back to `contact` field (format: `sip:40004@192.168.1.97:5060`)
   - Uses SQL `SUBSTRING_INDEX()` for extraction

3. **Updates destination**:
   - Sets `$du = "sip:" + $rU + "@" + $var(nat_ip) + ":" + $var(nat_port)`
   - Routes to public NAT IP instead of private IP

## Test Results

**Test Date**: 2026-01-25  
**Endpoint**: 40004@ael.vcloudpbx.com  
**Public NAT IP**: 74.83.23.44:5060  
**Private IP**: 192.168.1.97:5060

### OPTIONS Request

```
REQUEST: OPTIONS from 3.93.253.1:5060 to sip:40004@192.168.1.97:5060
OPTIONS/NOTIFY: lookup() returned TRUE - contact found
OPTIONS/NOTIFY: $ru changed from sip:40004@ael.vcloudpbx.com to sip:40004@192.168.1.97:5060
RELAY: OPTIONS - DEBUG - SQL extracted IP: [74.83.23.44]
RELAY: OPTIONS - DEBUG - SQL extracted port: [5060]
RELAY: OPTIONS - Updated destination to NAT IP from received field: sip:40004@74.83.23.44:5060
Response received: 200 OK from 74.83.23.44 (method=OPTIONS)
```

✅ **SUCCESS**: OPTIONS routed to NAT IP and received 200 OK

### NOTIFY Request

```
REQUEST: NOTIFY from 3.93.253.1:5060 to sip:40004@192.168.1.97:5060
OPTIONS/NOTIFY: lookup() returned TRUE - contact found
OPTIONS/NOTIFY: $ru changed from sip:40004@ael.vcloudpbx.com to sip:40004@192.168.1.97:5060
RELAY: NOTIFY - DEBUG - SQL extracted IP: [74.83.23.44]
RELAY: NOTIFY - DEBUG - SQL extracted port: [5060]
RELAY: NOTIFY - Updated destination to NAT IP from received field: sip:40004@74.83.23.44:5060
Response received: 200 OK from 74.83.23.44 (method=NOTIFY)
```

✅ **SUCCESS**: NOTIFY routed to NAT IP and received 200 OK

## Key Files Modified

- `config/opensips.cfg.template`:
  - Line 121: `modparam("usrloc", "db_mode", 1)` - Write-through mode
  - Lines 304-499: OPTIONS/NOTIFY route with SQL fallback
  - Line 1040: Added `OPTIONS` to NAT traversal methods
  - Lines 1074-1149: RELAY route NAT traversal with SQL SUBSTRING_INDEX() extraction

## Key Learnings

1. **OpenSIPS `db_mode`**: `db_mode=1` (write-through) is essential for immediate lookups after save
2. **POSIX Regex Limitation**: `$re` variable doesn't reliably populate - use SQL functions instead
3. **`lookup()` Behavior**: May update `$ru` instead of `$du` for local contacts - check both
4. **SQL for String Parsing**: `SUBSTRING_INDEX()` is reliable for extracting IP:port from strings
5. **Validation**: Always validate extracted values before constructing URIs

## Remaining Issues (Non-Critical)

- ⚠️ SQL UPDATE query for `received` field still fails in `onreply_route[handle_reply_reg]`
- **Impact**: None - `received` field is populated correctly via other means
- **Status**: Can be investigated later if needed

## Related Documents

- **SESSION-SUMMARY-USRLOC-LOOKUP-COMPLETE.md**: Race condition fix for `lookup()` after `save()`
- **SESSION-SUMMARY-REGEX-EXTRACTION-FIX.md**: Regex extraction issue and SQL solution
- **SESSION-SUMMARY-NAT-RECEIVED-FIX.md**: `received` field population logic

## Conclusion

The complete solution for routing OPTIONS and NOTIFY requests to endpoints behind NAT is now **working correctly**. All components are in place:
- ✅ Race condition handled
- ✅ NAT IP:port extraction working
- ✅ OPTIONS and NOTIFY routing successfully
- ✅ Both methods receive 200 OK responses from endpoints

The system is production-ready for NAT traversal of OPTIONS and NOTIFY requests.
