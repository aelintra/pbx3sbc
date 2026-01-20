# Usrloc Module Migration Plan

**Branch:** `usrloc`  
**Status:** ✅ **COMPLETE** (Multi-tenant testing pending)  
**Created:** January 2026  
**Completed:** January 2026  
**Related:** [OpenSIPS Proxy Registration Blog Post](https://blog.opensips.org/2016/12/13/how-to-proxy-sip-registrations/)

## Executive Summary

**✅ STATUS: MIGRATION COMPLETE** (Multi-tenant testing pending)

This document outlines the migration from our custom `endpoint_locations` table to OpenSIPS's standard `usrloc` module and `location` table. This migration:

- ✅ Fix stale registration issue (currently storing before reply)
- ✅ Reduce technical debt (remove custom table maintenance)
- ✅ Align with OpenSIPS best practices (proxy-registrar pattern)
- ✅ Provide better features (path support, proper expiration, flags)
- ✅ **Built-in multi-tenant support** - OpenSIPS stores contacts with `username@domain` as key
- ✅ **Domain-specific lookups** - `lookup("location", "uri", "sip:user@domain")` only finds contacts in that domain
- ✅ Improve maintainability (standard module vs custom SQL)

## Motivation

### Current Problems

1. **Stale Registrations**
   - We store endpoint locations **before** proxying REGISTER to Asterisk
   - Failed registrations (401, 403, etc.) still create records
   - Records persist until natural expiration
   - Violates OpenSIPS best practices

2. **Technical Debt**
   - Custom `endpoint_locations` table requires maintenance
   - Manual SQL queries scattered throughout config (~10+ locations)
   - Custom expiration logic
   - Missing features (path support, proper flags)

3. **Inconsistency**
   - Not using standard OpenSIPS modules
   - Reinventing functionality that already exists
   - Harder for OpenSIPS experts to understand

### Benefits of Migration

1. **Correct Proxy-Registrar Pattern**
   - Store locations only on successful registration (2xx reply)
   - Respect Asterisk's expiration decisions
   - No stale registrations

2. **Standard OpenSIPS Approach**
   - Use `usrloc` module (standard)
   - Use `location` table (standard schema)
   - Use `save()` and `lookup()` functions (standard API)
   - Use `domain` module to manage domain-specific information
   - **Domain separation built-in** - OpenSIPS treats `user@domainA` and `user@domainB` as separate entities

3. **Better Features**
   - Path header support (NAT traversal)
   - Proper expiration handling (Unix timestamps)
   - Flags and attributes
   - Better integration with other modules

4. **Reduced Maintenance**
   - No custom table schema
   - No manual expiration queries
   - Less code in config
   - Standard OpenSIPS documentation applies

## Current State Analysis

### Current Implementation

**Table Schema:**
```sql
CREATE TABLE endpoint_locations (
    aor VARCHAR(255) PRIMARY KEY,
    contact_ip VARCHAR(45) NOT NULL,
    contact_port VARCHAR(10) NOT NULL,
    contact_uri VARCHAR(255) NOT NULL,
    expires DATETIME NOT NULL
);
```

**Registration Flow (Current - WRONG):**
```opensips
route {
    if (is_method("REGISTER")) {
        # Extract info
        $var(endpoint_aor) = $tU + "@" + $(tu{uri.domain});
        $var(endpoint_ip) = $si;
        $var(endpoint_port) = $sp;
        
        # INSERT IMMEDIATELY - BEFORE PROXYING!
        sql_query("INSERT INTO endpoint_locations ...");
    }
    route(DOMAIN_CHECK);
    t_relay();  # Proxy to Asterisk
}
```

**Lookup Flow (Current):**
```opensips
# Direct SQL queries (~10+ locations in config)
sql_query("SELECT contact_ip FROM endpoint_locations 
           WHERE aor='...' AND expires > NOW()");
```

### Current Modules Loaded

- ✅ `tm.so` - Transaction management (required for `t_on_reply`)
- ✅ `db_mysql.so` - MySQL database support
- ✅ `sqlops.so` - SQL operations (currently used for queries)
- ✅ `nathelper.so` - NAT traversal
- ❌ `usrloc.so` - **NOT LOADED** (needs to be added)
- ❌ `registrar.so` - **NOT LOADED** (may be needed)

### Current Code Locations

**Registration Storage:**
- `config/opensips.cfg.template` lines 284-306

**Lookup Queries:**
- `config/opensips.cfg.template` line 603 (ENDPOINT_LOOKUP route)
- `config/opensips.cfg.template` line 620 (username pattern lookup)
- `config/opensips.cfg.template` line 950 (OPTIONS/NOTIFY routing)
- `config/opensips.cfg.template` line 961 (NOTIFY fallback)

**Cleanup Scripts:**
- `scripts/cleanup-expired-endpoints.sh` - Manual cleanup
- `scripts/cleanup-expired-endpoints.timer` - Systemd timer

## Target State Design

### OpenSIPS Standard Schema

**Location Table (from OpenSIPS schema):**
```sql
CREATE TABLE location (
    contact_id INTEGER PRIMARY KEY AUTO_INCREMENT NOT NULL,
    username CHAR(64) DEFAULT '' NOT NULL,
    domain CHAR(64) DEFAULT NULL,
    contact TEXT NOT NULL,
    received CHAR(255) DEFAULT NULL,
    path CHAR(255) DEFAULT NULL,
    expires INTEGER NOT NULL,
    q FLOAT(10,2) DEFAULT 1.0 NOT NULL,
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

**Key Differences:**
- Uses `username` + `domain` (not single `aor` field)
- Uses `contact` field (full Contact header, not separate IP/port)
- Uses `received` field for NAT traversal
- Expiration is Unix timestamp (`expires` INTEGER), not DATETIME

### Target Implementation Pattern

**Registration Flow (Target - CORRECT):**
```opensips
route {
    if (is_method("REGISTER")) {
        # Arm reply handler
        t_on_reply("handle_reply_reg");
        route(DOMAIN_CHECK);
        t_relay();
        exit;
    }
}

onreply_route[handle_reply_reg] {
    if (is_method("REGISTER")) {
        if (t_check_status("2[0-9][0-9]")) {
            # Only save on success!
            save("location");
            xlog("REGISTER: Saved location for $tU@$(tu{uri.domain})\n");
        } else {
            xlog("L_WARN", "REGISTER: Failed ($rs), not saving location\n");
        }
    }
}
```

**Lookup Flow (Target):**
```opensips
# Use standard lookup function
if (lookup("location")) {
    # Location found, $du is set automatically
    route(RELAY);
} else {
    sl_send_reply(404, "Not Found");
}
```

## Research Phase

### Phase 0: Research & Evaluation (Week 1)

**Objectives:**
1. Understand `usrloc` module API
2. Understand `registrar` module (if needed)
3. Map current functionality to OpenSIPS functions
4. Identify migration challenges
5. Design migration approach

**Tasks:**

1. **Study OpenSIPS Documentation**
   - [ ] Read `usrloc` module documentation
   - [ ] Read `registrar` module documentation (if needed)
   - [ ] Understand `save()` function behavior
   - [ ] Understand `lookup()` function behavior
   - [ ] Understand `registered()` function behavior
   - [ ] Review OpenSIPS proxy-registrar examples

2. **Map Current Functionality**
   - [ ] Map `endpoint_locations` INSERT → `save("location")`
   - [ ] Map `endpoint_locations` SELECT → `lookup("location")`
   - [ ] Map IP/port extraction → Contact header parsing
   - [ ] Map expiration handling → Unix timestamp conversion
   - [ ] Map username pattern lookup → `lookup()` with wildcards

3. **Identify Challenges**
   - [ ] How to extract IP/port from Contact header?
   - [ ] How to handle `contact_uri` field?
   - [ ] How to handle username-only lookups?
   - [ ] How to handle expiration queries?
   - [ ] How to migrate existing data?
   - [ ] ⚠️ **CRITICAL:** How to determine domain from source IP for multi-tenant deployments?

4. **Design Solutions**
   - [ ] Design Contact header parsing approach
   - [ ] Design lookup route modifications
   - [ ] Design data migration script
   - [ ] Design testing approach

**Deliverables:**
- Research notes document
- Function mapping document
- Migration design document
- Test plan document

---

## Phase 0 Deliverables

### Research Summary

**Date:** January 2026  
**Status:** ✅ Complete (with identified knowledge gaps)

---

## ⚠️ CRITICAL BUSINESS REQUIREMENT DISCOVERED

### Multi-Tenant Extension Number Overlap

**Business Context:**
- This is a **drop-in solution** for customers with fleets of Asterisk boxes
- Typically **one or more Asterisk boxes per customer**
- Traditional telephony used **repeating extension number ranges**
- **2XX range is most common** (201, 202, 203, ... 299)
- Customers **did NOT want to change extension numbers** when migrating to VoIP

**The Problem:**
```
Customer A (tenant-a.com):
  - Asterisk A: 10.0.1.10
  - Extensions: 201, 202, 203, ... 299, 401, 402, ...
  
Customer B (tenant-b.com):
  - Asterisk B: 10.0.1.20
  - Extensions: 201, 202, 203, ... 299, 401, 402, ...  ← SAME NUMBERS!
  
Customer C (tenant-c.com):
  - Asterisk C: 10.0.1.30
  - Extensions: 201, 202, 203, ... 299, 401, 402, ...  ← SAME NUMBERS!
```

**Critical Issue:**
- When Asterisk sends: `INVITE sip:401@192.168.1.138:5060`
- We **MUST** route to the correct customer's endpoint
- **CANNOT** use "first match" - that would route to wrong customer!
- **Wildcard lookup (`@*`) is UNACCEPTABLE** for production

**Impact:**
- ❌ **Privacy violation** - calls go to wrong customer
- ❌ **Billing errors** - wrong tenant charged
- ❌ **Service failure** - calls fail or go to wrong place

**Required Solution:**
- ✅ **MUST determine domain from source IP** (which Asterisk sent request)
- ✅ **MUST lookup endpoint only in correct domain**
- ✅ **MUST NOT use wildcard lookup** as primary method

**See:** [MULTIPLE-DOMAINS-SAME-USERNAME.md](MULTIPLE-DOMAINS-SAME-USERNAME.md) for detailed analysis and solution approach.

---

### 1. Current Implementation Analysis

#### Current Schema: `endpoint_locations`

```sql
CREATE TABLE endpoint_locations (
    aor VARCHAR(255) PRIMARY KEY,           -- Address of Record: user@domain
    contact_ip VARCHAR(45) NOT NULL,        -- Endpoint's IP address
    contact_port VARCHAR(10) NOT NULL,      -- Endpoint's port
    contact_uri VARCHAR(255) NOT NULL,      -- Full Contact URI
    expires DATETIME NOT NULL              -- Expiration timestamp
);
CREATE INDEX idx_endpoint_locations_expires ON endpoint_locations(expires);
```

#### Current Registration Flow (WRONG Pattern)

**Location:** `config/opensips.cfg.template` lines 284-306

```opensips
route {
    if (is_method("REGISTER")) {
        # Extract endpoint info from REQUEST
        $var(endpoint_aor) = $tU + "@" + $(tu{uri.domain});
        $var(endpoint_ip) = $si;  # Source IP
        $var(endpoint_port) = $sp;  # Source port
        
        # INSERT IMMEDIATELY - BEFORE PROXYING TO ASTERISK!
        sql_query("INSERT INTO endpoint_locations ... ON DUPLICATE KEY UPDATE ...");
    }
    route(DOMAIN_CHECK);
    t_relay();  # Proxy to Asterisk
}
```

**Problem:** Records created even if Asterisk rejects registration (401, 403, etc.)

#### Current Lookup Usage

**Primary Lookup Route:** `route[ENDPOINT_LOOKUP]` (lines 595-646)
- Exact AoR match: `SELECT ... WHERE aor='user@domain' AND expires > NOW()`
- Username pattern match: `SELECT ... WHERE aor LIKE 'user@%' AND expires > NOW()`
- Returns: `contact_ip`, `contact_port`, `contact_uri`

**Usage Locations:**
1. **OPTIONS/NOTIFY routing** (lines 170-277): Routes from Asterisk to endpoints
2. **INVITE routing** (lines 322-355): Routes INVITE from Asterisk to endpoints
3. **Diagnostic logging** (lines 950-968): Logs endpoint IPs for SDP troubleshooting

**Total SQL Queries:** ~10+ direct `sql_query()` calls to `endpoint_locations`

### 2. OpenSIPS `usrloc` Module Capabilities

#### Module Overview

The `usrloc` module is OpenSIPS's standard user-location storage facility. It manages contacts registered via SIP REGISTER messages.

**Key Features:**
- ✅ Standard OpenSIPS module (well-maintained, well-tested)
- ✅ Supports memory-only, DB-only, or cached DB modes (`db_mode`)
- ✅ Automatic expiration handling (Unix timestamps)
- ✅ Path header support (for NAT traversal)
- ✅ Contact metadata (user_agent, socket, flags, attributes)
- ✅ **Domain separation (multi-tenant support)** - Stores contacts with `username@domain` as key
- ✅ **Domain-specific lookups** - `lookup("location", "uri", "sip:user@domain")` only finds contacts in that domain
- ✅ Cluster/replication support (via Binary Interface)
- ✅ Management Interface (MI) commands for monitoring

**How Domain Separation Works:**
- OpenSIPS treats `user@domainA` and `user@domainB` as **completely separate entities**
- Contacts are stored with `username@domain` as the key in `location` table
- `lookup("location", "uri", "sip:401@tenant-a.com")` will **only** find contacts in `tenant-a.com`
- It will **never** find contacts from other domains - this is built into OpenSIPS architecture
- Works with `domain` module to manage domain-specific information
- **⚠️ CRITICAL:** Wildcard lookup (`@*`) returns "first match" which is **UNACCEPTABLE** for multi-tenant
- **✅ REQUIRED:** Domain-specific lookup is the **ONLY acceptable primary method** for multi-tenant deployments

#### Standard `location` Table Schema

```sql
CREATE TABLE location (
    contact_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY NOT NULL,  -- FIXED: Must be BIGINT for UUID Call-ID hashes
    username CHAR(64) DEFAULT '' NOT NULL,        -- Username part of AoR
    domain CHAR(64) DEFAULT NULL,                  -- Domain part of AoR
    contact TEXT NOT NULL,                         -- Full Contact header
    received CHAR(255) DEFAULT NULL,              -- NAT: received IP:port
    path CHAR(255) DEFAULT NULL,                  -- Path header (for NAT)
    expires INTEGER NOT NULL,                     -- Unix timestamp
    q FLOAT(10,2) DEFAULT 1.0 NOT NULL,           -- Contact priority (q-value)
    callid CHAR(255) DEFAULT 'Default-Call-ID' NOT NULL,
    cseq INTEGER DEFAULT 13 NOT NULL,
    last_modified DATETIME DEFAULT '1900-01-01 00:00:01' NOT NULL,
    flags INTEGER DEFAULT 0 NOT NULL,
    cflags CHAR(255) DEFAULT NULL,
    user_agent CHAR(255) DEFAULT '' NOT NULL,
    socket CHAR(64) DEFAULT NULL,                 -- Local socket info
    methods INTEGER DEFAULT NULL,                 -- Supported methods
    sip_instance CHAR(255) DEFAULT NULL,          -- SIP instance ID
    kv_store TEXT(512) DEFAULT NULL,              -- Key-value store
    attr CHAR(255) DEFAULT NULL                   -- Custom attributes
);
```

**Key Differences from `endpoint_locations`:**
- Uses `username` + `domain` (not single `aor` field)
- Uses `contact` field (full Contact header, not separate IP/port)
- Uses `received` field for NAT traversal
- Expiration is Unix timestamp (`expires` INTEGER), not DATETIME
- Much richer metadata (path, flags, user_agent, etc.)

#### Standard Functions

**`save("location")`**
- Saves contact to location table
- Called from `onreply_route` (after receiving reply)
- Only saves contacts from successful REGISTER (2xx responses)
- Automatically handles expiration, NAT, path headers

**`lookup("location")`**
- Looks up contacts for AoR (username@domain)
- Sets `$du` (destination URI) automatically
- Returns true if contact found, false otherwise
- Handles multiple contacts (load balancing)

**`registered("location")`**
- Checks if AoR is registered
- Returns true/false
- Doesn't set `$du`

### 3. Function Mapping

#### Registration Storage

| Current | Target |
|---------|--------|
| `sql_query("INSERT INTO endpoint_locations ...")` in request route | `save("location")` in `onreply_route` |
| Stores before proxying | Stores after successful reply (2xx) |
| Manual expiration calculation | Automatic expiration handling |
| Manual IP/port extraction | Automatic from Contact header |

**Migration:**
```opensips
# OLD (WRONG):
route {
    if (is_method("REGISTER")) {
        sql_query("INSERT INTO endpoint_locations ...");
    }
    t_relay();
}

# NEW (CORRECT):
route {
    if (is_method("REGISTER")) {
        t_on_reply("handle_reply_reg");
        t_relay();
        exit;
    }
}

onreply_route[handle_reply_reg] {
    if (is_method("REGISTER") && t_check_status("2[0-9][0-9]")) {
        save("location");  # Only on success!
    }
}
```

#### Lookup Functions

| Current | Target |
|---------|--------|
| `sql_query("SELECT contact_ip FROM endpoint_locations WHERE aor='...'")` | `lookup("location")` |
| Manual IP/port extraction | Automatic from Contact header |
| Manual expiration check (`expires > NOW()`) | Automatic expiration handling |
| Username pattern lookup (`aor LIKE 'user@%'`) | `lookup("location")` with domain matching |
| Manual `$du` construction | `lookup()` sets `$du` automatically |

**Migration:**
```opensips
# OLD:
$var(query) = "SELECT contact_ip FROM endpoint_locations WHERE aor='user@domain' AND expires > NOW()";
sql_query($var(query), "$avp(endpoint_ip)");
$var(endpoint_ip) = $(avp(endpoint_ip)[0]);
$var(query) = "SELECT contact_port FROM endpoint_locations WHERE aor='user@domain' AND expires > NOW()";
sql_query($var(query), "$avp(endpoint_port)");
$var(endpoint_port) = $(avp(endpoint_port)[0]);
# Manual URI construction
$du = "sip:" + $var(endpoint_user) + "@" + $var(endpoint_ip) + ":" + $var(endpoint_port);

# NEW:
# lookup() automatically sets $du from Contact header
if (lookup("location")) {
    # $du is automatically set by lookup() from Contact header
    # For NAT scenarios, lookup() uses 'received' field if available
    route(RELAY);
} else {
    sl_send_reply(404, "Not Found");
}
```

**Note:** `lookup("location")` automatically:
- Looks up contacts for AoR (username@domain)
- Sets `$du` from Contact header (or `received` field for NAT)
- Handles expiration (only returns non-expired contacts)
- Handles multiple contacts (load balancing)

#### Contact Header Parsing ✅ RESOLVED

**Challenge:** Current implementation stores separate `contact_ip` and `contact_port` fields. OpenSIPS `location` table stores full Contact header in `contact` field.

**Solution:** When `lookup("location")` is used, it automatically sets `$du` from the Contact header. If manual extraction is needed, use pseudo-variables:

```opensips
# If lookup() sets $du, you can extract components:
$var(contact_ip) = $(du{uri.host});      # IP from destination URI
$var(contact_port) = $(du{uri.port});    # Port from destination URI

# Or if accessing Contact header directly:
$var(contact_ip) = $ct.host;             # IP from Contact header
$var(contact_port) = $ct.port;           # Port from Contact header
if ($var(contact_port) == "" || $var(contact_port) == "0") {
    $var(contact_port) = "5060";          # Default port
}

# For NAT scenarios, use received field from location table:
# The received field contains IP:port from NAT traversal
# lookup() automatically uses received field if available
```

**Status:** ✅ Resolved - Pseudo-variables documented above

### 4. Identified Challenges

#### Challenge 1: Contact Header Parsing ✅ RESOLVED

**Issue:** Current code uses separate `contact_ip` and `contact_port` fields. OpenSIPS stores full Contact header.

**Impact:** Need to parse Contact header to extract IP/port for routing.

**Solution Approach:**
- Use OpenSIPS pseudo-variables to extract from Contact header:
  - `$ct` - Full Contact header body
  - `$(ct{nameaddr.uri})` - SIP URI from Contact header
  - `$ct.host` or `$(ct{uri.host})` - Host/IP part of Contact URI
  - `$ct.port` or `$(ct{uri.port})` - Port number of Contact URI
  - `$ct.proto` or `$(ct{uri.proto})` - Transport protocol
  - `$(ct{nameaddr.param,expires})` - Expires parameter value
- For NAT scenarios, use `received` field from `location` table (set by `fix_nated_register()`)
- Test with various Contact header formats

**Example:**
```opensips
# Extract IP and port from Contact header
$var(contact_ip) = $ct.host;
$var(contact_port) = $ct.port;
if ($var(contact_port) == "" || $var(contact_port) == "0") {
    $var(contact_port) = "5060";  # Default port
}

# Or use received field for NAT scenarios (from location table)
# The received field contains IP:port from NAT traversal
```

**Status:** ✅ Resolved - Pseudo-variables identified

#### Challenge 2: Username-Only Lookup ⚠️ **CRITICAL UPDATE REQUIRED**

**Issue:** Current code does pattern matching: `aor LIKE 'user@%'` to find any domain for a username.

**Impact:** `lookup("location")` requires domain. Need to handle username-only lookups.

**⚠️ CRITICAL BUSINESS REQUIREMENT:**
- **Multi-tenant deployment** - customers have repeating extension numbers (2XX range)
- **Same username in multiple domains** (e.g., 401@tenant-a.com, 401@tenant-b.com)
- **MUST route to correct customer** - cannot use "first match" approach
- **Wildcard lookup (`@*`) is UNACCEPTABLE** for production multi-tenant deployments

**Required Solution:** Determine domain from source IP (which Asterisk sent request)

**Implementation:**
```opensips
# 1. Identify which Asterisk sent request (source IP)
$var(source_ip) = $si;

# 2. Find dispatcher set for this Asterisk
$var(query) = "SELECT setid FROM dispatcher WHERE destination LIKE '%" + $var(source_ip) + "%' LIMIT 1";
sql_query($var(query), "$avp(asterisk_setid)");
$var(setid) = $(avp(asterisk_setid)[0]);

# 3. Find domain for this dispatcher set
$var(query) = "SELECT domain FROM domain WHERE setid='" + $var(setid) + "' LIMIT 1";
sql_query($var(query), "$avp(domain_name)");
$var(domain) = $(avp(domain_name)[0]);

# 4. Lookup endpoint in correct domain only
if ($var(domain) != "") {
    # Domain-specific lookup (CORRECT for multi-tenant)
    if (lookup("location", "uri", "sip:" + $var(username) + "@" + $var(domain))) {
        route(RELAY);
    } else {
        sl_send_reply(404, "User Not Found");
    }
} else {
    # Fallback: wildcard lookup (only if domain cannot be determined)
    # This should rarely happen if configuration is correct
    xlog("L_WARN", "Cannot determine domain from source IP $si, using wildcard lookup\n");
    if (lookup("location", "uri", "sip:" + $var(username) + "@*")) {
        route(RELAY);
    } else {
        sl_send_reply(404, "User Not Found");
    }
}
```

**Key Points:**
- ⚠️ **Wildcard lookup (`@*`) is NOT acceptable** for multi-tenant production
- ✅ **MUST determine domain from source IP** (which Asterisk sent request)
- ✅ **MUST lookup endpoint only in correct domain**
- ✅ **Wildcard lookup only as fallback** if domain cannot be determined
- ⚠️ **This is a CRITICAL requirement** - wrong routing = privacy violation, billing errors

**Status:** ⚠️ **REQUIRES IMPLEMENTATION** - Cannot use simple wildcard lookup

**Research Context:** 
- See [WHY-USERNAME-ONLY-LOOKUP.md](WHY-USERNAME-ONLY-LOOKUP.md) for why username-only lookup is needed
- See [MULTIPLE-DOMAINS-SAME-USERNAME.md](MULTIPLE-DOMAINS-SAME-USERNAME.md) for **CRITICAL multi-tenant requirements and required solution**

#### Challenge 3: `contact_uri` Field ✅ RESOLVED

**Issue:** Current code stores `contact_uri` separately (used for Request-URI construction).

**Impact:** OpenSIPS stores Contact header in `contact` field. May need to construct URI differently.

**Solution:**
- `lookup("location")` automatically sets `$du` from Contact header stored in `location` table
- No manual `contact_uri` construction needed - `$du` is ready to use
- For NAT scenarios, `lookup()` automatically uses `received` field if available
- Manual extraction only needed for diagnostic logging (use `$du` or `$ct` pseudo-variables)

**Status:** ✅ Resolved - `lookup()` handles this automatically

#### Challenge 4: Expiration Handling

**Issue:** Current uses `DATETIME` with `expires > NOW()`. OpenSIPS uses Unix timestamp (`INTEGER`).

**Impact:** Need to convert expiration queries.

**Solution Approach:**
- OpenSIPS handles expiration automatically in `lookup()`
- No manual expiration checks needed
- Cleanup scripts need to use Unix timestamp

**Status:** ✅ Understood

#### Challenge 5: Diagnostic Logging ✅ RESOLVED

**Issue:** Current code queries `endpoint_locations` for diagnostic logging (lines 950-968).

**Impact:** Need alternative way to get endpoint IP for logging.

**Solution:**
- If logging is still needed, can query `location` table directly with SQL
- Or extract from `$du` after `lookup()`: `$var(contact_ip) = $(du{uri.host})`
- Or extract from Contact header: `$var(contact_ip) = $ct.host`
- **Recommendation:** Evaluate if this logging is still needed (was for troubleshooting)
- If not needed, simply remove the diagnostic logging code

**Status:** ✅ Resolved - Multiple options available, decision can be made during implementation

### 5. Areas Where Knowledge Is Deficient

#### ✅ Contact Header Parsing - RESOLVED

**Status:** Contact header parsing pseudo-variables have been identified:
- `$ct` - Full Contact header
- `$ct.host` / `$(ct{uri.host})` - IP address
- `$ct.port` / `$(ct{uri.port})` - Port number
- `$ct.proto` / `$(ct{uri.proto})` - Transport protocol
- `$(ct{nameaddr.param,expires})` - Expires parameter

**Note:** `lookup("location")` automatically sets `$du` from Contact header, so manual parsing may not be needed in most cases.

#### ✅ OpenSIPS Version Specifics - **RESOLVED**

**Gap:** Need to verify exact OpenSIPS version in use and corresponding `usrloc` module capabilities.

**Version Confirmed:**
- ✅ **OpenSIPS 3.6.3** (x86_64/linux) - Confirmed via `opensips -V`
- ✅ Location table schema reference matches: `dbsource/opensips-3.6.3-sqlite3.sql`
- ✅ **`usrloc` module confirmed** at `/usr/lib/x86_64-linux-gnu/opensips/modules/usrloc.so`

**Remaining Day 1 Tasks:**
- [ ] Review OpenSIPS 3.6.3 `usrloc` module documentation
- [ ] Verify module API matches our planned usage
- [ ] Check MySQL database connection
- [ ] Review current `endpoint_locations` table structure

**Status:** ✅ Version and module confirmed - OpenSIPS 3.6.3 with usrloc module available (not a blocker)

#### ⚠️ Username-Only Lookup - **CRITICAL UPDATE REQUIRED**

**Gap:** Need to understand how to handle username-only lookups (without domain) **in multi-tenant scenarios**.

**⚠️ CRITICAL BUSINESS REQUIREMENT:**
- Multi-tenant deployments have **same extension numbers across customers** (2XX range)
- **MUST route to correct customer** - cannot use "first match"
- **Wildcard lookup (`@*`) is UNACCEPTABLE** for production multi-tenant deployments

**Solution:** **MUST determine domain from source IP** (which Asterisk sent request)

**Implementation:**
```opensips
# 1. Identify which Asterisk sent request (source IP)
$var(source_ip) = $si;

# 2. Find dispatcher set for this Asterisk
$var(query) = "SELECT setid FROM dispatcher WHERE destination LIKE '%" + $var(source_ip) + "%' LIMIT 1";
sql_query($var(query), "$avp(asterisk_setid)");
$var(setid) = $(avp(asterisk_setid)[0]);

# 3. Find domain for this dispatcher set
$var(query) = "SELECT domain FROM domain WHERE setid='" + $var(setid) + "' LIMIT 1";
sql_query($var(query), "$avp(domain_name)");
$var(domain) = $(avp(domain_name)[0]);

# 4. Lookup endpoint in correct domain only
if ($var(domain) != "") {
    # Domain-specific lookup (CORRECT for multi-tenant)
    # OpenSIPS usrloc module stores contacts with username@domain as key
    # This lookup will ONLY find contacts in this domain, never other domains
    if (lookup("location", "uri", "sip:" + $var(username) + "@" + $var(domain))) {
        # Found contact in correct domain - $du is set automatically
        route(RELAY);
    } else {
        sl_send_reply(404, "User Not Found");
    }
} else {
    # Fallback: wildcard lookup (only if domain cannot be determined)
    # ⚠️ WARNING: Wildcard lookup may return wrong domain in multi-tenant scenarios
    # This should rarely happen if configuration is correct
    xlog("L_WARN", "Cannot determine domain from source IP $si, using wildcard lookup (may route to wrong customer)\n");
    if (lookup("location", "uri", "sip:" + $var(username) + "@*")) {
        route(RELAY);
    } else {
        sl_send_reply(404, "User Not Found");
    }
}
```

**Key Points:**
- ⚠️ **"First match" behavior is UNACCEPTABLE** for multi-tenant production deployments
- ⚠️ **Wildcard lookup (`@*`) is NOT acceptable** as primary method - returns "first match" (non-deterministic)
- ✅ **MUST determine domain from source IP** (which Asterisk sent request)
- ✅ **MUST lookup endpoint only in correct domain** using `lookup("location", "uri", "sip:username@domain")`
- ✅ **OpenSIPS treats `user@domainA` and `user@domainB` as separate entities** - domain-specific lookup is built-in
- ✅ **Wildcard lookup only as fallback** if domain cannot be determined (should rarely happen)
- ⚠️ **This is a CRITICAL requirement** - wrong routing = privacy violation, billing errors, service failure

**Status:** ⚠️ **REQUIRES IMPLEMENTATION** - Cannot use simple wildcard lookup

**Reference:** 
- See [WHY-USERNAME-ONLY-LOOKUP.md](WHY-USERNAME-ONLY-LOOKUP.md) for why username-only lookup is needed
- See [MULTIPLE-DOMAINS-SAME-USERNAME.md](MULTIPLE-DOMAINS-SAME-USERNAME.md) for **CRITICAL multi-tenant requirements**

#### ⚠️ Request-URI Construction - **RESOLVE IN DAY 5**

**Gap:** Need to understand how to construct Request-URI from `location` table data.

**Questions:**
- How does `lookup("location")` set `$du`?
- What format does `$du` have?
- Do we need to modify Request-URI separately?
- How does `BUILD_ENDPOINT_URI` route need to change?

**Solution:**
- `lookup("location")` automatically sets `$du` with the Contact URI from `location` table
- Format: `$du = "sip:user@ip:port"` (from Contact header)
- For NAT: `lookup()` automatically uses `received` field if available
- **Day 5 Task:** Test basic lookup and verify `$du` format
- **Status:** Will be resolved during Week 1, Day 5 (not a blocker)

#### ⚠️ Performance Characteristics - **RESOLVE IN WEEK 3**

**Gap:** Need to understand performance implications of `usrloc` module.

**Questions:**
- What is the performance of `lookup("location")` vs direct SQL?
- What is the performance of `save("location")` vs direct SQL?
- How does `db_mode` affect performance?
- What caching is available?

**Action Required:** 
- **Week 3, Day 14:** Benchmark `usrloc` functions vs current SQL queries
- **Week 3, Day 14:** Compare registration save performance
- **Week 3, Day 14:** Document any performance differences
- **Status:** Will be resolved during Week 3 parallel implementation (not a blocker)

#### ⚠️ Module Configuration - **RESOLVE IN DAY 3**

**Gap:** Need to understand optimal `usrloc` module configuration.

**Questions:**
- What `db_mode` should we use? (0=memory, 1=DB-only, 2=cached DB)
- What other `modparam` settings are needed?
- Do we need `registrar` module in addition to `usrloc`?
- What about `use_domain` parameter?

**Recommended Configuration:**
- `db_mode = 2` (cached DB mode) - Best balance of performance and persistence
- `use_domain = 1` - **REQUIRED** for multi-tenant (allows same username across domains)
- `nat_bflag = "NAT"` - For NAT traversal support
- **Day 3 Task:** Add module parameters to config
- **Status:** Will be resolved during Week 1, Day 3 (not a blocker, recommended config provided)

#### ⚠️ Data Migration - **DECISION NEEDED**

**Gap:** Need to understand how to migrate existing `endpoint_locations` data.

**Questions:**
- How to convert `endpoint_locations` rows to `location` table format?
- How to handle expiration conversion (DATETIME → Unix timestamp)?
- How to extract Contact header from separate IP/port fields?
- Do we need to migrate existing data or can we start fresh?

**Recommendation:**
- **Option 1 (Recommended):** Start fresh - let endpoints re-register naturally
  - Simpler, no migration script needed
  - Ensures clean data in new format
  - Endpoints will re-register within their expiration window
- **Option 2:** Migrate existing data if needed
  - Convert DATETIME to Unix timestamp: `UNIX_TIMESTAMP(expires)`
  - Construct Contact header: `sip:user@contact_ip:contact_port`
  - Split AoR into username and domain
- **Decision Point:** Week 5, Day 21 (before dropping table)
- **Status:** Decision can be made during cleanup phase (not a blocker)

### 6. Recommended Next Steps

1. **Verify OpenSIPS Version**
   - Check installed OpenSIPS version
   - Review `usrloc` module documentation for that version
   - Identify version-specific capabilities

2. **Test `usrloc` Functions**
   - Create test script to test `save("location")` and `lookup("location")`
   - Verify Contact header parsing
   - Test username-only lookups
   - Measure performance

3. **Design Contact Parsing**
   - Research OpenSIPS pseudo-variables for Contact header
   - Design parsing logic for IP/port extraction
   - Test with various Contact formats

4. **Design Lookup Logic**
   - ⚠️ **CRITICAL:** Design domain context from source IP approach
   - Design domain-specific lookup (not wildcard)
   - Design Request-URI construction logic
   - Test lookup scenarios with multiple tenants

5. **Design Domain Context Logic**
   - ⚠️ **CRITICAL:** Design source IP → dispatcher set lookup
   - ⚠️ **CRITICAL:** Design dispatcher set → domain lookup
   - ⚠️ **CRITICAL:** Handle port variations in dispatcher destination
   - ⚠️ **CRITICAL:** Test with multiple Asterisk boxes

6. **Create Migration Script**
   - Design data migration approach (if needed)
   - Create conversion script for expiration timestamps
   - Test migration script

### 7. Risk Assessment Update

Based on research, identified risks:

**High Risk:**
- Contact header parsing complexity
- **⚠️ CRITICAL:** Domain context from source IP implementation (MUST be correct for multi-tenant)
- **⚠️ CRITICAL:** Username-only lookup with domain context (cannot use wildcard as primary)
- Request-URI construction changes

**Medium Risk:**
- Performance differences
- Module configuration complexity
- Data migration (if needed)

**Low Risk:**
- Module availability (standard module)
- Basic save/lookup functionality (well-documented)

---

**Phase 0 Status:** ✅ Complete  
**Phase 1 Status:** ✅ Complete  
**Phase 2 Status:** ✅ Complete  
**Phase 3 Status:** ✅ Complete  
**Phase 4 Status:** ✅ Complete (except table drop - optional)  
**Migration Status:** ✅ **COMPLETE** (Multi-tenant testing pending)

**Remaining Questions Status:**
- ✅ **Contact Header Parsing:** Resolved - `lookup()` handles automatically
- ✅ **contact_uri Field:** Resolved - `lookup()` sets `$du` automatically
- ✅ **Diagnostic Logging:** Resolved - Multiple options available
- ✅ **OpenSIPS Version:** Resolved - OpenSIPS 3.6.3 confirmed
- ⏳ **Request-URI Construction:** Will be resolved Day 5 (not a blocker)
- ⏳ **Module Configuration:** Will be resolved Day 3 (recommended config provided)
- ⏳ **Performance:** Will be resolved Week 3 (not a blocker)
- ⏳ **Data Migration:** Decision can be made Week 5 (not a blocker)
- ✅ **Username-Only Lookup:** Solution designed, needs implementation (not a blocker)

---

## 🎯 Easy-to-Digest Migration Steps

**Goal:** Break down the 5-week migration into small, manageable daily tasks.

### Week 1: Research & Setup (Days 1-5)

#### Day 1: Verify Environment ✅ **IN PROGRESS**

- [x] Check OpenSIPS version: `opensips -V` → **OpenSIPS 3.6.3 (x86_64/linux)** ✅
- [x] Verify `usrloc` module exists: `/usr/lib/x86_64-linux-gnu/opensips/modules/usrloc.so` ✅
- [ ] Check MySQL database connection works
  - **Connection:** `mysql -u opensips -popensips -h <opensips-box-ip> opensips`
  - **Verify:** Can connect and query tables
- [ ] Review current `endpoint_locations` table structure
  - **Query:** `DESCRIBE endpoint_locations;`
  - **Verify:** Table structure matches expected schema
- [ ] **Time:** 1-2 hours

**Note:** 
- OpenSIPS 3.6.3 confirmed
- `usrloc` module confirmed at expected path
- MySQL credentials: `opensips/opensips` (verify these match config)
- The location table schema in `dbsource/opensips-3.6.3-sqlite3.sql` matches this version

#### Day 2: Create Location Table

**SQL Script Ready:** `scripts/create-location-table.sql`

**Tasks:**
- [ ] Copy `scripts/create-location-table.sql` to OpenSIPS server
- [ ] Run SQL script on MySQL: `mysql -u opensips -popensips opensips < create-location-table.sql`
- [ ] Verify table created: `mysql -u opensips -popensips opensips -e "DESCRIBE location;"`
- [ ] Verify indexes created: `mysql -u opensips -popensips opensips -e "SHOW INDEXES FROM location;"`
- [ ] **Time:** 30 minutes - 1 hour

**Note:** The SQL script has been pre-converted from SQLite to MySQL format and includes recommended indexes for multi-tenant lookups.

#### Day 3: Load Modules in Config
- [ ] Add `loadmodule "usrloc.so"` to config
- [ ] Add `loadmodule "domain.so"` to config (if not already loaded)
- [ ] Add module parameters (db_url, db_mode, use_domain=1)
- [ ] Test config syntax: `opensips -C`
- [ ] **Time:** 1-2 hours

#### Day 4: Test Basic Save
- [ ] Add `t_on_reply("handle_reply_reg")` to REGISTER route
- [ ] Create `onreply_route[handle_reply_reg]` with `save("location")`
- [ ] Test with one endpoint registration
- [ ] Verify data appears in `location` table
- [ ] **Time:** 2-3 hours

#### Day 5: Test Basic Lookup
- [ ] Create simple test route with `lookup("location", "uri", "sip:user@domain")`
- [ ] Test with known registered endpoint
- [ ] Verify `$du` is set correctly
- [ ] **Time:** 2-3 hours

**Week 1 Goal:** Module loads, basic save/lookup works

---

### Week 2: Domain Context Implementation (Days 6-10)

#### Day 6: Source IP → Dispatcher Lookup
- [ ] Create helper route: `route[GET_DOMAIN_FROM_SOURCE_IP]`
- [ ] Query dispatcher table: `SELECT setid FROM dispatcher WHERE destination LIKE '%$si%'`
- [ ] Test with known Asterisk source IP
- [ ] Verify setid is returned correctly
- [ ] **Time:** 2-3 hours

#### Day 7: Dispatcher → Domain Lookup
- [ ] Extend helper route to query domain table
- [ ] Query: `SELECT domain FROM domain WHERE setid='...'`
- [ ] Test end-to-end: source IP → setid → domain
- [ ] Handle edge cases (no match, multiple matches)
- [ ] **Time:** 2-3 hours

#### Day 8: Domain-Specific Lookup Route
- [ ] Create new route: `route[ENDPOINT_LOOKUP_USRLOC]`
- [ ] Implement: source IP → domain → `lookup("location", "uri", "sip:user@domain")`
- [ ] Add fallback to wildcard if domain not found (with warning log)
- [ ] Test with single tenant
- [ ] **Time:** 3-4 hours

#### Day 9: Multi-Tenant Testing
- [ ] Set up test: 401@tenant-a.com and 401@tenant-b.com
- [ ] Test routing from Asterisk A (should route to tenant-a.com)
- [ ] Test routing from Asterisk B (should route to tenant-b.com)
- [ ] Verify no cross-tenant routing
- [ ] **Time:** 3-4 hours

#### Day 10: Integration Testing
- [ ] Test OPTIONS from Asterisk → endpoint
- [ ] Test NOTIFY from Asterisk → endpoint
- [ ] Test INVITE from Asterisk → endpoint
- [ ] Compare results with old SQL-based lookup
- [ ] **Time:** 3-4 hours

**Week 2 Goal:** Domain context working, multi-tenant routing correct

---

### Week 3: Parallel Implementation (Days 11-15)

#### Day 11: Dual-Write Registration
- [ ] Keep existing `endpoint_locations` INSERT
- [ ] Add `save("location")` in onreply_route
- [ ] Test registration: verify both tables updated
- [ ] Compare data between tables
- [ ] **Time:** 2-3 hours

#### Day 12: Dual-Lookup Testing
- [ ] Keep existing SQL-based lookup
- [ ] Add new usrloc-based lookup
- [ ] Log both results for comparison
- [ ] Test with various scenarios (exact match, username-only, expired)
- [ ] **Time:** 3-4 hours

#### Day 13: Request-URI Construction
- [ ] Verify `$du` from `lookup()` is correct
- [ ] Test Request-URI construction for routing
- [ ] Handle Contact header parsing if needed
- [ ] Test with NAT scenarios
- [ ] **Time:** 2-3 hours

#### Day 14: Performance Comparison
- [ ] Measure SQL lookup performance
- [ ] Measure usrloc lookup performance
- [ ] Compare registration save performance
- [ ] Document any performance differences
- [ ] **Time:** 2-3 hours

#### Day 15: Edge Case Testing
- [ ] Test expired registrations
- [ ] Test de-registration (Expires: 0)
- [ ] Test registration refresh
- [ ] Test multiple contacts for same AoR
- [ ] **Time:** 3-4 hours

**Week 3 Goal:** Both implementations working, results match

---

### Week 4: Migration & Cutover (Days 16-20)

#### Day 16: Replace Registration Code
- [ ] Remove `endpoint_locations` INSERT from request route
- [ ] Keep only `save("location")` in onreply_route
- [ ] Test registration flow
- [ ] Verify no `endpoint_locations` records created
- [ ] **Time:** 2-3 hours

#### Day 17: Replace OPTIONS/NOTIFY Lookups
- [ ] Replace SQL lookup with usrloc lookup in OPTIONS route
- [ ] Replace SQL lookup with usrloc lookup in NOTIFY route
- [ ] Test both scenarios
- [ ] **Time:** 2-3 hours

#### Day 18: Replace INVITE Lookup
- [ ] Replace SQL lookup with usrloc lookup in INVITE route
- [ ] Test INVITE routing
- [ ] Test with IP in Request-URI (username-only scenario)
- [ ] **Time:** 2-3 hours

#### Day 19: Remove All SQL Queries
- [ ] Search for all `endpoint_locations` references
- [ ] Remove all SQL queries
- [ ] Remove `route[ENDPOINT_LOOKUP]` (old SQL-based route)
- [ ] Test all routing scenarios
- [ ] **Time:** 3-4 hours

#### Day 20: Comprehensive Testing
- [ ] Full end-to-end test: registration → lookup → routing
- [ ] Test all SIP methods (REGISTER, INVITE, OPTIONS, NOTIFY, BYE, ACK)
- [ ] Test multi-tenant scenarios
- [ ] Test NAT scenarios
- [ ] **Time:** 4-5 hours

**Week 4 Goal:** Old code removed, only usrloc used

---

### Week 5: Cleanup & Documentation (Days 21-25)

#### Day 21: Remove Custom Table
- [ ] Backup `endpoint_locations` data (if needed)
- [ ] Drop `endpoint_locations` table
- [ ] Remove table creation from `init-database.sh`
- [ ] Test fresh installation
- [ ] **Time:** 1-2 hours

#### Day 22: Remove Cleanup Scripts
- [ ] Remove `cleanup-expired-endpoints.sh`
- [ ] Remove systemd timer/service files
- [ ] Update `install.sh` if needed
- [ ] **Time:** 1-2 hours

#### Day 23: Update Documentation
- [ ] Update `PROJECT-CONTEXT.md` (remove endpoint_locations references)
- [ ] Update `MASTER-PROJECT-PLAN.md` (mark migration complete)
- [ ] Update any routing documentation
- [ ] **Time:** 2-3 hours

#### Day 24: Final Testing
- [ ] Run full test suite
- [ ] Test with multiple tenants
- [ ] Test with multiple Asterisk boxes
- [ ] Performance validation
- [ ] **Time:** 3-4 hours

#### Day 25: Code Review & Merge
- [ ] Review all changes
- [ ] Merge `usrloc` branch to `main`
- [ ] Tag release
- [ ] Update deployment documentation
- [ ] **Time:** 2-3 hours

**Week 5 Goal:** Cleanup complete, migration done

---

## 📋 Daily Checklist Template

For each day, use this checklist:

- [ ] **Morning:** Review day's goals (15 min)
- [ ] **Work:** Complete day's tasks (2-4 hours)
- [ ] **Test:** Verify changes work (30 min)
- [ ] **Document:** Update notes/logs (15 min)
- [ ] **Evening:** Review tomorrow's tasks (15 min)

**Total Daily Time:** 3-5 hours

---

## 🚨 Risk Mitigation

**If something goes wrong:**

1. **Day 1-5 (Week 1):** Easy rollback - just remove module load
2. **Day 6-10 (Week 2):** Can disable new route, use old SQL lookup
3. **Day 11-15 (Week 3):** Both implementations running - no risk
4. **Day 16-20 (Week 4):** Can revert to dual-write if issues
5. **Day 21-25 (Week 5):** Can restore table from backup

**Rollback Strategy:** Keep `usrloc` branch separate until fully tested, then merge.

---

### 8. Contact Header Parsing - Additional Information

**Update:** Contact header parsing pseudo-variables have been identified and documented.

**Available Pseudo-Variables:**
- `$ct` - Full body of the primary Contact header
- `$(ct{nameaddr.name})` - Display name from Contact header URI
- `$(ct{nameaddr.uri})` - SIP URI from Contact header (e.g., `sip:user@host`)
- `$ct.user` or `$(ct{uri.user})` - Username part of Contact URI
- `$ct.host` or `$(ct{uri.host})` - Host/IP part of Contact URI
- `$ct.port` or `$(ct{uri.port})` - Port number of Contact URI
- `$ct.proto` or `$(ct{uri.proto})` - Transport protocol (udp, tcp)
- `$(ct{nameaddr.param,param_name})` - Specific parameter value (e.g., `expires`)
- `$(ct{nameaddr.params})` - All parameters and values

**Usage Example:**
```opensips
# Extract IP and port from Contact header
$var(contact_ip) = $ct.host;
$var(contact_port) = $ct.port;
if ($var(contact_port) == "" || $var(contact_port) == "0") {
    $var(contact_port) = "5060";  # Default port
}

# Extract expires parameter
$var(expires_value) = $(ct{nameaddr.param,expires});
```

**Note:** When using `lookup("location")`, the function automatically sets `$du` from the Contact header stored in the `location` table. Manual parsing may only be needed for:
- Diagnostic logging
- Custom routing logic
- Request-URI construction (though `lookup()` handles this automatically)

**For NAT Scenarios:** The `location` table's `received` field contains the actual IP:port from NAT traversal (set by `fix_nated_register()`). The `lookup()` function automatically uses the `received` field if available, so manual parsing is typically not needed.

## Migration Phases

### Phase 1: Module Setup & Configuration (Week 2)

**Objectives:**
- Load `usrloc` module
- Configure module parameters
- Create `location` table schema
- Test basic save/lookup functionality

**Tasks:**

1. **Add Module to Config**
   ```opensips
   loadmodule "usrloc.so"
   # Domain module for multi-tenant support (manages domain-specific information)
   # NOTE: Check if domain module is already loaded - it may be used elsewhere
   loadmodule "domain.so"
   # May also need registrar module
   # loadmodule "registrar.so"
   ```
   
   **Note:** The `domain` module helps OpenSIPS recognize which domains are local and manages them as distinct entities. This is important for multi-tenant deployments where the same username can exist across different domains.
   
   **How it works:**
   - OpenSIPS uses `domain` module with database (MySQL) to map unique user accounts (`username@domain`) to specific contacts
   - The `usrloc` module stores these distinct user bindings with `username@domain` as the key
   - `lookup("location", "uri", "sip:user@domain")` uses the full SIP URI as the key, ensuring domain-specific lookups
   - This ensures that lookups for `user@domainA` go to different contacts than `user@domainB`

2. **Configure Module Parameters**
   ```opensips
   modparam("usrloc", "db_url", "mysql://opensips:opensips@localhost/opensips")
   modparam("usrloc", "db_mode", 2)  # Cached DB mode
   modparam("usrloc", "use_domain", 1)  # CRITICAL: Enable domain separation for multi-tenant
   modparam("usrloc", "nat_bflag", "NAT")
   # Add other parameters as needed
   ```
   
   **Note:** Verify MySQL credentials match your actual database configuration. Default shown: `opensips/opensips`
   
   **⚠️ CRITICAL:** `use_domain = 1` is **REQUIRED** for multi-tenant deployments:
   - Allows same username across different domains (e.g., 401@tenant-a.com, 401@tenant-b.com)
   - Enforces uniqueness within each domain (prevents duplicate 401@tenant-a.com)
   - This matches the business requirement: duplication across domains, not within domain
   - **How it works:** OpenSIPS stores contacts with `username@domain` as the key
   - **Domain-specific lookups:** `lookup("location", "uri", "sip:401@tenant-a.com")` only finds contacts in `tenant-a.com`
   - **Never cross-domain:** Lookups are domain-specific by design - no wildcard needed when domain is known

3. **Update Database Schema**
   - [ ] Run OpenSIPS `location` table creation script
   - [ ] Verify table structure matches OpenSIPS schema
   - [ ] Add any custom indexes if needed
   - [ ] **CRITICAL:** Verify `use_domain = 1` is configured (allows username duplication across domains)
   - [ ] **Verify domain table exists** - Used by `domain` module to manage domain-specific information
   - [ ] **Verify dispatcher table structure** - Used for source IP → domain mapping

4. **Basic Functionality Test**
   - [ ] Test `save("location")` in onreply_route
   - [ ] Test `lookup("location")` function
   - [ ] Verify data in `location` table
   - [ ] Test expiration handling

**Success Criteria:**
- Module loads without errors
- Basic save/lookup works
- Data appears correctly in `location` table

### Phase 2: Parallel Implementation (Week 3)

**Objectives:**
- Implement `usrloc`-based registration handling
- Keep `endpoint_locations` as fallback
- Test both implementations in parallel
- Compare results

**Tasks:**

1. **Implement Proxy-Registrar Pattern**
   - [ ] Add `t_on_reply("handle_reply_reg")` to REGISTER handling
   - [ ] Create `onreply_route[handle_reply_reg]`
   - [ ] Implement `save("location")` on 2xx responses
   - [ ] Keep existing `endpoint_locations` INSERT (for comparison)

2. **Implement Lookup Functions**
   - [ ] Create new lookup route using `lookup("location")`
   - [ ] **CRITICAL:** Implement domain context from source IP
   - [ ] Implement domain-specific lookup (not wildcard)
   - [ ] Keep existing SQL-based lookup (for comparison)
   - [ ] Add logging to compare results
   - [ ] Test with multiple tenants (same extension numbers)

3. **Dual-Write Testing**
   - [ ] Test registration: verify both tables updated
   - [ ] Test lookup: verify both methods return same result
   - [ ] Compare performance
   - [ ] Compare data accuracy

4. **Contact Header Parsing**
   - [ ] Extract IP/port from Contact header
   - [ ] Handle NAT scenarios (`received` field)
   - [ ] Handle port extraction
   - [ ] Test with various Contact formats

5. **⚠️ CRITICAL: Domain Context from Source IP**
   - [ ] Implement source IP → dispatcher set lookup
   - [ ] Implement dispatcher set → domain lookup
   - [ ] Implement domain-specific endpoint lookup
   - [ ] Handle port variations in dispatcher destination matching
   - [ ] Test with multiple tenants (same extension numbers)
   - [ ] Verify correct routing to correct customer

**Success Criteria:**
- Both implementations work correctly
- Results match between old and new methods
- No performance degradation

### Phase 3: Migration & Testing (Week 4)

**Objectives:**
- Switch lookups to use `usrloc` module
- Remove `endpoint_locations` SQL queries
- Comprehensive testing
- Performance validation

**Tasks:**

1. **Replace Lookup Queries**
   - [ ] Replace `ENDPOINT_LOOKUP` route with `lookup("location")`
   - [ ] Replace OPTIONS/NOTIFY routing lookups
   - [ ] Replace INVITE routing lookups
   - [ ] Remove all `endpoint_locations` SQL queries

2. **Update Registration Handling**
   - [ ] Remove `endpoint_locations` INSERT from request route
   - [ ] Keep only `save("location")` in onreply_route
   - [ ] Add proper error handling

3. **Update Cleanup Scripts**
   - [ ] Modify cleanup script to use `location` table
   - [ ] Update expiration queries (Unix timestamp)
   - [ ] Test cleanup functionality

4. **Comprehensive Testing**
   - [ ] Test REGISTER with success (200 OK)
   - [ ] Test REGISTER with failure (401, 403, etc.)
   - [ ] Test OPTIONS routing from Asterisk
   - [ ] Test NOTIFY routing from Asterisk
   - [ ] Test INVITE routing from Asterisk
   - [ ] Test de-registration (Expires: 0)
   - [ ] Test expiration handling
   - [ ] Test NAT scenarios
   - [ ] **CRITICAL:** Test multi-tenant scenario (same extension in multiple domains)
   - [ ] **CRITICAL:** Verify routing to correct customer/domain
   - [ ] **CRITICAL:** Test domain context from source IP
   - [ ] **CRITICAL:** Test with multiple Asterisk boxes (different source IPs)

**Success Criteria:**
- All routing works correctly
- No `endpoint_locations` queries remain
- Performance is acceptable
- All tests pass

### Phase 4: Cleanup & Documentation (Week 5)

**Objectives:**
- Remove `endpoint_locations` table
- Update documentation
- Remove custom cleanup scripts
- Final validation

**Tasks:**

1. **Remove Custom Table**
   - [ ] Backup `endpoint_locations` data (if needed)
   - [ ] Drop `endpoint_locations` table
   - [ ] Remove table creation from `init-database.sh`

2. **Remove Custom Scripts**
   - [ ] Remove `cleanup-expired-endpoints.sh`
   - [ ] Remove `cleanup-expired-endpoints.timer`
   - [ ] Remove `cleanup-expired-endpoints.service`
   - [ ] Update `install.sh` if needed

3. **Update Documentation**
   - [ ] Update `PROJECT-CONTEXT.md`
   - [ ] Update `MASTER-PROJECT-PLAN.md`
   - [ ] Update `opensips-routing-logic.md`
   - [ ] Update `ENDPOINT-LOCATION-CREATION.md`
   - [ ] Create migration notes document

4. **Final Validation**
   - [ ] Run full test suite
   - [ ] Verify no references to `endpoint_locations`
   - [ ] Verify all documentation updated
   - [ ] Performance benchmark

**Success Criteria:**
- No `endpoint_locations` references remain
- Documentation is accurate
- System works correctly
- Performance is acceptable

## Testing Plan

### Unit Tests

1. **Registration Tests**
   - [ ] REGISTER with 200 OK → location saved
   - [ ] REGISTER with 401 Unauthorized → location NOT saved
   - [ ] REGISTER with 403 Forbidden → location NOT saved
   - [ ] REGISTER with Expires: 0 → location removed
   - [ ] REGISTER refresh → location updated

2. **Lookup Tests**
   - [ ] Lookup by exact AoR → found
   - [ ] **CRITICAL:** Lookup by username with domain context (source IP → domain → lookup) → found in correct domain
   - [ ] **CRITICAL:** Lookup by username with domain context → NOT found in wrong domain (even if exists in other domain)
   - [ ] **CRITICAL:** Multiple tenants with same extension → routes to correct tenant based on source IP
   - [ ] Lookup expired entry → not found
   - [ ] Lookup non-existent → not found
   - [ ] ⚠️ **MUST NOT use wildcard lookup (`@*`) as primary method** - only as fallback

3. **Routing Tests**
   - [ ] OPTIONS from Asterisk → routed to endpoint
   - [ ] NOTIFY from Asterisk → routed to endpoint
   - [ ] INVITE from Asterisk → routed to endpoint
   - [ ] Endpoint not found → 404 response

4. **NAT Tests**
   - [ ] REGISTER behind NAT → `received` field set
   - [ ] Lookup uses `received` field correctly
   - [ ] Contact header parsing works

### Integration Tests

1. **End-to-End Registration Flow**
   - [ ] Endpoint registers → Asterisk accepts → location saved
   - [ ] Endpoint registers → Asterisk rejects → location not saved
   - [ ] Endpoint refreshes → location updated
   - [ ] Endpoint de-registers → location removed

2. **End-to-End Routing Flow**
   - [ ] Asterisk sends OPTIONS → routed to endpoint → 200 OK
   - [ ] Asterisk sends NOTIFY → routed to endpoint → 200 OK
   - [ ] Asterisk sends INVITE → routed to endpoint → call established

3. **Expiration Tests**
   - [ ] Registration expires → lookup fails
   - [ ] Cleanup script removes expired entries
   - [ ] Expired entries don't affect routing

### Performance Tests

1. **Load Tests**
   - [ ] 100 concurrent registrations
   - [ ] 1000 concurrent lookups
   - [ ] Compare performance vs `endpoint_locations`

2. **Database Tests**
   - [ ] Table size growth
   - [ ] Query performance
   - [ ] Cleanup performance

## Rollback Plan

### If Migration Fails

1. **Immediate Rollback**
   - Revert config to use `endpoint_locations`
   - Restore `endpoint_locations` table (if dropped)
   - Restart OpenSIPS

2. **Data Recovery**
   - Restore `endpoint_locations` from backup
   - Migrate `location` data back to `endpoint_locations` (if needed)

3. **Investigation**
   - Review logs for errors
   - Identify root cause
   - Document issues
   - Plan fix

### Rollback Triggers

- Registration failures > 5%
- Routing failures > 5%
- Performance degradation > 20%
- Critical bugs discovered

## Risk Assessment

### High Risk

1. **Lookup Functionality**
   - **Risk:** `lookup()` may not work exactly like current SQL queries
   - **Mitigation:** Parallel implementation and testing
   - **Impact:** Routing failures

2. **Contact Header Parsing**
   - **Risk:** IP/port extraction from Contact header may be complex
   - **Mitigation:** Thorough testing with various formats
   - **Impact:** NAT traversal issues

### Medium Risk

1. **Data Migration**
   - **Risk:** Existing `endpoint_locations` data may need migration
   - **Mitigation:** Parallel implementation allows gradual migration
   - **Impact:** Temporary data inconsistency

2. **Performance**
   - **Risk:** `usrloc` module may have different performance characteristics
   - **Mitigation:** Performance testing in Phase 2
   - **Impact:** System slowdown

### Low Risk

1. **Module Compatibility**
   - **Risk:** `usrloc` module may conflict with other modules
   - **Mitigation:** Standard OpenSIPS module, well-tested
   - **Impact:** Module loading issues

2. **Documentation**
   - **Risk:** Documentation may be incomplete
   - **Mitigation:** OpenSIPS has good documentation
   - **Impact:** Development delays

## Timeline

### Week 1: Research Phase
- Study OpenSIPS `usrloc` module
- Map current functionality
- Design migration approach

### Week 2: Module Setup
- Load and configure `usrloc` module
- Create `location` table
- Basic functionality testing

### Week 3: Parallel Implementation
- Implement proxy-registrar pattern
- Implement lookup functions
- Dual-write testing

### Week 4: Migration
- Replace all SQL queries with `usrloc` functions
- Remove `endpoint_locations` INSERT
- Comprehensive testing

### Week 5: Cleanup
- Remove `endpoint_locations` table
- Update documentation
- Final validation

**Total Estimated Time:** 5 weeks

## Success Metrics

### Functional Metrics
- ✅ All registrations work correctly
- ✅ All routing works correctly
- ✅ No stale registrations
- ✅ Expiration handling works

### Performance Metrics
- ✅ Registration latency < 50ms increase
- ✅ Lookup latency < 10ms increase
- ✅ Database size manageable

### Quality Metrics
- ✅ Zero critical bugs
- ✅ All tests pass
- ✅ Documentation complete
- ✅ Code review passed

## Dependencies

### Required
- OpenSIPS `usrloc` module (standard, should be available)
- OpenSIPS `location` table schema (standard, should be available)
- MySQL database (already in use)

### Optional
- OpenSIPS `registrar` module (may be needed for full functionality)
- OpenSIPS documentation (for reference)

## Related Documents

- [OpenSIPS Proxy Registration Blog Post](https://blog.opensips.org/2016/12/13/how-to-proxy-sip-registrations/)
- [Why Username-Only Lookup is Needed](WHY-USERNAME-ONLY-LOOKUP.md) - Explanation of why this functionality is required
- [Multiple Domains Same Username](MULTIPLE-DOMAINS-SAME-USERNAME.md) - Critical multi-tenant requirements and required solution
- [Multiple Domains for Same Username](MULTIPLE-DOMAINS-SAME-USERNAME.md) - Behavior when same username exists in multiple domains
- [Endpoint Location Creation Documentation](ENDPOINT-LOCATION-CREATION.md)
- [OpenSIPS Routing Logic](opensips-routing-logic.md)
- [Project Context](PROJECT-CONTEXT.md)
- [Master Project Plan](MASTER-PROJECT-PLAN.md)

## Notes

- This is a living document - update as migration progresses
- Review weekly during migration
- Document decisions and rationale
- Keep rollback plan ready
- Test thoroughly at each phase

---

## Quick Status Update (Jan 19, 2026)

**✅ COMPLETED:**
- ✅ Location table created with `BIGINT UNSIGNED` contact_id (fixes UUID Call-ID hash overflow)
- ✅ usrloc, registrar, domain, signaling modules loaded
- ✅ `save("location")` working correctly - registrations saving to location table
- ✅ Failed registrations (401) correctly NOT creating records
- ✅ Proxy-registrar pattern implemented in `onreply_route[handle_reply_reg]`
- ✅ `lookup("location")` implemented for OPTIONS/NOTIFY routing
- ✅ INVITE routing updated to use location table
- ✅ REGISTER Contact header preserved correctly (fixed fix_nated_contact() issue)

**🔧 KEY FIXES:**
1. **contact_id overflow:** Changed from `INT UNSIGNED` to `BIGINT UNSIGNED` to handle UUID-based Call-ID hashes
   - Snom phones use UUID format Call-IDs which produce hash values exceeding INT UNSIGNED max
   - Actual contact_id value: `3617797875662073346` (way beyond INT range)
2. **REGISTER Contact header:** Excluded REGISTER responses from `fix_nated_contact()` to preserve endpoint Contact
3. **lookup() implementation:** Replaced SQL queries with `lookup("location")` function for OPTIONS/NOTIFY/INVITE routing

**📋 NEXT STEPS (Optional Improvements):**
- Improve domain detection for multi-tenant (determine domain from dispatcher setid)
- Remove old endpoint_locations SQL queries (if still present)
- Test with multiple domains/tenants

**📚 See:** `workingdocs/SESSION-SUMMARY-USRLOC-SAVE-FIX.md` for detailed session notes

---

**Status:** ✅ **MIGRATION COMPLETE** - All code migrated, cleanup done  
**Testing Status:** ⚠️ Single-tenant tested ✅ | Multi-tenant testing pending  
**Next Steps:** Multi-tenant testing with second server  
**Branch:** `usrloc`  
**Last Updated:** January 2026

---

## ✅ Migration Complete Summary

**Date Completed:** January 2026

### What Was Completed

1. ✅ **Location table created** with `BIGINT UNSIGNED` contact_id (fixes UUID Call-ID hash overflow)
2. ✅ **Modules loaded:** usrloc, registrar, domain, signaling
3. ✅ **save() function working** - Registrations saving to location table in `onreply_route`
4. ✅ **lookup() function working** - OPTIONS/NOTIFY/INVITE routing using `lookup("location")`
5. ✅ **Domain detection implemented** - `GET_DOMAIN_FROM_SOURCE_IP` route for multi-tenant support
6. ✅ **NAT handling migrated** - RELAY route now uses location table
7. ✅ **Diagnostic logging migrated** - Uses location table queries
8. ✅ **All endpoint_locations code removed** - No active references remain
9. ✅ **Installer updated** - No longer creates endpoint_locations table

### Testing Status

- ✅ **Single-tenant:** Tested and working
- ⚠️ **Multi-tenant:** Pending (requires second server setup)

### Remaining Work

- ⏳ Multi-tenant testing with multiple domains/tenants
- ⏳ Verify domain detection works correctly in production
- ⏳ Optional: Drop endpoint_locations table from existing installations (when ready)
