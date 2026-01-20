# Session Summary: usrloc save() Fix - Contact ID Overflow Issue

**Date:** January 19, 2026  
**Status:** ✅ RESOLVED  
**Key Achievement:** Successfully fixed `save("location")` function - registrations now saving to location table

## Problem Statement

`save("location")` was returning `TRUE` but no data was appearing in the `location` table. Error logs showed:
```
CRITICAL:db_mysql:wrapper_single_mysql_stmt_execute: driver error (1264): Out of range value for column 'contact_id' at row 1
ERROR:usrloc:db_insert_ucontact: inserting contact in db failed
```

## Root Cause

**UUID-based Call-IDs causing hash overflow:**
- OpenSIPS computes `contact_id` from a hash that includes the Call-ID
- Snom phones use UUID format for Call-ID (e.g., `60f86b69b228-zd4egelytysk`)
- The hash computation produced values exceeding `INT UNSIGNED` maximum (4,294,967,295)
- Example: Actual `contact_id` value was `3617797875662073346` - way beyond INT UNSIGNED range

## Solution

Changed `contact_id` column type from `INT UNSIGNED` to `BIGINT UNSIGNED`:

**Before:**
```sql
contact_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY NOT NULL
```

**After:**
```sql
contact_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY NOT NULL
```

**Range comparison:**
- `INT UNSIGNED`: 0 to 4,294,967,295
- `BIGINT UNSIGNED`: 0 to 18,446,744,073,709,551,615 ✅

## Files Modified

1. **`scripts/create-location-table.sql`**
   - Changed `contact_id` from `INT UNSIGNED` to `BIGINT UNSIGNED`
   - Updated for future table creation

2. **Database (on server):**
   - Ran: `ALTER TABLE location MODIFY COLUMN contact_id BIGINT UNSIGNED AUTO_INCREMENT NOT NULL;`

3. **`config/opensips.cfg.template`**
   - Added `regen_broken_contactid` parameter (for future migrations)
   - Fixed diagnostic logging (removed invalid `[len]` syntax)
   - Switched back to `db_mode=2` (cached DB) after debugging

## Key Learnings

### 1. OpenSIPS contact_id Computation
- OpenSIPS **computes** `contact_id` from a hash (doesn't use AUTO_INCREMENT)
- Hash includes: Call-ID, Contact URI, username, domain, etc.
- UUID-based Call-IDs can produce very large hash values
- Must use `BIGINT UNSIGNED` to accommodate these values

### 2. Proxy-Registrar Pattern
- `save()` extracts Contact from the **200 OK REPLY**, not the request
- Must be called in `onreply_route` after successful 2xx response
- If reply Contact header is `<null>`, `save()` cannot work (we exit early)
- No flags needed for `save()` in `onreply_route` (transaction handles reply)

### 3. Debugging Process
- Used `db_mode=1` (write-through) to see errors immediately
- Diagnostic logging showed Contact header values
- MySQL query logging would show exact INSERT statements (if needed)
- Error appeared immediately with `db_mode=1` vs delayed with `db_mode=2`

### 4. Common Issues Encountered
- ❌ `db_update_period` parameter doesn't exist → Use `timer_interval`
- ❌ `save()` function not found → Need `loadmodule "registrar.so"`
- ❌ `registrar` module dependency → Need `loadmodule "signaling.so"`
- ❌ Invalid `[len]` syntax → OpenSIPS doesn't support this
- ❌ `r` flag not recognized → Not needed in `onreply_route`
- ✅ `contact_id` overflow → Fixed with `BIGINT UNSIGNED`

## Current Status

✅ **Working:**
- `save("location")` successfully saves registrations to location table
- Failed registrations (401) do NOT create records (correct behavior)
- Contact information correctly stored with domain separation
- UUID-based Call-IDs handled correctly

✅ **Verified:**
- Data appears in location table after successful REGISTER
- `contact_id` values are valid (within BIGINT UNSIGNED range)
- All required fields populated (username, domain, contact, expires, etc.)

## Next Steps

1. **Implement `lookup()` function** (usrloc-8)
   - Replace SQL queries in OPTIONS/NOTIFY routing with `lookup("location")`
   - Test domain-specific lookups
   - Verify multi-contact handling

2. **Remove old endpoint_locations code**
   - Once `lookup()` is working, remove SQL queries
   - Clean up old table (if no longer needed)

3. **Performance testing**
   - Verify `db_mode=2` (cached DB) performance
   - Monitor `timer_interval` flush behavior
   - Check memory usage

## Configuration Snippets

### Current usrloc Module Parameters
```opensips
modparam("usrloc", "db_url", "mysql://opensips:your-password@localhost/opensips")
modparam("usrloc", "db_mode", 2)  # Cached DB mode
modparam("usrloc", "use_domain", 1)  # Domain-aware (required for multi-tenant)
modparam("usrloc", "nat_bflag", "NAT")
modparam("usrloc", "timer_interval", 10)  # Flush every 10 seconds
modparam("usrloc", "regen_broken_contactid", 1)  # Fix broken contact_ids
```

### Current save() Implementation
```opensips
onreply_route[handle_reply_reg] {
    if (is_method("REGISTER")) {
        if (t_check_status("2[0-9][0-9]")) {
            # Exit early if reply Contact is missing
            if ($hdr(Contact) == "") {
                xlog("REGISTER: ERROR: Reply Contact header is empty/null - save() cannot work!\n");
                exit;
            }
            
            # Save location (extracts Contact from reply)
            if (save("location")) {
                xlog("REGISTER: Successfully saved location\n");
            }
        }
    }
    exit;
}
```

## Database Schema

**Location Table (Fixed):**
```sql
CREATE TABLE location (
    contact_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY NOT NULL,  -- FIXED: Was INT UNSIGNED
    username CHAR(64) DEFAULT '' NOT NULL,
    domain CHAR(64) DEFAULT NULL,
    contact TEXT NOT NULL,
    received CHAR(255) DEFAULT NULL,
    path CHAR(255) DEFAULT NULL,
    expires INT NOT NULL,
    q FLOAT(10,2) DEFAULT 1.0 NOT NULL,
    callid CHAR(255) NOT NULL DEFAULT 'Default-Call-ID',
    cseq INT DEFAULT 13 NOT NULL,
    last_modified DATETIME DEFAULT '1900-01-01 00:00:01' NOT NULL,
    flags INT DEFAULT 0 NOT NULL,
    cflags CHAR(255) DEFAULT NULL,
    user_agent CHAR(255) DEFAULT '' NOT NULL,
    socket CHAR(64) DEFAULT NULL,
    methods INT DEFAULT NULL,
    sip_instance CHAR(255) DEFAULT NULL,
    kv_store TEXT DEFAULT NULL,
    attr CHAR(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

## Test Results

**Successful Registration:**
```sql
MariaDB [opensips]> select * from location;
+---------------------+----------+------------------------+------------------------------+----------+------+------------+------+---------------------------+------+---------------------+-------+--------+----------------------+------------------+---------+-------------------------------------------------+----------+------+
| contact_id          | username | domain                 | contact                      | received | path | expires    | q    | callid                    | cseq | last_modified       | flags | cflags | user_agent           | socket           | methods | sip_instance                                    | kv_store | attr |
+---------------------+----------+------------------------+------------------------------+----------+------+------------+------+---------------------------+------+---------------------+-------+--------+----------------------+------------------+---------+-------------------------------------------------+----------+------+
| 3617797875662073346 | 1000     | pjsipsbc.vcloudpbx.com | sip:1000@192.168.1.138:50368 | NULL     | NULL | 1768881030 | 1.00 | 60f86b69b228-zd4egelytysk | 1327 | 2026-01-19 21:50:30 |     0 |        | snomD717/10.1.198.19 | udp:0.0.0.0:5060 |    7999 | <urn:uuid:daf7c982-9054-43d7-8ce9-000413BE48C0> | NULL     | NULL |
+---------------------+----------+------------------------+------------------------------+----------+------+------------+------+---------------------------+------+---------------------+-------+--------+----------------------+------------------+---------+-------------------------------------------------+----------+------+
```

**Key Observations:**
- `contact_id`: `3617797875662073346` (exceeds INT UNSIGNED max of 4,294,967,295) ✅
- `username`: `1000` ✅
- `domain`: `pjsipsbc.vcloudpbx.com` ✅
- `contact`: `sip:1000@192.168.1.138:50368` ✅
- `expires`: Unix timestamp ✅
- `callid`: UUID format ✅
- `sip_instance`: UUID format ✅

## References

- OpenSIPS 3.6.3 usrloc module documentation
- OpenSIPS registrar module documentation
- MySQL/MariaDB BIGINT UNSIGNED range: 0 to 18,446,744,073,709,551,615
- UUID format: 128-bit identifier (can produce large hash values)
