# Architecture Decision: Proxy-Registrar Mode and NAT Handling

## Overview

This document explains why we're using proxy-registrar mode with OpenSIPS, the limitations this creates for automatic NAT handling in the `usrloc` module, and why manual NAT handling is necessary and correct.

## Architecture: Proxy-Registrar Mode

### What is Proxy-Registrar Mode?

In our deployment, OpenSIPS acts as a **Session Border Controller (SBC)** that:
1. **Proxies REGISTER requests** to Asterisk (the actual registrar)
2. **Saves location information** in OpenSIPS's `usrloc` module for routing purposes
3. **Routes calls** from Asterisk to endpoints using the location table

This is different from **pure registrar mode** where OpenSIPS would be the registrar itself.

### Why Proxy-Registrar Mode?

**Business Requirements:**
- Asterisk is the authoritative registrar (handles authentication, user management)
- OpenSIPS needs location information for routing calls to endpoints
- Multi-tenant support (same extension numbers across different domains)
- NAT traversal for endpoints behind firewalls

**Technical Benefits:**
- Asterisk handles all registrar logic (authentication, user provisioning)
- OpenSIPS handles routing and NAT traversal
- Separation of concerns

## The Problem: Automatic NAT Handling Doesn't Work

### How `usrloc` is Supposed to Work

In **pure registrar mode**, the `usrloc` module automatically:
1. Detects NAT using `fix_nated_register()`
2. Populates the `received` field with the public NAT IP:port from the original request source
3. Uses `received` field in `lookup()` to route to the correct NAT IP

### Why It Doesn't Work in Proxy-Registrar Mode

**The Issue:**
```
REGISTER Request Flow:
1. Endpoint (74.83.23.44:5060) → OpenSIPS (3.93.26.82:5060)
   - OpenSIPS captures: $si:$sp = 74.83.23.44:5060 ✓
   - OpenSIPS forwards to Asterisk
   
2. Asterisk (3.93.253.1) → OpenSIPS (3.93.26.82:5060)
   - 200 OK response
   - OpenSIPS in onreply_route: $si:$sp = 3.93.253.1:5060 ✗ (wrong!)
   
3. save("location") called in onreply_route
   - Transaction source = response source (Asterisk)
   - Original request source (endpoint) is lost
   - save() cannot populate 'received' field automatically
```

**Root Cause:**
- In `onreply_route`, the transaction context points to the **response source** (Asterisk), not the **original request source** (endpoint)
- `save()` tries to get the original source from the transaction, but it's not available in proxy-registrar mode
- The `received` field remains `NULL` or gets the wrong value

### Evidence from Our Code

Our code comments acknowledge this limitation:
```opensips
# CRITICAL: Ensure save() can populate 'received' field correctly
# save() should automatically populate 'received' from the transaction's original request source
# However, in proxy-registrar mode, the transaction source in onreply_route might be the response source
# We extract the original request source from Via header to verify it's available
# The registrar module's save() function should use this automatically if the transaction preserves it
```

And later:
```opensips
# save() should populate 'received' automatically, but it doesn't always work in proxy-registrar mode
```

## Our Solution: Manual NAT Handling

### Why Manual Handling is Necessary

Since automatic NAT handling doesn't work in proxy-registrar mode, we must:
1. **Capture original source** before forwarding REGISTER
2. **Manually update `received` field** after `save()`
3. **Manually extract `received` field** for routing (since `lookup()` may not use it correctly)

### Implementation Details

#### 1. Capture Original Source (Main Route)

```opensips
# CRITICAL: Capture original request source IP:port for NAT traversal
# In onreply_route, $si:$sp will be the response source (Asterisk), not the original request source
$avp(tu:reg_received) = $si + ":" + $sp;  # Transaction-scoped AVP
xlog("REGISTER: Captured original request source: $avp(reg_received)\n");
```

#### 2. Extract from Via Header (Fallback)

```opensips
# Fallback: Extract from Via header if AVP not available
$var(original_source) = $(hdr(Via)[1]{via.received}) + ":" + $(hdr(Via)[1]{via.rport});
```

#### 3. Manually Update `received` Field

```opensips
# Update the location record's 'received' field using SQL
$var(update_query) = "UPDATE location SET received='" + $var(received_value) + 
    "' WHERE username='" + $tU + "' AND domain='" + $(tu{uri.domain}) + 
    "' AND expires > UNIX_TIMESTAMP()";
sql_query($var(update_query));
```

#### 4. Manual Extraction for Routing

Instead of relying on `lookup()` to use `received` field, we:
- Query `received` field directly with SQL
- Extract IP:port using `SUBSTRING_INDEX()`
- Construct destination URI manually

## Is This Wrong?

**No, this is the correct approach for proxy-registrar mode.**

### Why This is Correct

1. **Proxy-registrar mode limitation**: This is a known limitation, not a bug
2. **Manual handling is expected**: When automatic handling doesn't work, manual handling is the solution
3. **We're using usrloc correctly**: We're using it for storage and expiration, just not relying on automatic NAT handling
4. **Our solution works**: All routing and NAT traversal is functioning correctly

### Alternative Approaches Considered

#### Option 1: Pure Registrar Mode
- **Pros**: Automatic NAT handling would work
- **Cons**: Would require moving all registrar logic from Asterisk to OpenSIPS (authentication, user management, provisioning)
- **Decision**: Not viable - Asterisk is the authoritative registrar

#### Option 2: Custom Location Table
- **Pros**: Full control, no proxy-registrar limitations
- **Cons**: Must reimplement expiration, cleanup, location management
- **Decision**: Not worth the effort - usrloc provides good value for storage/expiration

#### Option 3: Current Approach (Manual NAT Handling)
- **Pros**: Uses usrloc for storage/expiration, handles NAT correctly
- **Cons**: More complex code, manual workarounds
- **Decision**: ✅ **Chosen** - Best balance of functionality and complexity

## What We're Using `usrloc` For

### What Works Well

1. **Storage**: `save("location")` stores contact information correctly
2. **Expiration**: Automatic expiration handling works
3. **Domain-aware**: Multi-tenant support with `use_domain=1`
4. **Database persistence**: `db_mode=1` ensures immediate writes

### What We Handle Manually

1. **`received` field population**: Manual SQL UPDATE after `save()`
2. **NAT IP extraction**: Manual SQL queries with `SUBSTRING_INDEX()`
3. **Routing**: Manual destination URI construction
4. **Contact header fixing**: Manual header replacement in responses

## Current Status

**Working Correctly:**
- ✅ REGISTER saves location information
- ✅ `received` field is populated (via manual UPDATE)
- ✅ INVITE/OPTIONS/NOTIFY route to NAT IPs
- ✅ ACK/PRACK route to NAT IPs
- ✅ Contact headers fixed in responses
- ✅ Audio works correctly

**Complexity:**
- ⚠️ More code than ideal (manual workarounds)
- ⚠️ SQL queries instead of `lookup()` in many places
- ⚠️ Manual IP:port extraction instead of automatic

**But It Works:**
- ✅ All functionality is working
- ✅ NAT traversal is correct
- ✅ Multi-tenant support is working

## Recommendations

### Keep Current Approach

**Reasoning:**
1. It works correctly
2. Proxy-registrar mode limitation is unavoidable
3. Manual handling is the correct solution
4. Alternative approaches have significant drawbacks

### Future Improvements

1. **Simplify SQL extraction**: Could create helper routes for IP:port extraction
2. **Better error handling**: More robust fallbacks if `received` field is missing
3. **Documentation**: Keep this document updated as architecture evolves

### When to Reconsider

Consider alternatives if:
- OpenSIPS adds better proxy-registrar NAT support
- We need to move registrar logic to OpenSIPS anyway
- Performance becomes an issue with manual SQL queries

## Conclusion

**We are NOT doing something fundamentally wrong.**

We're using `usrloc` correctly for its intended purpose (location storage and expiration), but we're working around a known limitation of proxy-registrar mode for NAT handling. This is the correct architectural decision given our requirements.

The complexity we've added (manual NAT handling) is necessary and appropriate for proxy-registrar mode. The alternative would be to abandon proxy-registrar mode entirely, which would require significant architectural changes.

## Additional Findings: Path Headers and nat_uac_test()

### Path Headers and path-received

**Why we're not using `path-received`:**
- `path-received` requires Path headers to be present in REGISTER requests
- Path headers must be inserted by an intermediate proxy using `add_path_received()`
- We're not inserting Path headers in our current architecture
- Without Path headers, `path-received` cannot work
- **Conclusion**: Our manual `received` field update is correct for our architecture

**Could we use Path headers?**
- Yes, we could add Path header insertion before forwarding to Asterisk
- This would enable `path-received` and automatic `received` population
- Trade-off: Adds Path header complexity to messages
- **Decision**: Not necessary - our manual approach works correctly

### NAT Keepalives

**Why we're not using `nat_keepalive()`:**
- Asterisk (the registrar) handles NAT keepalives by sending OPTIONS packets
- OpenSIPS routes those OPTIONS packets correctly (already fixed)
- No need to duplicate keepalive functionality in OpenSIPS
- **Conclusion**: Delegating keepalives to Asterisk is the correct architectural choice

### NAT Detection: Manual vs nat_uac_test()

**Current Approach:**
- Custom `CHECK_PRIVATE_IP` route that checks RFC 1918 private IP ranges
- Script-based regex pattern matching
- Used in multiple places: INVITE route, RELAY route, Contact header fixing

**nat_uac_test() Alternative:**
- C-based detection (faster, more efficient)
- Checks multiple NAT indicators:
  - Flag 1: Private IP in Contact header
  - Flag 2: `received` IP differs from source IP
  - Flag 4: Private IP in Via header
  - Flag 8: Private IP in SDP
  - Flag 16: Source port differs from Via port
- More comprehensive (detects NAT even with public IPs via port/received mismatches)
- Standard OpenSIPS approach

**Assessment:**
- Our manual approach works but is less efficient and less comprehensive
- `nat_uac_test()` would be an optimization opportunity
- Can detect NAT scenarios beyond just private IP ranges
- **Status**: Optimization opportunity, not a critical issue

**Recommendation:**
- Consider switching to `nat_uac_test()` for initial NAT detection on requests
- Keep `CHECK_PRIVATE_IP` for cases where we've already extracted a specific IP
- Hybrid approach: Use `nat_uac_test()` for comprehensive detection, manual check for specific IPs

## References

- OpenSIPS usrloc module documentation
- OpenSIPS registrar module documentation
- OpenSIPS nathelper module documentation (`nat_uac_test()`)
- OpenSIPS path module documentation (Path headers, `path-received`)
- Proxy-registrar mode limitations (documented in code comments)
- Our implementation: `config/opensips.cfg.template`
- Related documents:
  - `SESSION-SUMMARY-NAT-RECEIVED-FIX.md`
  - `SESSION-SUMMARY-OPTIONS-NOTIFY-NAT-FIX.md`
  - `SESSION-SUMMARY-INVITE-ACK-AUDIO-FIX.md`
