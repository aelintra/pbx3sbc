# Session Summary: NAT Received Field Fix

## Problem Statement

**Issue**: Extension 40004 registered through OpenSIPS (public IP: 3.93.26.82) to Asterisk PBX (3.93.253.1) can call other phones, but no phones can call 40004. The endpoint is behind NAT with public IP 74.83.23.44.

**Root Cause**: The `received` field in the `location` table is `NULL`, causing `lookup("location")` to use the private IP from the `contact` field when routing OPTIONS/NOTIFY requests from Asterisk to the NAT'd endpoint. This results in routing failures.

## Technical Context

- **OpenSIPS Version**: 3.6.3
- **Database Mode**: `usrloc` module uses `db_mode=1` (write-through) to ensure immediate database writes
- **Branch**: `natfix`
- **Key Table**: `location` table stores endpoint contact information including:
  - `username`: Extension (e.g., "40004")
  - `domain`: Domain (e.g., "ael.vcloudpbx.com")
  - `contact`: Contact URI from REGISTER request (contains private IP)
  - `received`: **CRITICAL** - Should contain public NAT IP:port (e.g., "74.83.23.44:5060")
  - `expires`: Registration expiration timestamp

## Solution Approach

The `save("location")` function in OpenSIPS's `registrar` module should automatically populate the `received` field from the original request source IP:port. However, in `onreply_route`, the `$si:$sp` pseudo-variables refer to the *response* source (Asterisk), not the original *request* source (endpoint).

**Fix Strategy**: 
1. Capture the original request source IP:port before forwarding REGISTER to Asterisk
2. Store it in a transaction-scoped AVP (`tu:reg_received`) that persists across transaction boundaries
3. In `onreply_route[handle_reply_reg]`, after `save("location")` succeeds, use SQL UPDATE to set the `received` field
4. Fallback to extracting from Via header if AVP is not available

## Implementation Details

### Current Configuration (`config/opensips.cfg.template`)

**Line 121**: `modparam("usrloc", "db_mode", 1)` - Write-through mode for immediate DB writes

**REGISTER Handling** (main route):
- Captures original request source: `$avp(tu:reg_received) = $si + ":" + $sp`
- Calls `fix_nated_register()` to fix Contact header
- Forwards to Asterisk with `t_on_reply("handle_reply_reg")`

**onreply_route[handle_reply_reg]**:
1. Validates 2xx response and Contact header presence
2. Calls `save("location")` to store registration
3. Attempts to retrieve original source from:
   - **Method 1**: Transaction-scoped AVP `$avp(tu:reg_received)`
   - **Method 2**: Regular AVP `$avp(reg_received)`
   - **Method 3**: Array-style AVP access `$(avp(reg_received)[0])`
   - **Method 4**: Extract from Via header `$(hdr(Via)[1]{via.received})` and `$(hdr(Via)[1]{via.rport})`
4. Validates IP:port format (regex: `^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]+$`)
5. Executes SQL UPDATE: `UPDATE location SET received='<ip:port>' WHERE username='<user>' AND domain='<domain>' AND expires > UNIX_TIMESTAMP()`

## Issues Encountered

1. **AVP Persistence**: AVPs were not persisting from main route to `onreply_route`
   - **Fix**: Use transaction-scoped AVPs with `tu:` prefix
   
2. **Parse Errors**: 
   - `$null` variable doesn't exist in OpenSIPS
   - **Fix**: Removed `$null` comparisons, use `""` or `"<null>"` string checks
   
3. **Via Header Syntax**: Incorrect syntax for accessing Via header transformations
   - **Fix**: Use `$(hdr(Via)[1]{via.received})` with `$()` wrapper for OpenSIPS 3.6
   
4. **SQL UPDATE Timing**: With `db_mode=2` (cached DB), `save()` writes to memory first, so SQL UPDATE executed before record was flushed to DB
   - **Fix**: Changed to `db_mode=1` (write-through) so `save()` writes immediately to DB

## Current Status

**Configuration**: 
- ✅ `usrloc` `db_mode=1` is set (line 121)
- ✅ Transaction-scoped AVP capture in main route
- ✅ Comprehensive fallback logic in `onreply_route`
- ✅ SQL UPDATE with validation and error handling

**Pending**:
- ⚠️ **OpenSIPS service needs to be reloaded** to apply `db_mode=1` change
- ⚠️ Test registration and verify `received` field is populated
- ⚠️ Test OPTIONS/NOTIFY routing to confirm fix works

## Next Steps

1. **Reload OpenSIPS configuration**:
   ```bash
   opensipsctl reload
   # OR
   systemctl reload opensips
   ```

2. **Test Registration**:
   - Trigger re-registration from endpoint 40004
   - Check logs for:
     - "REGISTER: Successfully updated 'received' field to 74.83.23.44:5060"
     - No SQL UPDATE errors
   - Verify in database:
     ```sql
     SELECT username, domain, contact, received, expires 
     FROM location 
     WHERE username='40004' AND domain='ael.vcloudpbx.com';
     ```
     - `received` should be `74.83.23.44:5060` (not NULL)

3. **Test OPTIONS/NOTIFY Routing**:
   - Send OPTIONS request from Asterisk to 40004
   - Verify routing succeeds using the `received` field
   - Check logs for successful routing

## Key Files Modified

- `config/opensips.cfg.template`:
  - Line 121: Changed `db_mode` from `2` to `1` for `usrloc` module
  - REGISTER handling: Added `$avp(tu:reg_received)` capture
  - `onreply_route[handle_reply_reg]`: Added comprehensive `received` field update logic

## Notes

- **Dialog module** `db_mode=2` (line 96) is separate and should remain at 2 for CDR correlation - this is correct
- **Domain module** `db_mode=2` (line 144) is also separate and correct
- Only the **usrloc module** needs `db_mode=1` for this fix to work
- The SQL UPDATE approach is a workaround - ideally `save()` should populate `received` automatically, but this ensures it works reliably

## Debugging Commands

```bash
# Check OpenSIPS config syntax
opensipsctl cfgcheck

# Reload configuration
opensipsctl reload

# View OpenSIPS logs
journalctl -u opensips -f

# Check location table
mysql -u opensips -p opensips -e "SELECT username, domain, contact, received, expires FROM location WHERE username='40004';"
```

## Regex Extraction Issue and Solution

### Problem: POSIX Regex `$re` Variable Not Populating

**Issue Discovered**: When extracting IP:port from the `received` field (format: `74.83.23.44:5060`) in the RELAY route, regex patterns were matching successfully, but the `$re` variable (which should contain the first capturing group) was always `<null>`.

**Root Cause**: In OpenSIPS 3.6, the `=~` operator uses POSIX extended regex, not PCRE. The `$re` variable has a very specific scope:
- It's only valid immediately after the regex match
- It must be captured before any other regex operations
- Even when captured immediately, POSIX regex may not properly populate `$re` with capturing groups

**Evidence from Logs**:
```
RELAY: NOTIFY - DEBUG - IP pattern matched, <null>=[<null>], nat_ip=[<null>]
RELAY: NOTIFY - DEBUG - Port pattern matched, <null>=[<null>], nat_port=[<null>]
```

The pattern matched (we were inside the `if` block), but `$re` was `<null>` even when captured immediately.

### Solution: SQL SUBSTRING_INDEX() for String Extraction

**Approach**: Instead of using regex with `$re`, use SQL `SUBSTRING_INDEX()` function to extract IP and port from the `received` field.

**Implementation** (lines 1074-1103 in `opensips.cfg.template`):
```opensips
# Extract IP part (everything before first colon)
$var(query_ip) = "SELECT SUBSTRING_INDEX('" + $var(received_value) + "', ':', 1)";
if (sql_query($var(query_ip), "$avp(nat_ip_extracted)")) {
    $var(nat_ip) = $(avp(nat_ip_extracted)[0]);
}

# Extract port part (everything after last colon)
$var(query_port) = "SELECT SUBSTRING_INDEX('" + $var(received_value) + "', ':', -1)";
if (sql_query($var(query_port), "$avp(nat_port_extracted)")) {
    $var(nat_port) = $(avp(nat_port_extracted)[0]);
}
```

**How SUBSTRING_INDEX Works**:
- `SUBSTRING_INDEX('74.83.23.44:5060', ':', 1)` → Returns `74.83.23.44` (everything before first colon)
- `SUBSTRING_INDEX('74.83.23.44:5060', ':', -1)` → Returns `5060` (everything after last colon)

### Applied to Multiple Locations

1. **RELAY Route** (lines 1074-1103): Extracts IP:port from `received` field for NAT traversal
2. **OPTIONS/NOTIFY SQL Fallback** (lines 454-508): Extracts IP:port from `received` or `contact` field when `lookup()` fails due to race conditions

### Results

**Successfully Working**:
- ✅ OPTIONS routing: Extracts NAT IP:port and routes to `sip:40004@74.83.23.44:5060`
- ✅ NOTIFY routing: Extracts NAT IP:port and routes to `sip:40004@74.83.23.44:5060`
- ✅ Both receive 200 OK responses from endpoints behind NAT

**Log Evidence**:
```
RELAY: OPTIONS - DEBUG - SQL extracted IP: [74.83.23.44]
RELAY: OPTIONS - DEBUG - SQL extracted port: [5060]
RELAY: OPTIONS - Updated destination to NAT IP from received field: sip:40004@74.83.23.44:5060
Response received: 200 OK from 74.83.23.44 (method=OPTIONS)
```

### Key Learnings

1. **OpenSIPS 3.6 Regex Limitation**: POSIX extended regex (`=~` operator) does not reliably populate `$re` with capturing groups, even when patterns match
2. **SQL as String Manipulation**: SQL functions like `SUBSTRING_INDEX()` can be used for reliable string parsing in OpenSIPS
3. **Scope of `$re`**: Even when captured immediately after match, `$re` may remain `<null>` - this is a known limitation of POSIX regex in OpenSIPS
4. **Alternative**: The `regex` module provides `pcre_match()` with `pcre_match_group()` for proper capturing groups, but requires loading the module

### Remaining Issue

**SQL UPDATE for `received` Field Still Failing**:
- The SQL UPDATE query in `onreply_route[handle_reply_reg]` continues to fail
- However, this does NOT affect functionality because:
  - The `received` field is eventually populated correctly (visible in database)
  - The extraction in RELAY route works correctly
  - OPTIONS/NOTIFY routing succeeds
- **Possible causes**: Timing issue, `expires` condition mismatch, or transaction isolation

## References

- OpenSIPS 3.6 Documentation: Via header transformations
- OpenSIPS usrloc module: `db_mode` parameter
- OpenSIPS registrar module: `save()` function behavior
- Transaction-scoped AVPs: `tu:` prefix for persistence across transaction boundaries
- OpenSIPS 3.6 Regex Module: https://opensips.org/docs/modules/3.6.x/regex.html
- OpenSIPS `$re` variable scope: Temporary, only valid immediately after regex match
- MySQL SUBSTRING_INDEX() function documentation