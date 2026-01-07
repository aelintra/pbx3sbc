# Database Schema Comparison: Custom vs OpenSIPS 3.6.3 Standard

**Date:** January 2026  
**Context:** Full OpenSIPS 3.6.3 database schema loaded from `dbsource/opensips-3.6.3-sqlite3.sql`

## Overview

The OpenSIPS 3.6.3 standard schema includes many tables we weren't using, most importantly:
- **`location` table** (usrloc module, version 1013) - Could replace our custom `endpoint_locations`
- **`domain` table** (version 4) - Different from our custom `sip_domains`
- **`dispatcher` table** (version 9) - Matches our schema ✅
- **`subscriber` table** (version 8) - For authentication (not currently used)

## Table Comparisons

### 1. Endpoint Location Storage

#### Our Custom Table: `endpoint_locations`
```sql
CREATE TABLE endpoint_locations (
    aor TEXT PRIMARY KEY,              -- Format: user@domain
    contact_ip TEXT NOT NULL,          -- Endpoint IP address
    contact_port TEXT NOT NULL,        -- Endpoint port
    expires TEXT NOT NULL              -- Expiration (SQLite datetime)
);
```

**Usage:**
- Manual INSERT/UPDATE via `sql_query()` in REGISTER handling
- Manual SELECT queries for endpoint lookup
- Simple structure, easy to query

#### OpenSIPS Standard: `location` (usrloc module)
```sql
CREATE TABLE location (
    contact_id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    username CHAR(64) DEFAULT '' NOT NULL,      -- Part of AoR
    domain CHAR(64) DEFAULT NULL,                -- Part of AoR
    contact TEXT NOT NULL,                       -- Full contact URI
    received CHAR(255) DEFAULT NULL,             -- Received parameter (NAT)
    path CHAR(255) DEFAULT NULL,                 -- Path header
    expires INTEGER NOT NULL,                     -- Expires (Unix timestamp)
    q FLOAT(10,2) DEFAULT 1.0 NOT NULL,         -- Q value
    callid CHAR(255) DEFAULT 'Default-Call-ID' NOT NULL,
    cseq INTEGER DEFAULT 13 NOT NULL,
    last_modified DATETIME DEFAULT '1900-01-01 00:00:01' NOT NULL,
    flags INTEGER DEFAULT 0 NOT NULL,
    cflags CHAR(255) DEFAULT NULL,
    user_agent CHAR(255) DEFAULT '' NOT NULL,
    socket CHAR(64) DEFAULT NULL,
    methods INTEGER DEFAULT NULL,
    sip_instance CHAR(255) DEFAULT NULL,
    kv_store TEXT(512) DEFAULT NULL,
    attr CHAR(255) DEFAULT NULL
);
```

**Usage:**
- Managed by usrloc module automatically
- Functions: `save()`, `lookup()`, `registered()` built-in
- More comprehensive (NAT support, Path header, etc.)
- Requires loading `usrloc` module

**Key Differences:**
| Feature | endpoint_locations | location (usrloc) |
|---------|-------------------|-------------------|
| AoR storage | Single `aor` field | Split `username` + `domain` |
| Contact info | `contact_ip` + `contact_port` | `contact` (full URI) |
| Expires format | TEXT (datetime) | INTEGER (Unix timestamp) |
| NAT support | Manual extraction | `received` field built-in |
| Management | Manual SQL queries | Module functions |
| Multiple contacts | No (PRIMARY KEY on aor) | Yes (multiple rows per AoR) |

### 2. Domain Routing

#### Our Custom Table: `sip_domains`
```sql
CREATE TABLE sip_domains (
    domain TEXT PRIMARY KEY,
    dispatcher_setid INTEGER NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    comment TEXT
);
```

**Usage:**
- Links domain to dispatcher set ID
- Custom routing logic

#### OpenSIPS Standard: `domain` table
```sql
CREATE TABLE domain (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    domain CHAR(64) DEFAULT '' NOT NULL,
    attrs CHAR(255) DEFAULT NULL,
    accept_subdomain INTEGER DEFAULT 0 NOT NULL,
    last_modified DATETIME DEFAULT '1900-01-01 00:00:01' NOT NULL,
    CONSTRAINT domain_domain_idx UNIQUE (domain)
);
```

**Key Differences:**
- Standard `domain` table doesn't have `dispatcher_setid` field
- We need our custom `sip_domains` for routing logic
- **Recommendation:** Keep `sip_domains`, don't use standard `domain` table

### 3. Dispatcher Table

#### Both Match ✅
```sql
CREATE TABLE dispatcher (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    setid INTEGER DEFAULT 0 NOT NULL,
    destination CHAR(192) DEFAULT '' NOT NULL,  -- Note: CHAR(192) in standard
    socket CHAR(128) DEFAULT NULL,
    state INTEGER DEFAULT 0 NOT NULL,
    probe_mode INTEGER DEFAULT 0 NOT NULL,
    weight CHAR(64) DEFAULT 1 NOT NULL,         -- TEXT in our version
    priority INTEGER DEFAULT 0 NOT NULL,
    attrs CHAR(128) DEFAULT NULL,                -- CHAR(128) vs TEXT
    description CHAR(64) DEFAULT NULL             -- CHAR(64) vs TEXT
);
```

**Minor Differences:**
- Standard uses `CHAR()` types, our uses `TEXT`
- Both are compatible (SQLite treats them similarly)
- **Recommendation:** Standard schema is fine, both work

## Migration Considerations

### Option 1: Keep Custom Tables (Current Approach)
**Pros:**
- ✅ Simple, straightforward queries
- ✅ Full control over schema
- ✅ No module dependencies
- ✅ Already working

**Cons:**
- ❌ Manual management (no automatic expiration)
- ❌ No built-in NAT handling
- ❌ Can't use usrloc module features

### Option 2: Migrate to usrloc Module
**Pros:**
- ✅ Automatic contact management
- ✅ Built-in NAT traversal support (`received` field)
- ✅ Multiple contacts per AoR support
- ✅ Standard OpenSIPS approach
- ✅ Automatic expiration handling

**Cons:**
- ❌ Requires refactoring REGISTER handling
- ❌ Need to learn usrloc module functions
- ❌ More complex queries (username + domain split)
- ❌ May need to extract IP/port from `contact` URI

### Option 3: Hybrid Approach
**Pros:**
- ✅ Use usrloc for REGISTER handling (automatic)
- ✅ Keep custom `endpoint_locations` for simple lookups
- ✅ Best of both worlds

**Cons:**
- ❌ Data duplication
- ❌ Need to sync both tables

## Recommendations

### For `sip_domains` Table
**✅ Keep custom table** - Standard `domain` table doesn't have `dispatcher_setid` field we need for routing.

### For `endpoint_locations` Table
**🤔 Evaluate usrloc module** - This is what you're currently evaluating. Consider:

1. **If usrloc module is loaded:**
   - Use `save()` function in REGISTER handling instead of manual INSERT
   - Use `lookup()` function for endpoint lookups instead of manual SELECT
   - Extract IP/port from `contact` URI when needed
   - Use `received` field for NAT traversal

2. **If keeping custom table:**
   - Continue with current approach
   - Consider adding automatic expiration cleanup

### For `dispatcher` Table
**✅ Use standard schema** - Both versions work, standard is fine.

## Code Changes Needed (if migrating to usrloc)

### Current REGISTER Handling (lines 262-372)
```opensips
# Current: Manual INSERT
$var(query) = "INSERT OR REPLACE INTO endpoint_locations ...";
sql_query($var(query), "$avp(reg_result)");
```

### With usrloc Module
```opensips
# New: Use usrloc save() function
if (!save("location")) {
    xlog("L_ERR", "Failed to save location\n");
}
```

### Current Endpoint Lookup (route[ENDPOINT_LOOKUP])
```opensips
# Current: Manual SELECT
$var(query) = "SELECT contact_ip FROM endpoint_locations WHERE aor='...'";
sql_query($var(query), "$avp(endpoint_ip)");
```

### With usrloc Module
```opensips
# New: Use usrloc lookup() function
if (lookup("location")) {
    # Contact info available in $du or $ru
    # Extract IP/port from contact URI
}
```

## Next Steps

1. **Evaluate usrloc module:**
   - Test if it meets our needs
   - Check if it handles NAT correctly
   - Verify expiration handling

2. **Decision point:**
   - Migrate to usrloc? (refactor code)
   - Keep custom table? (continue as-is)
   - Hybrid approach? (use both)

3. **Update init-database.sh:**
   - Ensure it creates both custom tables AND standard tables
   - Or decide which approach to use

4. **Update configuration:**
   - If using usrloc, load module and configure
   - Update REGISTER handling
   - Update endpoint lookup routes

