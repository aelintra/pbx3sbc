# Simplified Approach: Custom endpoint_locations Table + Simple SQL

**Date:** January 2026  
**Decision:** Simple SQL approach using custom `endpoint_locations` table

## What We Did

We use a **custom `endpoint_locations` table** with direct SQL queries. We do **NOT** use the OpenSIPS `location` table, and we do **NOT** use the `usrloc` or `registrar` modules.

## Changes Made

### 1. Removed Modules
- ❌ Removed `usrloc.so` module
- ❌ Removed `registrar.so` module
- ✅ No extra module dependencies

### 2. Simplified Code
- ✅ Direct SQL INSERT to `endpoint_locations` table (simple, straightforward)
- ✅ Direct SQL SELECT from `endpoint_locations` table (no function calls)
- ✅ No Request-URI manipulation
- ✅ No complex lookup() function calls
- ✅ Clear, maintainable code

### 3. Using Custom Table
- ✅ Using custom `endpoint_locations` table (created by `scripts/init-database.sh`)
- ✅ Simple SQL queries (working, tested approach)
- ✅ Direct control over data
- ✅ Custom schema optimized for our use case

## Table Schema

The `endpoint_locations` table has the following structure:

```sql
CREATE TABLE endpoint_locations (
    aor VARCHAR(255) PRIMARY KEY,
    contact_ip VARCHAR(45) NOT NULL,
    contact_port VARCHAR(10) NOT NULL,
    contact_uri VARCHAR(255) NOT NULL,
    expires DATETIME NOT NULL
);

CREATE INDEX idx_endpoint_locations_expires ON endpoint_locations(expires);
```

**Columns:**
- `aor` - Address of Record (e.g., "1000@example.com")
- `contact_ip` - Endpoint IP address
- `contact_port` - Endpoint port
- `contact_uri` - Full Contact URI (e.g., "sip:1000@192.168.1.138:5060")
- `expires` - Expiration timestamp (DATETIME)

## Benefits

1. **Simplicity:** Straightforward SQL queries, easy to understand
2. **Custom Structure:** Table schema optimized for our specific needs
3. **Direct Control:** Know exactly what's happening
4. **Fewer Dependencies:** No extra modules to load/configure
5. **Maintainability:** Simple code is easier to maintain
6. **Performance:** MySQL handles queries efficiently

## How It Works

### Registration (REGISTER handling)

When a REGISTER request is received, endpoint information is stored in `endpoint_locations`:

```opensips
# Extract endpoint info
$var(endpoint_aor) = $tU + "@" + $(tu{uri.domain});
$var(final_ip) = $si;  # Source IP
$var(final_port) = $sp;  # Source port
$var(contact_uri) = "sip:" + $tU + "@" + $var(final_ip) + ":" + $var(final_port);

# Store/update in endpoint_locations table
INSERT INTO endpoint_locations (aor, contact_ip, contact_port, contact_uri, expires) 
VALUES ('...', '...', '...', '...', DATE_ADD(NOW(), INTERVAL ... SECOND))
ON DUPLICATE KEY UPDATE contact_ip='...', contact_port='...', contact_uri='...', expires=...;
```

### Endpoint Lookup (route[ENDPOINT_LOOKUP])

When routing back to an endpoint (e.g., OPTIONS or NOTIFY from Asterisk), we query `endpoint_locations`:

```opensips
# Lookup endpoint by AoR
SELECT contact_ip, contact_port, contact_uri FROM endpoint_locations 
WHERE aor='...' AND expires > NOW() LIMIT 1;

# Or lookup by username pattern
SELECT contact_ip, contact_port, contact_uri FROM endpoint_locations 
WHERE aor LIKE 'username@%' AND expires > NOW() LIMIT 1;
```

## Comparison

| Aspect | usrloc/registrar | Simple SQL (endpoint_locations) |
|--------|------------------|--------------------------------|
| Complexity | High (modules, functions) | Low (SQL only) |
| Dependencies | 2 modules | 0 modules |
| Code clarity | Complex (Request-URI manipulation) | Simple (direct SQL queries) |
| Control | Indirect (through modules) | Direct (SQL queries) |
| Table structure | Standard OpenSIPS `location` table | Custom `endpoint_locations` table ✅ |
| Performance | Good (caching) | Good (MySQL fast) |
| Maintainability | Medium | High ✅ |

## What We Use

- ✅ Custom `endpoint_locations` table (created by init-database.sh)
- ✅ Simple SQL approach (working code)
- ✅ Direct control (transparency)
- ✅ Expiration handling via SQL WHERE clauses (expires > NOW())

## What We Do NOT Use

- ❌ `usrloc` module (removed)
- ❌ `registrar` module (removed)
- ❌ OpenSIPS `location` table (not used)
- ❌ `lookup()` function calls (SQL is simpler)
- ❌ Request-URI manipulation (not needed)

## Important Notes

**DO NOT confuse this with:**
- The OpenSIPS `location` table (we don't use it)
- The `usrloc` module (we don't use it)
- The `registrar` module (we don't use it)

**We use:**
- Custom `endpoint_locations` table only
- Direct SQL queries only
- No OpenSIPS modules for endpoint tracking

## Result

**Simple and effective:**
- Custom table structure (optimized for our needs)
- Simple SQL approach (maintainability, clarity)
- No extra modules (simplicity)
- Direct control (transparency)

This approach gives us full control over endpoint tracking without the complexity of OpenSIPS modules or the constraints of the standard `location` table structure.
