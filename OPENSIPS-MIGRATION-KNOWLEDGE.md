# OpenSIPS Migration Knowledge Base

This document captures all learnings from the Kamailio to OpenSIPS migration, including specific errors encountered, solutions, and critical differences. Use this as a reference for future OpenSIPS work.

## Table of Contents

1. [Critical Module Loading Order](#critical-module-loading-order)
2. [Database Schema Requirements](#database-schema-requirements)
3. [Module Parameter Differences](#module-parameter-differences)
4. [Function Syntax Differences](#function-syntax-differences)
5. [Pseudo-Variable Differences](#pseudo-variable-differences)
6. [Common Errors and Solutions](#common-errors-and-solutions)
7. [Configuration Checklist](#configuration-checklist)

---


## Database Schema Requirements

### OpenSIPS 3.6 Dispatcher Table (Version 9)

The dispatcher table schema is **strictly defined** and must match exactly:

```sql
CREATE TABLE dispatcher (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    setid INTEGER DEFAULT 0 NOT NULL,
    destination TEXT DEFAULT '' NOT NULL,
    socket TEXT,
    state INTEGER DEFAULT 0 NOT NULL,
    probe_mode INTEGER DEFAULT 0 NOT NULL,
    weight TEXT DEFAULT '1' NOT NULL,      -- Note: TEXT, not INTEGER
    priority INTEGER DEFAULT 0 NOT NULL,
    attrs TEXT,
    description TEXT
);
```

**Critical Points:**
- Column order matters (id, setid, destination, socket, state, probe_mode, weight, priority, attrs, description)
- `weight` is **TEXT** with default `'1'`, NOT INTEGER
- All NOT NULL columns must have defaults
- Version table must have entry: `INSERT OR REPLACE INTO version (table_name, table_version) VALUES ('dispatcher', 9);`

**Common Mistakes:**
- Using `CREATE TABLE IF NOT EXISTS` with wrong schema - it won't update existing tables
- Solution: Use `DROP TABLE IF EXISTS` then `CREATE TABLE` to ensure correct schema

---

## Module Parameter Differences

### Dispatcher Module

| Parameter | Kamailio | OpenSIPS 3.6 | Notes |
|-----------|----------|--------------|-------|
| Ping reply codes | `ds_ping_reply_codes` | `options_reply_codes` | Different name |
| Inactive threshold | `ds_inactive_threshold` | ❌ **Does not exist** | Removed in OpenSIPS |
| Database URL | `db_url` | `db_url` | Same |
| Ping method | `ds_ping_method` | `ds_ping_method` | Same |
| Ping interval | `ds_ping_interval` | `ds_ping_interval` | Same |

**Example:**
```opensips
# OpenSIPS 3.6
modparam("dispatcher", "options_reply_codes", "200")  # ✅ Correct
modparam("dispatcher", "ds_ping_reply_codes", "200") # ❌ Wrong parameter name
```

### Transaction Module (TM)

| Parameter | Kamailio | OpenSIPS 3.6 | Notes |
|-----------|----------|--------------|-------|
| Final response timer | `fr_timer` | ❌ **Not a modparam** | Handled differently |
| INVITE final response timer | `fr_inv_timer` | ❌ **Not a modparam** | Handled differently |
| Retransmission timer 1 | `retr_timer1` | `T1_timer` | Different name |
| Retransmission timer 2 | `retr_timer2` | `T2_timer` | Different name |
| Restart FR on reply | `restart_fr_on_each_reply` | `restart_fr_on_each_reply` | Same |

**Example:**
```opensips
# OpenSIPS 3.6
modparam("tm", "T1_timer", 2000)      # ✅ Correct
modparam("tm", "T2_timer", 8000)      # ✅ Correct
modparam("tm", "restart_fr_on_each_reply", 1)  # ✅ Correct
modparam("tm", "retr_timer1", 2000)   # ❌ Wrong parameter name
modparam("tm", "fr_timer", 30)       # ❌ Not a modparam
```

---

## Function Syntax Differences

### Stateless Reply Functions

**Kamailio:**
```kamailio
sl_send_reply("483", "Too Many Hops");  # String status code
sl_reply_error();                        # Built-in function
```

**OpenSIPS 3.6:**
```opensips
sl_send_reply(483, "Too Many Hops");    # Integer status code ✅
sl_reply_error();                        # Requires sl.so module ✅
```

**Key Differences:**
- Status codes must be **integers**, not strings
- `sl.so` module must be loaded for `sl_send_reply()` and `sl_reply_error()`

### Max-Forwards Processing

**Both:**
```opensips
if (!mf_process_maxfwd_header(10)) {  # Integer parameter ✅
    sl_send_reply(483, "Too Many Hops");
}
```

**Common Mistake:**
```opensips
mf_process_maxfwd_header("10")  # ❌ String - will fail
```

### Dispatcher Selection

**Both:**
```opensips
if (!ds_select_dst($var(setid), 4)) {  # Integer flag ✅
    sl_send_reply(503, "Service Unavailable");
}
```

**Common Mistake:**
```opensips
ds_select_dst($var(setid), "4")  # ❌ String flag - will fail
```

### In-Dialog Check

**Kamailio:**
```kamailio
if (has_totag()) {  # Built-in function
```

**OpenSIPS 3.6:**
```opensips
if (has_totag()) {  # Requires sipmsgops.so module ✅
```

**Note:** `has_totag()` requires `sipmsgops.so` module to be loaded.

---

## Pseudo-Variable Differences

### To Tag

**Kamailio:**
```kamailio
$tt  # To tag pseudo-variable
```

**OpenSIPS 3.6:**
```opensips
$tt        # ✅ Works in most contexts
$to_tag    # ❌ Does NOT work in xlog format strings
```

**In xlog calls:**
```opensips
# ✅ Correct
xlog("To-tag=$tt\n");

# ❌ Wrong - will fail with "unknown script var"
xlog("To-tag=$to_tag\n");
```

### Domain Extraction

**Kamailio:**
```kamailio
$tD  # To header domain
$rD  # Request-URI domain
```

**OpenSIPS 3.6:**
```opensips
$(tu{uri.domain})  # ✅ To header domain (use transformation)
$rd                # ✅ Request-URI domain (direct)
```

**Common Mistakes:**
```opensips
$tD  # ❌ Does not exist
$rD  # ❌ Does not exist - use $rd instead
```

### Null Checks

**Kamailio:**
```kamailio
if ($var(value) == $null) {  # ✅ Works
```

**OpenSIPS 3.6:**
```opensips
if ($var(value) == "") {     # ✅ Use empty string
if ($var(value) == $null) {  # ❌ $null not supported
```

---

## Common Errors and Solutions

### Error: "no modules to load!"

**Cause:** Missing `.so` extension in `loadmodule` statements

**Solution:**
```opensips
# ✅ Correct
loadmodule "sl.so"
loadmodule "tm.so"

# ❌ Wrong
loadmodule "sl"
loadmodule "tm"
```

---

### Error: "Parameter <ds_ping_reply_codes> not found in module <dispatcher>"

**Cause:** Wrong parameter name in OpenSIPS 3.6

**Solution:**
```opensips
# ✅ Correct
modparam("dispatcher", "options_reply_codes", "200")

# ❌ Wrong
modparam("dispatcher", "ds_ping_reply_codes", "200")
```

---

### Error: "Parameter <retr_timer1> not found in module <tm>"

**Cause:** Wrong parameter name in OpenSIPS 3.6

**Solution:**
```opensips
# ✅ Correct
modparam("tm", "T1_timer", 2000)
modparam("tm", "T2_timer", 8000)

# ❌ Wrong
modparam("tm", "retr_timer1", 2000)
modparam("tm", "retr_timer2", 8000)
```

---

### Error: "unknown command <sl_send_reply>, missing loadmodule?"

**Cause:** `sl.so` module not loaded

**Solution:**
```opensips
loadmodule "sl.so"  # Must be loaded before use
```

---

### Error: "unknown command <has_totag>, missing loadmodule?"

**Cause:** `sipmsgops.so` module not loaded

**Solution:**
```opensips
loadmodule "sipmsgops.so"  # Required for has_totag()
```

---

### Error: "unknown script variable $tD"

**Cause:** `$tD` doesn't exist in OpenSIPS

**Solution:**
```opensips
# ✅ Correct
$(tu{uri.domain})  # To header domain

# ❌ Wrong
$tD
```

---

### Error: "unknown script variable $null"

**Cause:** `$null` not supported in OpenSIPS

**Solution:**
```opensips
# ✅ Correct
if ($var(value) == "") {

# ❌ Wrong
if ($var(value) == $null) {
```

---

### Error: "unknown script var $to_tag" in xlog

**Cause:** `$to_tag` doesn't work in xlog format strings

**Solution:**
```opensips
# ✅ Correct
xlog("To-tag=$tt\n");

# ❌ Wrong
xlog("To-tag=$to_tag\n");
```

---

### Error: "no transport protocol loaded"

**Cause:** Transport module not loaded

**Solution:**
```opensips
loadmodule "proto_udp.so"  # ✅ Correct module name
# NOT "udp.so"
```

---

### Error: "invalid version 4 for table dispatcher found, expected 9"

**Cause:** Version table has wrong version number

**Solution:**
```sql
INSERT OR REPLACE INTO version (table_name, table_version) VALUES ('dispatcher', 9);
```

---

### Error: "no such column: probe_mode"

**Cause:** Dispatcher table missing required columns

**Solution:** Drop and recreate table with correct schema (see Database Schema Requirements above)

---

### Error: "Param [1] expected to be an integer or variable" for mf_process_maxfwd_header

**Cause:** String parameter instead of integer

**Solution:**
```opensips
# ✅ Correct
mf_process_maxfwd_header(10)

# ❌ Wrong
mf_process_maxfwd_header("10")
```

---

### Error: "Param [1] expected to be an integer or variable" for sl_send_reply

**Cause:** String status code instead of integer

**Solution:**
```opensips
# ✅ Correct
sl_send_reply(483, "Too Many Hops")

# ❌ Wrong
sl_send_reply("483", "Too Many Hops")
```

---

### Error: "Param [2] expected to be an integer or variable" for ds_select_dst

**Cause:** String flag instead of integer

**Solution:**
```opensips
# ✅ Correct
ds_select_dst($var(setid), 4)

# ❌ Wrong
ds_select_dst($var(setid), "4")
```

---

### Error: "ERROR:dispatcher:mod_init: failed to load data from DB"

**Possible Causes:**
1. **Module load order** - `db_sqlite.so` must be loaded before `dispatcher.so`
2. **Wrong schema** - Table doesn't match OpenSIPS 3.6 version 9 requirements
3. **Wrong version** - Version table has incorrect version number
4. **Missing columns** - Table missing required columns (probe_mode, weight, etc.)

**Solutions:**
1. Fix module load order
2. Drop and recreate table with correct schema
3. Update version table: `INSERT OR REPLACE INTO version (table_name, table_version) VALUES ('dispatcher', 9);`
4. Verify all required columns exist with correct types

---

### Error: "syntax error" for failure_route

**Cause:** Missing route index

**Solution:**
```opensips
# ✅ Correct
failure_route[1] {
    # ...
}
t_on_failure("1");  # Must call before t_relay()

# ❌ Wrong
failure_route {
    # ...
}
```

---

### Error: "syntax error" for event_route[dispatcher:dst-up]

**Cause:** Colon in route name may cause parsing issues

**Solution:** Comment out or use alternative event handling:
```opensips
# Temporarily commented out - may need different syntax
# event_route[dispatcher:dst-up] {
#     xlog("Dispatcher destination up\n");
# }
```

---

### Error: sql_query() returns false for INSERT statements

**Cause:** `sql_query()` in OpenSIPS `sqlops` module returns `false` for INSERT/UPDATE/DELETE statements because they don't return rows. This is expected behavior, not an error.

**Solution:**
```opensips
# ✅ Correct - Execute INSERT without checking return value
$var(query) = "INSERT OR REPLACE INTO endpoint_locations ...";
sql_query($var(query), "$avp(result)");
xlog("Stored endpoint location: ...\n");

# ❌ Wrong - Treating false return as error
if (sql_query($var(query), "$avp(result)")) {
    xlog("Success\n");
} else {
    xlog("Failed\n");  # This will always execute for INSERT!
}
```

**Note:** For SELECT queries, `sql_query()` returns `true` if rows are found, `false` if no rows. For INSERT/UPDATE/DELETE, it always returns `false` (no rows returned), but the query still executes successfully.

**Database Connection:**
- Use 3 slashes for `sqlops` module: `sqlite:///path/to/db` (matches `dispatcher` module format)
- Both `sqlops` and `dispatcher` can use the same database file

---

### Error: SQL queries show literal variable names instead of values

**Cause:** OpenSIPS does not interpolate variables inside SQL query strings. Using `'$var(domain)'` in a query string will search for the literal string `$var(domain)`, not the variable's value.

**Solution:**
```opensips
# ✅ Correct - Use string concatenation to interpolate variables
$var(query) = "SELECT dispatcher_setid FROM sip_domains WHERE domain='" + $var(domain) + "' AND enabled=1";
if (sql_query($var(query), "$avp(domain_setid)")) {
    # ...
}

# ❌ Wrong - Variable not interpolated, searches for literal '$var(domain)'
$var(query) = "SELECT dispatcher_setid FROM sip_domains WHERE domain='$var(domain)' AND enabled=1";
```

**Note:** Always use string concatenation (`+` operator) to build SQL queries with variable values. This applies to all SQL queries (SELECT, INSERT, UPDATE, DELETE).

---

### Error: NOTIFY requests failing with null destination URI

**Problem:** NOTIFY requests from Asterisk to endpoints behind NAT fail because `$du` (destination URI) is `<null>`, causing `t_relay()` to fail. Logs show:
```
RELAY: Creating transaction for NOTIFY to <null>
```

**Root Cause:** 
- NOTIFY requests are in-dialog (have To-tag) and go through `route[WITHINDLG]` → `loose_route()` → `route[RELAY]`
- When NOTIFY has a private IP in Request-URI (e.g., `sip:40005@192.168.1.232:5060`), it needs to be routed to the endpoint's public NAT IP
- The NAT IP fix in `route[RELAY]` was only applied to ACK and BYE methods, not NOTIFY

**Solution:**
Include NOTIFY in the NAT IP fix in `route[RELAY]`:

```opensips
# ✅ Correct - Include NOTIFY with ACK and BYE
if (is_method("ACK|BYE|NOTIFY")) {
    # Check if Request-URI domain is a private IP address
    $var(check_ip) = $rd;
    route(CHECK_PRIVATE_IP);
    
    if ($var(is_private) == 1) {
        # Look up endpoint's NAT IP from database
        $var(msg_user) = $rU;
        if ($var(msg_user) != "") {
            $var(lookup_user) = $var(msg_user);
            $var(lookup_aor) = "";
            route(ENDPOINT_LOOKUP);
            
            if ($var(lookup_success) == 1) {
                # Set destination URI to NAT IP
                $du = "sip:" + $var(msg_user) + "@" + $var(endpoint_ip) + ":" + $var(endpoint_port);
            }
        }
    }
}
```

**Why NOTIFY needs this:**
- Asterisk sends NOTIFY with private IP in Request-URI after SUBSCRIBE
- NOTIFY is in-dialog and follows Record-Route
- Without NAT IP fix, `$du` remains unset and `t_relay()` fails
- NOTIFY retransmissions occur because no response is received

**Related:** This same pattern applies to any in-dialog request that needs NAT traversal (ACK, BYE, NOTIFY, UPDATE, etc.)

---

## Configuration Checklist

When setting up OpenSIPS configuration, verify:

### Module Loading
- [ ] All modules have `.so` extension
- [ ] `db_sqlite.so` loaded before `dispatcher.so`
- [ ] `sl.so` loaded (for `sl_send_reply()`)
- [ ] `sipmsgops.so` loaded (for `has_totag()`)
- [ ] `proto_udp.so` loaded (for transport)

### Module Parameters
- [ ] `dispatcher` uses `options_reply_codes` (not `ds_ping_reply_codes`)
- [ ] `tm` uses `T1_timer` and `T2_timer` (not `retr_timer1`/`retr_timer2`)
- [ ] No `fr_timer` or `fr_inv_timer` modparams (not supported)

### Function Calls
- [ ] Status codes are integers: `sl_send_reply(483, ...)` not `sl_send_reply("483", ...)`
- [ ] `mf_process_maxfwd_header(10)` uses integer
- [ ] `ds_select_dst($var(setid), 4)` uses integer flag
- [ ] `has_totag()` available (requires `sipmsgops.so`)
- [ ] `sql_query()` for INSERT/UPDATE/DELETE doesn't check return value (always false, but query succeeds)

### Pseudo-Variables
- [ ] Use `$(tu{uri.domain})` instead of `$tD`
- [ ] Use `$rd` instead of `$rD`
- [ ] Use `$tt` in xlog (not `$to_tag`)
- [ ] Use `""` for null checks (not `$null`)

### Database Schema
- [ ] Dispatcher table has all required columns in correct order
- [ ] `weight` column is TEXT with default '1'
- [ ] Version table has `dispatcher` version 9
- [ ] Table created with `DROP TABLE IF EXISTS` then `CREATE TABLE` (not `IF NOT EXISTS`)

### Routes
- [ ] `failure_route[1]` has index
- [ ] `t_on_failure("1")` called before `t_relay()`
- [ ] Event routes commented out if causing syntax errors

---

## Testing Commands

```bash
# Check configuration syntax
sudo opensips -C -f /etc/opensips/opensips.cfg

# Check service status
sudo systemctl status opensips

# View logs
sudo journalctl -u opensips -f

# Check database schema
sqlite3 /var/lib/opensips/routing.db ".schema dispatcher"
sqlite3 /var/lib/opensips/routing.db "SELECT * FROM version WHERE table_name='dispatcher';"

# Verify dispatcher entries
sqlite3 /var/lib/opensips/routing.db "SELECT * FROM dispatcher;"
```

---

## Key Takeaways

1. **Module load order matters** - Database modules before dependent modules
2. **Parameter names differ** - Always check OpenSIPS 3.6 documentation
3. **Integer vs String** - Many parameters require integers, not strings
4. **Schema is strict** - Dispatcher table must match exactly
5. **Pseudo-variables differ** - Some Kamailio vars don't exist in OpenSIPS
6. **Test incrementally** - Fix errors one at a time
7. **Use correct version** - OpenSIPS 3.6 uses dispatcher table version 9

---

## References

- OpenSIPS 3.6 Documentation: https://www.opensips.org/Documentation
- Dispatcher Module: https://www.opensips.org/docs/modules/3.6.x/dispatcher.html
- Transaction Module: https://www.opensips.org/docs/modules/3.6.x/tm.html
- Pseudo-Variables: https://www.opensips.org/docs/modules/3.6.x/pv.html

---

## Version Information

This knowledge base is based on:
- **OpenSIPS Version:** 3.6.x
- **Dispatcher Table Version:** 9
- **Migration Date:** December 2025
- **Source:** Kamailio 5.5.4 → OpenSIPS 3.6

---

*Last Updated: January 2026*

