# Simplified Approach: Standard Table + Simple SQL

**Date:** January 2026  
**Decision:** Revert to simple SQL approach using standard location table structure

## What We Did

Reverted from usrloc/registrar modules back to simple SQL approach, but using the standard OpenSIPS `location` table structure instead of custom `endpoint_locations` table.

## Changes Made

### 1. Removed Modules
- ❌ Removed `usrloc.so` module
- ❌ Removed `registrar.so` module
- ✅ No extra module dependencies

### 2. Simplified Code
- ✅ Direct SQL INSERT to `location` table (simple, straightforward)
- ✅ Direct SQL SELECT from `location` table (no function calls)
- ✅ No Request-URI manipulation
- ✅ No complex lookup() function calls
- ✅ Clear, maintainable code

### 3. Using Standard Table
- ✅ Using `location` table from OpenSIPS schema (standard, compatible)
- ✅ Simple SQL queries (working, tested approach)
- ✅ Direct control over data

## Benefits

1. **Simplicity:** Straightforward SQL queries, easy to understand
2. **Standard Structure:** Using OpenSIPS standard location table
3. **Direct Control:** Know exactly what's happening
4. **Fewer Dependencies:** No extra modules to load/configure
5. **Maintainability:** Simple code is easier to maintain
6. **Performance:** SQLite is fast enough for our use case

## How It Works

### Registration (REGISTER handling)
```opensips
# Extract endpoint info
$var(username) = $tU;
$var(domain) = $(tu{uri.domain});
$var(contact_uri) = "sip:" + $var(username) + "@" + $var(final_ip) + ":" + $var(final_port);
$var(expires_timestamp) = $(Ts) + $var(expires_int);

# Delete existing, insert new (simple update)
DELETE FROM location WHERE username='...' AND domain='...';
INSERT INTO location (username, domain, contact, expires, ...) VALUES (...);
```

### Endpoint Lookup (route[ENDPOINT_LOOKUP])
```opensips
# Simple SQL query
SELECT contact FROM location WHERE username='...' AND domain='...' AND expires > strftime('%s', 'now');

# Extract IP/port from contact URI
if ($var(contact_uri) =~ "@([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})") {
    $var(endpoint_ip) = $re;
    # Extract port...
}
```

## Comparison

| Aspect | usrloc/registrar | Simple SQL |
|--------|------------------|------------|
| Complexity | High (modules, functions) | Low (SQL only) |
| Dependencies | 2 modules | 0 modules |
| Code clarity | Complex (Request-URI manipulation) | Simple (direct SQL) |
| Control | Indirect (through modules) | Direct (SQL queries) |
| Table structure | Standard | Standard ✅ |
| Performance | Good (caching) | Good (SQLite fast) |
| Maintainability | Medium | High ✅ |

## What We Kept

- ✅ Standard `location` table structure (compatibility)
- ✅ Simple SQL approach (working code)
- ✅ Direct control (transparency)
- ✅ Expiration handling via SQL WHERE clauses

## What We Removed

- ❌ usrloc module (unnecessary complexity)
- ❌ registrar module (unnecessary complexity)
- ❌ lookup() function calls (SQL is simpler)
- ❌ Request-URI manipulation (not needed)
- ❌ Legacy endpoint_locations table (using location table only)

## Result

**Best of both worlds:**
- Standard table structure (compatibility with OpenSIPS ecosystem)
- Simple SQL approach (maintainability, clarity)
- No extra modules (simplicity)
- Direct control (transparency)

This is the sweet spot: using the standard table structure without the complexity of usrloc/registrar modules.

