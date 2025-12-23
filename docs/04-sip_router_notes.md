# SIP Router Notes

## Complete Kamailio Configuration

```kamailio
#!KAMAILIO
#
# Kamailio SIP Edge Router Configuration Template
# This file is used by install.sh if present, otherwise a default config is created
#

####### Global Parameters #########

debug=2
log_stderror=no
fork=yes
children=4

listen=udp:0.0.0.0:5060

####### Modules ########

loadmodule "sl.so"
loadmodule "tm.so"
loadmodule "rr.so"
loadmodule "pv.so"
loadmodule "xlog.so"
loadmodule "siputils.so"
loadmodule "maxfwd.so"
loadmodule "textops.so"
loadmodule "sanity.so"
loadmodule "dispatcher.so"
loadmodule "sqlops.so"
loadmodule "db_sqlite.so"

####### Module Parameters ########

# --- SQLite routing database ---
modparam("sqlops", "sqlcon",
    "cb=>sqlite:///var/lib/kamailio/routing.db")

# --- Dispatcher (health checks via SIP OPTIONS) ---
modparam("dispatcher", "db_url",
    "sqlite:///var/lib/kamailio/routing.db")

modparam("dispatcher", "ds_ping_method", "OPTIONS")
modparam("dispatcher", "ds_ping_interval", 30)
modparam("dispatcher", "ds_probing_threshold", 2)
modparam("dispatcher", "ds_inactive_threshold", 2)
modparam("dispatcher", "ds_ping_reply_codes", "200")

# --- Transaction timers ---
modparam("tm", "fr_timer", 5)
modparam("tm", "fr_inv_timer", 30)

####### Routing Logic ########

request_route {

    # ---- Basic hygiene ----
    if (!mf_process_maxfwd_header("10")) {
        sl_send_reply("483", "Too Many Hops");
        exit;
    }

    if (!sanity_check("1511", "7")) {
        xlog("L_WARN", "Malformed SIP from $si\n");
        exit;
    }

    # ---- Drop known scanners ----
    if ($ua =~ "(?i)sipvicious|friendly-scanner|sipcli|nmap") {
        exit;
    }

    # ---- In-dialog requests ----
    if (has_totag()) {
        route(WITHINDLG);
        exit;
    }

    # ---- Allowed methods only ----
    if (!is_method("REGISTER|INVITE|ACK|BYE|CANCEL|OPTIONS")) {
        sl_send_reply("405", "Method Not Allowed");
        exit;
    }

    route(DOMAIN_CHECK);
}

####### Domain validation / door-knocker protection ########

route[DOMAIN_CHECK] {

    $var(domain) = $rd;

    if ($var(domain) == "") {
        exit;
    }

    # Optional extra hardening: domain consistency
    if ($rd != $td) {
        xlog("L_WARN",
             "R-URI / To mismatch domain=$rd src=$si\n");
        exit;
    }

    # Lookup dispatcher set for this domain
    if (!sql_query("cb",
        "SELECT dispatcher_setid \
         FROM sip_domains \
         WHERE domain='$var(domain)' AND enabled=1")) {

        xlog("L_NOTICE",
             "Door-knock blocked: domain=$var(domain) src=$si\n");
        exit;
    }

    sql_result("cb", "dispatcher_setid", "$var(setid)");

    route(TO_DISPATCHER);
}

####### Health-aware routing ########

route[TO_DISPATCHER] {

    # Select a healthy Asterisk from the dispatcher set
    if (!ds_select_dst($var(setid), "4")) {
        xlog("L_ERR",
             "No healthy Asterisk nodes for domain=$rd\n");
        sl_send_reply("503", "Service Unavailable");
        exit;
    }

    record_route();

    if (!t_relay()) {
        sl_reply_error();
    }

    exit;
}

####### In-dialog handling ########

route[WITHINDLG] {

    if (loose_route()) {
        route(RELAY);
        exit;
    }

    sl_send_reply("404", "Not Here");
    exit;
}

route[RELAY] {
    if (!t_relay()) {
        sl_reply_error();
    }
    exit;
}

####### Dispatcher events (visibility) ########

event_route[dispatcher:dst-up] {
    xlog("L_INFO", "Asterisk UP: $du\n");
}

event_route[dispatcher:dst-down] {
    xlog("L_WARN", "Asterisk DOWN: $du\n");
}
```

### Database Layout

The Kamailio configuration uses a SQLite database with two main tables. This layout is referenced throughout the notes below.

#### sip_domains Table

```sql
CREATE TABLE sip_domains (
    domain TEXT PRIMARY KEY,
    dispatcher_setid INTEGER NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    comment TEXT
);

CREATE INDEX idx_sip_domains_enabled
ON sip_domains(enabled);
```

**Purpose:** Maps SIP domains to dispatcher set IDs for multi-tenant routing.

**Example data:**
- `tenant1.example.com` → `setid 10`
- `tenant2.example.com` → `setid 20`

#### dispatcher Table

```sql
CREATE TABLE dispatcher (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    setid INTEGER NOT NULL,
    destination TEXT NOT NULL,
    flags INTEGER DEFAULT 0,
    priority INTEGER DEFAULT 0,
    attrs TEXT
);

CREATE INDEX idx_dispatcher_setid
ON dispatcher(setid);
```

**Purpose:** Stores backend Asterisk server destinations grouped by setid. The dispatcher module loads this into memory for fast routing.

**Example destinations:**
- `setid=10` → `sip:10.0.1.10:5060` (primary Asterisk)
- `setid=10` → `sip:10.0.1.11:5060` (secondary Asterisk, same tenant)
- `setid=20` → `sip:10.0.2.20:5060` (different tenant)

**Note:** Health status is not stored here - dispatcher marks nodes up/down dynamically based on SIP OPTIONS health checks.

---

## Understanding the Dispatcher Table Columns

### The `setid` Column

The `setid` (set ID) column is a grouping mechanism that groups multiple destinations together. It links domains to their specific set of backend servers and enables multi-tenancy by allowing different domains to use different server groups.

#### How It Works

**The Two-Table Relationship:**

1. **`sip_domains` table** - Maps domains to set IDs:
   ```sql
   domain              → dispatcher_setid
   tenant1.example.com → 10
   tenant2.example.com → 20
   ```

2. **`dispatcher` table** - Groups destinations by set ID:
   ```sql
   setid → destination
   10    → sip:10.0.1.10:5060  (Asterisk for tenant1)
   10    → sip:10.0.1.11:5060  (Backup Asterisk for tenant1)
   20    → sip:10.0.2.20:5060  (Asterisk for tenant2)
   ```

#### The Routing Flow

```kamailio
# Step 1: Look up the domain to get its setid
sql_query("cb", "SELECT dispatcher_setid FROM sip_domains WHERE domain='$var(domain)'")
sql_result("cb", "dispatcher_setid", "$var(setid)")

# Step 2: Use that setid to select from the dispatcher table
ds_select_dst($var(setid), "4")  # Selects from all destinations with this setid
```

#### Real-World Example

**Multi-tenant setup:**

```sql
-- Tenant 1 (setid 10)
INSERT INTO sip_domains (domain, dispatcher_setid) 
VALUES ('tenant1.example.com', 10);

INSERT INTO dispatcher (setid, destination, priority) 
VALUES (10, 'sip:10.0.1.10:5060', 0);  -- Primary
INSERT INTO dispatcher (setid, destination, priority) 
VALUES (10, 'sip:10.0.1.11:5060', 10);  -- Backup

-- Tenant 2 (setid 20)
INSERT INTO sip_domains (domain, dispatcher_setid) 
VALUES ('tenant2.example.com', 20);

INSERT INTO dispatcher (setid, destination, priority) 
VALUES (20, 'sip:10.0.2.20:5060', 0);  -- Different server
INSERT INTO dispatcher (setid, destination, priority) 
VALUES (20, 'sip:10.0.2.21:5060', 10);  -- Different backup
```

**What happens:**
- Request for `tenant1.example.com` → looks up setid `10` → selects from destinations with setid `10` (10.0.1.10 or 10.0.1.11)
- Request for `tenant2.example.com` → looks up setid `20` → selects from destinations with setid `20` (10.0.2.20 or 10.0.2.21)

#### Key Benefits

1. **Multi-tenancy**: Different domains can route to different backend servers
2. **Isolation**: Tenant 1's traffic never goes to Tenant 2's servers
3. **Scalability**: Each tenant can have multiple backend servers (load balancing/failover)
4. **Flexibility**: Easy to add/remove destinations for a specific tenant without affecting others

#### Important Points

- The `setid` is just a number (integer) - you choose the values (10, 20, 30, etc.)
- Multiple destinations can share the same `setid` (for load balancing/failover)
- Each domain maps to exactly one `setid`, but each `setid` can have multiple destinations
- The `setid` is what connects the two tables together

In essence, `setid` is the tenant/group identifier that enables routing different domains to different sets of backend servers.

---

### The `flags` Column

The `flags` column in the dispatcher table is a bitmask (integer) that controls various behaviors of how Kamailio's dispatcher module selects and handles destinations.

#### Purpose

The `flags` column stores an integer bitmask that controls dispatcher behavior when `ds_select_dst()` is called. Common flags include:

#### Common Flag Values

1. **Flag 1 (bit 0 = 1)**: URI-based hashing uses only the username
   - Without this flag: hash uses username + hostname + port
   - With this flag: hash uses only the username
   - Useful for consistent routing based on user identity

2. **Flag 2 (bit 1 = 2)**: Enable failover support
   - Stores alternative addresses from the destination set in AVPs
   - If the selected destination fails, automatically tries alternatives
   - Useful for high availability scenarios

3. **Flag 4 (bit 2 = 4)**: Used in our config
   - In our code, `ds_select_dst($var(setid), "4")` uses flag value "4"
   - This is the algorithm selector, not the flags column value
   - Algorithm "4" typically means "round-robin with weight"

#### How It Works in our Setup

In our configuration, we're calling:
```kamailio
ds_select_dst($var(setid), "4")
```

The `"4"` here is the algorithm selector (round-robin), not the flags value. The `flags` column in the database is separate and can be used to:
- Control failover behavior (flag 2)
- Control URI hashing behavior (flag 1)
- Combine multiple behaviors (e.g., flags = 3 = 1+2 for both username-only hashing and failover)

#### Example Usage

```sql
-- Destination with failover enabled
INSERT INTO dispatcher (setid, destination, flags, priority)
VALUES (10, 'sip:10.0.1.10:5060', 2, 0);  -- Flag 2 = failover

-- Destination with username-only hashing
INSERT INTO dispatcher (setid, destination, flags, priority)
VALUES (10, 'sip:10.0.1.11:5060', 1, 0);  -- Flag 1 = username-only hash

-- Both behaviors combined
INSERT INTO dispatcher (setid, destination, flags, priority)
VALUES (10, 'sip:10.0.1.12:5060', 3, 0);  -- Flag 3 = 1+2 (both)
```

In our current setup, flags are set to `0` (default), which means no special behaviors are enabled—just basic destination selection using the algorithm specified in `ds_select_dst()`.

---

### The `priority` Column

The `priority` column in the dispatcher table controls the selection order of destinations, especially when using priority-based algorithms.

#### Purpose

The `priority` column assigns a numerical priority to each destination. **Lower values = higher priority** (selected first).

#### How It Works

1. **Lower numbers = higher priority**
   - Priority `0` is selected before priority `10`
   - Priority `10` is selected before priority `20`

2. **Algorithm-dependent behavior**
   - Our current config uses `ds_select_dst($var(setid), "4")` (algorithm 4 = round-robin)
   - With round-robin, priority may not affect selection
   - Priority matters with algorithms 8 and 13 (priority-based serial forking)

#### Common Use Cases

**Primary/Secondary Setup:**
```sql
-- Primary server (selected first)
INSERT INTO dispatcher (setid, destination, flags, priority)
VALUES (10, 'sip:10.0.1.10:5060', 0, 0);  -- Priority 0 = highest

-- Secondary server (backup)
INSERT INTO dispatcher (setid, destination, flags, priority)
VALUES (10, 'sip:10.0.1.11:5060', 0, 10);  -- Priority 10 = lower
```

**Tiered Priority Setup:**
```sql
-- Tier 1 (highest priority)
INSERT INTO dispatcher (setid, destination, flags, priority)
VALUES (10, 'sip:10.0.1.10:5060', 0, 0);

-- Tier 2 (medium priority)
INSERT INTO dispatcher (setid, destination, flags, priority)
VALUES (10, 'sip:10.0.1.11:5060', 0, 10);

-- Tier 3 (lowest priority, last resort)
INSERT INTO dispatcher (setid, destination, flags, priority)
VALUES (10, 'sip:10.0.1.12:5060', 0, 20);
```

#### Algorithms That Use Priority

- **Algorithm 8**: Priority-based serial forking (lower priority first)
- **Algorithm 13**: Priority-based serial forking (lower priority first)
- **Algorithm 4** (our current): Round-robin (priority typically ignored)

#### In Our Current Setup

Since you're using algorithm `"4"` (round-robin), the `priority` column is currently not affecting selection—destinations are selected in round-robin fashion regardless of priority. However, you can still set priorities for:
1. Documentation/clarity (showing which servers are primary/secondary)
2. Future flexibility (if you switch to algorithm 8 or 13)
3. Database organization (grouping destinations by importance)

If you want priority-based selection, change the `ds_select_dst()` call to use algorithm `"8"`:
```kamailio
ds_select_dst($var(setid), "8")  # Priority-based serial forking
```

This would make Kamailio try destinations in priority order (0, then 10, then 20, etc.), which is useful for primary/backup scenarios.

---

## How Routing Actually Works: Understanding `ds_select_dst()`

### The Question

You might notice that the Kamailio config never explicitly retrieves the destination IP address from the database. So how does it route to the correct backend Asterisk?

### The Answer: Dispatcher Module Magic

The destination IP **is** retrieved, but it's handled automatically by the dispatcher module behind the scenes, not by an explicit SQL query in the routing script.

### How It Actually Works

#### 1. **Dispatcher Module Loads Data at Startup**

When Kamailio starts, the dispatcher module:
- Reads the `dispatcher` table from the database (via `db_url` parameter on line 38-39)
- Loads all destinations into **memory** (in-memory cache)
- Maintains this cache for fast lookups
- Performs health checks (SIP OPTIONS pings) to mark destinations as up/down

#### 2. **`ds_select_dst()` Does the Heavy Lifting**

When you call `ds_select_dst($var(setid), "4")` on line 124, it:

1. **Looks up** all destinations with that `setid` from its **in-memory cache** (not a SQL query)
2. **Filters out** unhealthy destinations (based on health check status)
3. **Selects** one destination using algorithm "4" (round-robin)
4. **Automatically sets** the destination URI in the `$du` variable

The `$du` variable is the destination URI that Kamailio will send the request to.

#### 3. **`t_relay()` Uses the Destination**

When `t_relay()` is called on line 133, it:
- Reads the `$du` variable (set by `ds_select_dst()`)
- Sends the SIP request to that destination IP/port

### The Complete Flow

```
1. SIP request arrives for "example.com"
   ↓
2. SQL query: SELECT dispatcher_setid FROM sip_domains WHERE domain='example.com'
   → Returns: setid = 10
   ↓
3. ds_select_dst(10, "4")
   → Dispatcher module looks in its IN-MEMORY cache for setid=10
   → Finds: sip:10.0.1.10:5060 (healthy) and sip:10.0.1.11:5060 (healthy)
   → Selects sip:10.0.1.10:5060 (round-robin)
   → Sets $du = "sip:10.0.1.10:5060"  ← Destination IP is set here!
   ↓
4. t_relay()
   → Reads $du = "sip:10.0.1.10:5060"
   → Sends SIP request to 10.0.1.10:5060
```

### Why This Design?

- **Performance**: No SQL query per request - uses in-memory cache
- **Health awareness**: Only healthy destinations are selected
- **Automatic failover**: Unhealthy destinations are automatically skipped

### The Key Point

The dispatcher module maintains an **in-memory cache** of the `dispatcher` table. When `ds_select_dst()` is called:
- It queries this **cache** (not the database)
- It sets `$du` **automatically**
- `t_relay()` then uses `$du` to send the request

So the destination IP is retrieved, but by the dispatcher module from its cache, not by an explicit SQL query in the routing script. This is why you don't see a SQL query for the destination—it's handled internally by the dispatcher module.

### Summary

- **Our script**: Queries `sip_domains` table to get the `setid`
- **Dispatcher module**: Uses `setid` to look up destinations from its in-memory cache
- **`ds_select_dst()`**: Selects a healthy destination and sets `$du`
- **`t_relay()`**: Sends the request to the destination in `$du`

The "magic" is that the dispatcher module does all the destination lookup and selection work for you, making the routing script simple and efficient.
