# Troubleshooting Session: OPTIONS Packet Routing from Asterisk to Endpoints

**Date:** December 25, 2024  
**Issue:** OPTIONS packets from Asterisk backends not routing to registered endpoints

## Problem Summary

OPTIONS packets sent from Asterisk backends to registered endpoints were not being routed correctly through Kamailio. The packets were being blocked or failing with various errors.

## Issues Identified and Fixed

### 1. Contact Header Parsing Errors

**Symptoms:**
```
ERROR: pv [pv_trans.c:1496]: tr_eval_uri(): invalid uri [<sip:H5CCvFpY@10.0.1.200:45891;line=zlpcjjt4>;reg-id=1;q=1.0;+sip.instance="<urn:uuid:...>";audio;m>
ERROR: <core> [core/lvalue.c:346]: lval_pvar_assign(): non existing right pvar
ERROR: <core> [core/lvalue.c:404]: lval_assign(): assignment failed at pos: (214,32-214,46)
```

**Root Cause:**  
The code was using `$(ct{uri.host})` and `$(ct{uri.port})` to extract IP and port from Contact headers, but these pvar transformations fail when the Contact header contains angle brackets and complex parameters (like `reg-id`, `sip.instance`, etc.).

**Solution:**  
Replaced pvar-based extraction with regex pattern matching that extracts IP and port directly from the Contact header string, handling angle brackets and complex parameters.

**Location:** `config/kamailio.cfg.template` lines 222-237

**Code Change:**
```kamailio
# Old (failing):
$var(contact_ip) = $(ct{uri.host});
$var(contact_port) = $(ct{uri.port});

# New (working):
# Extract IP address from Contact header (pattern: @IP:port or @IP)
if ($hdr(Contact) =~ "@([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})") {
    $var(contact_ip) = $re;
    if ($hdr(Contact) =~ "@[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}:([0-9]+)") {
        $var(contact_port) = $re;
    }
}
```

### 2. Dispatcher Destination Matching Failure

**Symptoms:**
```
INFO: <script>: OPTIONS/NOTIFY from 10.0.1.100 is not from a known dispatcher destination, continuing normal routing
NOTICE: <script>: Door-knock blocked: domain=10.0.1.200 src=10.0.1.100 (not found)
```

**Root Cause:**  
The SQL query to check if an OPTIONS request came from a known Asterisk backend was using LIKE patterns that assumed destinations were stored as `sip:IP:PORT` or `sip:IP`. However, the actual database stored destinations as just `IP` (e.g., `10.0.1.100`).

**Solution:**  
Updated the SQL query to extract the IP from the destination field regardless of format, handling:
- Just IP: `10.0.1.100`
- IP:PORT: `10.0.1.100:5060`
- sip:IP: `sip:10.0.1.100`
- sip:IP:PORT: `sip:10.0.1.100:5060`

**Location:** `config/kamailio.cfg.template` lines 87-106

**Code Change:**
```kamailio
# Complex SQL query that extracts IP from destination field
# Handles all possible formats by checking if destination starts with "sip:"
# and extracting IP accordingly
if (sql_query("cb", "SELECT COUNT(*) FROM dispatcher WHERE CASE WHEN destination LIKE 'sip:%' THEN CASE WHEN instr(substr(destination, 5), ':') > 0 THEN substr(destination, 5, instr(substr(destination, 5), ':') - 1) ELSE substr(destination, 5) END WHEN instr(destination, ':') > 0 AND destination NOT LIKE 'sip:%' THEN substr(destination, 1, instr(destination, ':') - 1) ELSE destination END = '$var(source_ip)'", "dispatcher_check")) {
```

### 3. Invalid Request-URI Errors

**Symptoms:**
```
ERROR: pv [pv_core.c:269]: pv_get_ruri(): failed to parse the R-URI
ERROR: tm [t_lookup.c:1285]: new_t(): uri invalid
ERROR: tm [t_lookup.c:1438]: t_newtran(): new_t failed
INFO: <script>: Routing OPTIONS from Asterisk 10.0.1.100 to endpoint sip:401@10.0.1.200:58396 (username match), Request-URI=<null>
```

**Root Cause:**  
The code was trying to use `rewritehostport()` on a Request-URI that was already invalid or null. The Request-URI from Asterisk's OPTIONS request contained an IP address instead of a domain, making it invalid for routing.

**Solution:**  
Instead of trying to rewrite an invalid Request-URI, we now construct a new valid Request-URI directly by setting `$ru = $du` after building the destination URI.

**Location:** `config/kamailio.cfg.template` lines 138-150, 174-186

**Code Change:**
```kamailio
# Old (failing):
$du = "sip:" + $var(target_user) + "@" + $var(endpoint_ip) + ":" + $var(endpoint_port);
rewritehostport("$var(endpoint_ip):$var(endpoint_port)");
route(RELAY);

# New (working):
$du = "sip:" + $var(target_user) + "@" + $var(endpoint_ip) + ":" + $var(endpoint_port);
$ru = $du;  # Construct valid Request-URI directly
route(RELAY);
```

## Current Working State

After all fixes, the logs show successful routing:

```
INFO: <script>: OPTIONS/NOTIFY received from 10.0.1.100, checking if from dispatcher
INFO: <script>: Dispatcher check result: found 1 matching destinations for IP 10.0.1.100
INFO: <script>: OPTIONS/NOTIFY from Asterisk 10.0.1.100, looking up endpoint AoR: 401@10.0.1.200 (user: 401)
INFO: <script>: Database lookup result (username match): IP=10.0.1.200, Port=58396
INFO: <script>: Routing OPTIONS from Asterisk 10.0.1.100 to endpoint sip:401@10.0.1.200:58396 (username match), Request-URI=sip:401@10.0.1.200:58396
```

## Debug Logging

The following debug logging was added and should be kept for now:
- Dispatcher destination sample logging (line 98-102)
- Dispatcher check result logging (line 109)
- Detailed routing information in log messages

These can be removed during cleanup once the system is fully tested and stable.

## Testing Notes

- REGISTER requests successfully track endpoint locations
- OPTIONS requests from Asterisk are correctly identified as coming from dispatcher destinations
- Endpoint lookup works via username-only match (when To header has IP instead of domain)
- Request-URI is properly constructed and routing succeeds

## Future Cleanup Tasks

1. Remove debug query that logs dispatcher destinations (lines 98-102)
2. Consider optimizing the SQL query for dispatcher matching
3. Add error handling for edge cases
4. Document the endpoint location tracking mechanism

## Related Files

- `config/kamailio.cfg.template` - Main configuration file with all fixes
- Database table: `endpoint_locations` - Stores endpoint IP/port for routing
- Database table: `dispatcher` - Stores Asterisk backend destinations

## Key Learnings

1. Contact headers with complex parameters (angle brackets, multiple params) require regex extraction instead of pvar transformations
2. Dispatcher destinations can be stored in various formats - need flexible IP extraction
3. Request-URI must be valid before routing - construct it directly rather than trying to rewrite invalid URIs
4. To header from Asterisk OPTIONS may contain IP addresses instead of domains - username-only lookup is essential

---

# Troubleshooting Session: INVITE Cancellation and 408 Request Timeout

**Date:** December 25, 2024  
**Issue:** INVITE requests being cancelled by Kamailio with 408 Request Timeout immediately after receiving 100 Trying from Asterisk

## Problem Summary

After fixing the OPTIONS routing issue, a new problem emerged: INVITE requests from endpoints were being cancelled by Kamailio with a 408 Request Timeout approximately 26ms after receiving a 100 Trying response from Asterisk. The endpoint never received the 100 Trying from Asterisk, only the 408 Request Timeout from Kamailio.

## Symptoms

**From Endpoint Logs:**
- INVITE sent at timestamp T
- 100 Trying received from Kamailio at T+3ms (automatic from `t_relay()`)
- 408 Request Timeout received from Kamailio at T+26ms
- Endpoint **never** receives the 100 Trying from Asterisk

**From Kamailio Logs:**
```
INFO: <script>: INVITE received from 10.0.1.200:58396
INFO: <script>: Routing to sip:10.0.1.100 for domain=example.com
INFO: <script>: t_relay() succeeded for sip:10.0.1.100 method=INVITE
INFO: <script>: Response received: 100 Trying from 10.0.1.100
INFO: <script>: Provisional response 100 received, transaction should remain active
INFO: <script>: Response received: 487 Request Terminated from 10.0.1.100
INFO: <script>: Response received: 200 OK from 10.0.1.100 (method=CANCEL)
```

**Key Observations:**
- Kamailio receives 100 Trying from Asterisk (logged)
- Kamailio sends CANCEL to Asterisk internally (evidenced by 200 OK to CANCEL and 487 Request Terminated)
- No "REQUEST: CANCEL" log appears, indicating CANCEL is generated internally by transaction module
- 408 Request Timeout is generated in ~26ms, which is way too fast for any timer
- The 100 Trying from Asterisk is never forwarded to the endpoint

## Root Cause Hypothesis

The 408 Request Timeout is being generated internally by Kamailio's transaction module (`tm`) before it can forward the upstream 100 Trying response. The timing (26ms) suggests this is a transaction state issue rather than a timer expiration. Possible causes:

1. **Transaction State Conflict:** When `t_relay()` automatically sends its own 100 Trying to the endpoint, and then Kamailio receives 100 Trying from Asterisk, the transaction module may be getting confused about which response is which, or there's a state conflict.

2. **Response Matching Issue:** The transaction module may not be properly matching the 100 Trying response from Asterisk to the correct transaction, causing it to think the transaction has failed.

3. **Bug in Kamailio 5.5.4:** This could be a known or unknown bug in the transaction module of Kamailio 5.5.4 that causes premature 408 generation.

## Attempted Fixes

### 1. Transaction Timer Adjustments

**Attempted:**
- Increased `fr_timer` from 5 to 30 seconds
- Increased `fr_inv_timer` from default to 30 seconds
- Increased `retr_timer1` from 500ms to 2000ms
- Increased `retr_timer2` from 4000ms to 8000ms

**Result:** No change - 408 still generated in ~26ms

**Location:** `config/kamailio.cfg.template` lines 50-62

### 2. Restart Timer on Provisional Responses

**Attempted:**
- Added `modparam("tm", "restart_fr_on_each_reply", 1)` to reset `fr_inv_timer` on each provisional response

**Result:** No change - 408 still generated in ~26ms

**Location:** `config/kamailio.cfg.template` line 57

### 3. Advertised Address Configuration

**Attempted:**
- Added `advertised_address="198.51.100.1"` to fix `0.0.0.0` in Via headers

**Result:** No change - issue persisted

**Location:** `config/kamailio.cfg.template` line 17

### 4. onreply_route Handling Changes

**Attempted Multiple Approaches:**
- Changed `exit` to `return` in `onreply_route`
- Removed `exit`/`return` entirely
- Added explicit `exit` statements for all response types
- Added detailed logging for provisional responses

**Result:** No change - 408 still generated in ~26ms

**Location:** `config/kamailio.cfg.template` lines 443-460

### 5. Enhanced Logging

**Added:**
- Logging for all incoming requests
- Logging for INVITE requests specifically
- Logging for CANCEL requests
- Logging for in-dialog requests
- Detailed logging in `onreply_route` for all response types
- Enhanced logging in `failure_route` for 408 errors

**Result:** Provided visibility but didn't fix the issue

**Location:** Throughout `config/kamailio.cfg.template`

### 6. Early CANCEL Handling

**Attempted:**
- Added explicit CANCEL handling in `request_route` before domain check
- Added transaction matching check for CANCEL requests

**Result:** No change - CANCEL is generated internally, not received from endpoint

**Location:** `config/kamailio.cfg.template` lines 90-110

## Current Configuration State

The configuration now includes:

```kamailio
# Transaction timers
modparam("tm", "fr_timer", 30)
modparam("tm", "fr_inv_timer", 30)
modparam("tm", "restart_fr_on_each_reply", 1)
modparam("tm", "retr_timer1", 2000)
modparam("tm", "retr_timer2", 8000)

# Global parameters
advertised_address="198.51.100.1"

# onreply_route with explicit handling
onreply_route {
    xlog("L_INFO", "Response received: $rs $rr from $si...\n");
    if ($rs >= 100 && $rs < 200) {
        xlog("L_INFO", "Provisional response $rs received, transaction should remain active\n");
        exit;
    }
    # ... other response handling
    exit;
}
```

## Conclusion

After extensive troubleshooting with multiple approaches, the issue persists across multiple Kamailio versions (5.5.4 and 5.7.4). The 408 Request Timeout is being generated way too quickly (26ms) to be a timer issue, suggesting a **fundamental architectural limitation or transaction state conflict** in Kamailio's transaction module.

**Testing Results:**
- **Kamailio 5.5.4:** Issue present
- **Kamailio 5.7.4 (Ubuntu 24.04):** Issue persists - **NO CHANGE**

**Root Cause Hypothesis:**
This appears to be an architectural limitation in Kamailio's transaction module when handling the specific flow:
1. `t_relay()` automatically sends 100 Trying to endpoint
2. Upstream server (Asterisk) sends 100 Trying back
3. Transaction module generates 408 before forwarding upstream 100 Trying

The conflict between the automatic 100 Trying from `t_relay()` and the upstream 100 Trying may be causing a transaction state issue that cannot be resolved through configuration alone.

**Recommendations:**
1. **Try OpenSIPS:** OpenSIPS may handle this transaction flow differently and could resolve the issue
2. **Post to Kamailio Community:** Document this as a potential architectural limitation on Kamailio mailing list/IRC
3. **Consider Workarounds:** 
   - Use stateless forwarding (loses transaction management benefits)
   - Implement custom transaction handling (complex, may not work)
4. **Document as Known Limitation:** If this use case is not supported by Kamailio, document it for future reference

## Testing Results

**Kamailio 5.7.4 (Ubuntu 24.04):**
- Issue **PERSISTS** - No improvement
- Same symptoms: 408 Request Timeout in ~26ms
- 100 Trying from Asterisk still not forwarded to endpoint
- **Conclusion:** This appears to be an architectural limitation, not a version-specific bug

## Related Files

- `config/kamailio.cfg.template` - Contains all attempted fixes and current configuration
- Transaction module (`tm`) - Responsible for transaction management and timeout handling

## Key Learnings from INVITE Issue

1. **Transaction timeouts can occur due to state issues, not just timer expiration** - The 408 happens in 26ms, way too fast for any timer
2. **The transaction module's internal state management is complex and can fail in edge cases** - The conflict between automatic and upstream 100 Trying may be unresolvable
3. **Some issues may be architectural limitations rather than bugs** - Persisting across versions (5.5.4 → 5.7.4) suggests a fundamental design issue
4. **Extensive logging is essential for diagnosing transaction state issues** - But logging alone cannot fix architectural problems
5. **When multiple configuration approaches fail across versions, consider alternative solutions** - OpenSIPS may handle this transaction flow differently
6. **Not all SIP proxy use cases are supported by all proxies** - This specific flow (automatic 100 Trying + upstream 100 Trying) may not be supported by Kamailio

