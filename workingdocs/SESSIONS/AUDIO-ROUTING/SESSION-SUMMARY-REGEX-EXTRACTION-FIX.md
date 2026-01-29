# Session Summary: Regex Extraction Fix - SQL SUBSTRING_INDEX Solution

## Problem Statement

**Issue**: When extracting IP:port from the `received` field (format: `74.83.23.44:5060`) in the RELAY route and OPTIONS/NOTIFY SQL fallback, regex patterns were matching successfully, but the `$re` variable (which should contain the first capturing group) was always `<null>`.

**Impact**: NAT traversal for OPTIONS and NOTIFY requests was failing because the NAT IP:port could not be extracted from the `received` field, causing routing to use the private IP from the `contact` field instead.

## Root Cause

In OpenSIPS 3.6, the `=~` operator uses POSIX extended regex, not PCRE. The `$re` variable has a very specific scope:
- It's only valid immediately after the regex match
- It must be captured before any other regex operations
- **Even when captured immediately, POSIX regex may not properly populate `$re` with capturing groups**

**Evidence from Logs**:
```
RELAY: NOTIFY - DEBUG - IP pattern matched, <null>=[<null>], nat_ip=[<null>]
RELAY: NOTIFY - DEBUG - Port pattern matched, <null>=[<null>], nat_port=[<null>]
```

The pattern matched (we were inside the `if` block), but `$re` was `<null>` even when captured immediately after the match.

## Solution: SQL SUBSTRING_INDEX() for String Extraction

**Approach**: Instead of using regex with `$re`, use SQL `SUBSTRING_INDEX()` function to extract IP and port from the `received` field.

### Implementation Details

**Location 1: RELAY Route** (lines 1074-1103 in `opensips.cfg.template`)

For `received` field format (`74.83.23.44:5060`):
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

For `contact` field format (`sip:40004@192.168.1.97:5060`):
```opensips
# Extract everything after @
$var(query_at) = "SELECT SUBSTRING_INDEX('" + $var(contact_uri) + "', '@', -1)";
if (sql_query($var(query_at), "$avp(nat_at_part)")) {
    $var(at_part) = $(avp(nat_at_part)[0]);
    # Extract IP (before colon if present)
    $var(query_ip) = "SELECT SUBSTRING_INDEX('" + $var(at_part) + "', ':', 1)";
    if (sql_query($var(query_ip), "$avp(nat_ip_extracted)")) {
        $var(nat_ip) = $(avp(nat_ip_extracted)[0]);
    }
    # Extract port (after colon if present, or default to 5060)
    if ($var(at_part) =~ ":") {
        $var(query_port) = "SELECT SUBSTRING_INDEX('" + $var(at_part) + "', ':', -1)";
        if (sql_query($var(query_port), "$avp(nat_port_extracted)")) {
            $var(nat_port) = $(avp(nat_port_extracted)[0]);
        }
    } else {
        $var(nat_port) = "5060";
    }
}
```

**Location 2: OPTIONS/NOTIFY SQL Fallback** (lines 454-508 in `opensips.cfg.template`)

Similar logic applied when `lookup("location")` fails due to race conditions. The SQL fallback queries the database directly and extracts IP:port using `SUBSTRING_INDEX()`.

### How SUBSTRING_INDEX Works

- `SUBSTRING_INDEX('74.83.23.44:5060', ':', 1)` → Returns `74.83.23.44` (everything before first colon)
- `SUBSTRING_INDEX('74.83.23.44:5060', ':', -1)` → Returns `5060` (everything after last colon)
- `SUBSTRING_INDEX('sip:40004@192.168.1.97:5060', '@', -1)` → Returns `192.168.1.97:5060` (everything after last @)

## Results

### Successfully Working

- ✅ **OPTIONS routing**: Extracts NAT IP:port and routes to `sip:40004@74.83.23.44:5060`
- ✅ **NOTIFY routing**: Extracts NAT IP:port and routes to `sip:40004@74.83.23.44:5060`
- ✅ Both receive **200 OK responses** from endpoints behind NAT

### Log Evidence

```
RELAY: OPTIONS - DEBUG - Extracting from received field: [74.83.23.44:5060]
RELAY: OPTIONS - DEBUG - SQL extracted IP: [74.83.23.44]
RELAY: OPTIONS - DEBUG - SQL extracted port: [5060]
RELAY: OPTIONS - DEBUG - Final extraction result: IP=[74.83.23.44], Port=[5060]
RELAY: OPTIONS - Updated destination to NAT IP from received field: sip:40004@74.83.23.44:5060 (was sip:40004@192.168.1.97:5060)
Response received: 200 OK from 74.83.23.44 (method=OPTIONS)
```

## Key Learnings

1. **OpenSIPS 3.6 Regex Limitation**: POSIX extended regex (`=~` operator) does not reliably populate `$re` with capturing groups, even when patterns match successfully.

2. **SQL as String Manipulation**: SQL functions like `SUBSTRING_INDEX()` can be used for reliable string parsing in OpenSIPS, providing a workaround for regex limitations.

3. **Scope of `$re`**: Even when captured immediately after match, `$re` may remain `<null>` - this is a known limitation of POSIX regex in OpenSIPS.

4. **Alternative Solution**: The `regex` module provides `pcre_match()` with `pcre_match_group()` for proper capturing groups, but requires loading the module. SQL `SUBSTRING_INDEX()` is simpler and doesn't require additional modules.

5. **Validation Required**: Always validate extracted values before using them:
   ```opensips
   if ($var(nat_ip) != "" && $var(nat_ip) != "<null>" && $var(nat_ip) =~ "^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}" && $var(nat_port) != "" && $var(nat_port) != "<null>" && $var(nat_port) =~ "^[0-9]+$") {
       # Use extracted values
   }
   ```

## Code Locations Modified

### RELAY Route (lines 1035-1149)
- **Line 1040**: Added `OPTIONS` to `is_method("ACK|PRACK|BYE|NOTIFY|OPTIONS")` check
- **Lines 1074-1103**: Replaced regex extraction with SQL `SUBSTRING_INDEX()` for `received` field
- **Lines 1105-1149**: Added SQL `SUBSTRING_INDEX()` extraction for `contact` field fallback

### OPTIONS/NOTIFY Route (lines 304-499)
- **Lines 454-508**: SQL fallback uses `SUBSTRING_INDEX()` to extract IP:port from `received` or `contact` field

## Testing Results

**Test Date**: 2026-01-25

**Test Scenario**: 
1. Endpoint 40004 registers from behind NAT (public IP: 74.83.23.44:5060, private IP: 192.168.1.97:5060)
2. Asterisk sends OPTIONS and NOTIFY requests to 40004
3. OpenSIPS extracts NAT IP:port from `received` field and routes correctly

**Results**:
- ✅ OPTIONS request routed to `sip:40004@74.83.23.44:5060` → 200 OK received
- ✅ NOTIFY request routed to `sip:40004@74.83.23.44:5060` → 200 OK received
- ✅ SQL extraction working correctly for both IP and port
- ✅ No regex extraction errors in logs

## References

- OpenSIPS 3.6 Regex Module: https://opensips.org/docs/modules/3.6.x/regex.html
- OpenSIPS `$re` variable scope: Temporary, only valid immediately after regex match
- MySQL SUBSTRING_INDEX() function: https://dev.mysql.com/doc/refman/8.0/en/string-functions.html#function_substring-index
- OpenSIPS SQL Query function: https://opensips.org/docs/modules/3.6.x/sqlops.html#func_sql_query

## Related Issues

- **Race Condition**: `lookup("location")` failing immediately after `save("location")` - see `SESSION-SUMMARY-USRLOC-LOOKUP-COMPLETE.md`
- **NAT Received Field**: SQL UPDATE for `received` field still failing - see `SESSION-SUMMARY-NAT-RECEIVED-FIX.md` (non-critical, field is populated correctly)
