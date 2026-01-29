# Session Summary: usrloc lookup() Implementation Complete

**Date:** January 20, 2026  
**Status:** ✅ COMPLETE  
**Key Achievement:** Successfully implemented `lookup("location")` for OPTIONS/NOTIFY/INVITE routing

## Problem Statement

After fixing `save("location")` to work correctly, we needed to implement `lookup("location")` to replace SQL queries to `endpoint_locations` table for:
- OPTIONS requests from Asterisk to endpoints
- NOTIFY requests from Asterisk to endpoints  
- INVITE requests from Asterisk to endpoints

## Issues Encountered

### 1. REGISTER Contact Header Being Modified
**Problem:** `fix_nated_contact()` in general `onreply_route` was modifying REGISTER 200 OK Contact headers
- Asterisk sends: `<sip:1000@192.168.1.138:50368>;expires=599`
- OpenSIPS was forwarding: `<sip:1000@192.168.1.109:5060>;expires=599>` (wrong - Asterisk's IP)

**Solution:** Excluded REGISTER responses from `fix_nated_contact()`
```opensips
if (!is_method("REGISTER")) {
    fix_nated_contact();
}
```

### 2. NOTIFY Returning 476 Unresolvable Destination
**Problem:** Still using old SQL queries to `endpoint_locations` table instead of `lookup("location")`

**Solution:** Replaced SQL queries with `lookup("location")` function

### 3. lookup() Syntax Error
**Problem:** Used incorrect syntax `lookup("location", "uri", $var(lookup_uri))` - "uri" is not a valid flag

**Solution:** Set Request-URI first, then call `lookup("location")`
```opensips
$ru = $var(lookup_uri);
if (lookup("location")) {
    # $du is set automatically
}
```

### 4. Wildcard Lookup Support
**Problem:** When To header has IP address (not domain), need wildcard lookup `sip:1000@*`

**Solution:** Added SQL fallback for wildcard lookups
```opensips
if ($var(lookup_uri) =~ "@\\*") {
    # Use SQL query for wildcard lookup
    $var(query) = "SELECT contact FROM location WHERE username='...' AND expires > UNIX_TIMESTAMP() LIMIT 1";
}
```

## Implementation Details

### OPTIONS/NOTIFY Routing
**Location:** `config/opensips.cfg.template` lines ~234-300

**Logic:**
1. Extract username from Request-URI or To header
2. Extract domain from To header (if not IP address)
3. If domain is IP → use SQL wildcard lookup
4. If domain is present → use `lookup("location")` with domain-specific URI
5. If no domain → use SQL wildcard lookup

**Key Code:**
```opensips
# Domain-specific lookup
$ru = "sip:" + $var(endpoint_user) + "@" + $var(to_domain);
if (lookup("location")) {
    # $du is set automatically
    route(RELAY);
}

# Wildcard lookup (SQL fallback)
$var(query) = "SELECT contact FROM location WHERE username='" + $var(endpoint_user) + "' AND expires > UNIX_TIMESTAMP() LIMIT 1";
if (sql_query($var(query), "$avp(contact_uri)") && $(avp(contact_uri)[0]) != "") {
    $du = $(avp(contact_uri)[0]);
    route(RELAY);
}
```

### INVITE Routing
**Location:** `config/opensips.cfg.template` lines ~382-415

**Logic:**
1. Detect if Request-URI is endpoint (IP address instead of domain)
2. Extract username from Request-URI
3. Use SQL wildcard lookup (username-only, any domain)
4. Route to endpoint if found

**Key Code:**
```opensips
if ($var(request_domain) =~ "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})") {
    # Request-URI is endpoint IP
    $var(query) = "SELECT contact FROM location WHERE username='" + $var(endpoint_user) + "' AND expires > UNIX_TIMESTAMP() LIMIT 1";
    if (sql_query($var(query), "$avp(contact_uri)") && $(avp(contact_uri)[0]) != "") {
        $du = $(avp(contact_uri)[0]);
        $ru = $du;
        route(RELAY);
    }
}
```

## Test Results

### REGISTER
✅ Contact header preserved correctly
- Asterisk sends: `<sip:1000@192.168.1.138:50368>;expires=599`
- OpenSIPS forwards: `<sip:1000@192.168.1.138:50368>;expires=599` ✅

### OPTIONS
✅ Routing working correctly
- Asterisk → OpenSIPS → Endpoint → OpenSIPS → Asterisk
- `lookup()` finds contact and routes correctly

### NOTIFY
✅ Routing working correctly
- Asterisk → OpenSIPS → Endpoint → OpenSIPS → Asterisk
- No more 476 errors

### INVITE
✅ Routing working correctly
- Endpoint → OpenSIPS → Asterisk → OpenSIPS → Endpoint
- Both directions working (1000→1001 and 1001→1000)

## Current Status

✅ **Fully Working:**
- `save("location")` - Registrations saving to location table
- `lookup("location")` - OPTIONS/NOTIFY routing working
- INVITE routing - Using location table for endpoint lookup
- REGISTER Contact header - Preserved correctly
- Failed registrations - Correctly NOT creating records

## Files Modified

1. **`config/opensips.cfg.template`**
   - Fixed `fix_nated_contact()` to exclude REGISTER responses
   - Replaced SQL queries with `lookup("location")` for OPTIONS/NOTIFY
   - Updated INVITE routing to use location table

2. **`workingdocs/USRLOC-QUICK-REFERENCE.md`**
   - Updated status to reflect lookup() completion

3. **`docs/USRLOC-MIGRATION-PLAN.md`**
   - Updated status and completed items

## Key Learnings

1. **lookup() syntax:** Must set Request-URI first, then call `lookup("location")` - no flags needed
2. **Wildcard lookups:** `lookup()` doesn't support `@*` syntax directly - need SQL fallback
3. **fix_nated_contact():** Should NOT be applied to REGISTER responses (preserves endpoint Contact)
4. **Domain-specific lookups:** When domain is known, use `lookup("location")` with full URI
5. **Username-only lookups:** When domain is IP address, use SQL query to location table

## Next Steps (Optional Improvements)

1. **Improve domain detection:** Determine domain from dispatcher setid based on Asterisk source IP
   - This would enable proper domain-specific lookups even when To header has IP
   - Critical for multi-tenant deployments

2. **Remove old SQL queries:** Once domain detection is improved, can remove SQL fallbacks

3. **Test multi-tenant:** Verify with multiple domains/tenants that domain separation works correctly

4. **Performance testing:** Verify `db_mode=2` (cached DB) performance with real traffic

## Configuration Snippets

### OPTIONS/NOTIFY Lookup
```opensips
# Extract domain from To header
$var(to_domain) = $(tu{uri.domain});

if ($var(to_domain) =~ "^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}") {
    # IP address - use SQL wildcard lookup
    $var(query) = "SELECT contact FROM location WHERE username='...' LIMIT 1";
} else if ($var(to_domain) != "") {
    # Domain present - use lookup() with domain-specific URI
    $ru = "sip:" + $var(endpoint_user) + "@" + $var(to_domain);
    if (lookup("location")) {
        route(RELAY);
    }
}
```

### INVITE Lookup
```opensips
# Detect endpoint IP in Request-URI
if ($rd =~ "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})") {
    # Use SQL wildcard lookup
    $var(query) = "SELECT contact FROM location WHERE username='" + $rU + "' AND expires > UNIX_TIMESTAMP() LIMIT 1";
    if (sql_query($var(query), "$avp(contact_uri)") && $(avp(contact_uri)[0]) != "") {
        $du = $(avp(contact_uri)[0]);
        $ru = $du;
        route(RELAY);
    }
}
```

## References

- OpenSIPS 3.6.3 registrar module documentation
- OpenSIPS usrloc module documentation
- Previous session: `SESSION-SUMMARY-USRLOC-SAVE-FIX.md`
