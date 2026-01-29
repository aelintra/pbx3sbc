# Statistics Overview

**Date:** January 2026  
**Branch:** `stats`  
**Purpose:** Document all statistics currently being collected and where they are stored

## Summary

The PBX3sbc system collects statistics in two categories:

### 1. Operational Data (Database Tables)
Currently stored in MySQL database tables:

1. **`acc`** - Call Detail Records (CDR) for billing and call reporting
2. **`dialog`** - Active dialog state tracking for call monitoring
3. **`location`** - Endpoint registration statistics

### 2. Real-Time Statistics (Management Interface)
OpenSIPS 3.6 collects extensive real-time statistics via its **Management Interface (MI)**, but these are **NOT stored in database tables by default**. These include:

- Request/response counts (core:rcv_requests, core:rcv_replies)
- Transaction statistics (tm:transactions, tm:active_transactions)
- Dialog statistics (dialog:active_dialogs, dialog:early_dialogs)
- Module-specific statistics (dispatcher:active_destinations, etc.)
- Performance metrics (processing times, memory usage)
- Error rates and failure statistics

**Access Methods:**
- **Management Interface (MI)**: Via `opensips-cli` or `opensipsctl fifo`
- **Script Variables**: `$stat()` pseudo-variable in routing script
- **External Tools**: Prometheus/Grafana integration (planned)

**Note:** These real-time statistics are ephemeral and not persisted unless collected by external monitoring tools.

## Data Persistence

**All statistics are persistent** to MySQL database, but with different persistence characteristics:

| Table | Persistence | Notes |
|-------|-------------|-------|
| **`acc`** | ✅ **Immediate** | CDR records written directly to database |
| **`dialog`** | ⚠️ **Cached (10s delay)** | Cached in memory, flushed every 10 seconds |
| **`location`** | ⚠️ **Cached (10s delay)** | Cached in memory, flushed every 10 seconds |

**Important Notes:**
- **CDR records (`acc`)**: Written immediately - no data loss risk
- **Dialog and Location**: Cached for performance, flushed every 10 seconds
  - **Normal restart**: Data persists (loaded from database on startup)
  - **Crash/abnormal shutdown**: Up to 10 seconds of data may be lost
  - **Active calls**: Dialog state may be lost on crash, but CDR will still be created

---

## 1. Call Detail Records (CDR) - `acc` Table

### Purpose
Tracks completed calls for billing, reporting, and call analysis.

### Storage Location
- **Database:** MySQL (`opensips` database)
- **Table:** `acc`
- **Module:** OpenSIPS `acc` module with CDR mode enabled

### Configuration
**File:** `config/opensips.cfg.template`

```opensips
# Accounting module configuration
modparam("acc", "db_url", "mysql://opensips:your-password@localhost/opensips")
modparam("acc", "early_media", 0)          # Don't account for early media
modparam("acc", "report_cancels", 1)       # Report cancelled calls
modparam("acc", "detect_direction", 1)     # Detect call direction
modparam("acc", "extra_fields", "db:from_uri->from_uri;to_uri->to_uri")

# CDR mode enabled for INVITE requests
if (is_method("INVITE") && !has_totag()) {
    $acc_extra(from_uri) = $fu;
    $acc_extra(to_uri) = $tu;
    do_accounting("db", "cdr");
}
```

### Persistence
✅ **Immediately Persistent**
- CDR records are written directly to the database when `do_accounting("db", "cdr")` is called
- No caching - data is immediately available in database
- **No data loss risk** on crash or restart
- Records persist across OpenSIPS restarts

### Schema

| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER PRIMARY KEY | Auto-incrementing record ID |
| `method` | CHAR(16) | SIP method (INVITE, BYE, etc.) |
| `from_tag` | CHAR(64) | From tag from SIP headers |
| `to_tag` | CHAR(64) | To tag from SIP headers |
| `callid` | CHAR(64) | SIP Call-ID header |
| `sip_code` | CHAR(3) | Final SIP response code (200, 404, etc.) |
| `sip_reason` | CHAR(32) | SIP reason phrase |
| `time` | DATETIME | Timestamp of the accounting event |
| `duration` | INTEGER | Call duration in seconds |
| `ms_duration` | INTEGER | Call duration in milliseconds |
| `setuptime` | INTEGER | Time to answer (setup time) in seconds |
| `created` | DATETIME | Call start timestamp |
| `from_uri` | VARCHAR(255) | **Custom:** Full From SIP URI |
| `to_uri` | VARCHAR(255) | **Custom:** Full To SIP URI |

### What Gets Collected

**CDR Mode Behavior:**
- Single record per call (INVITE and BYE are correlated)
- Duration calculated automatically from INVITE to BYE
- `created` timestamp set when INVITE is received
- `time` timestamp set when call ends (BYE received)
- `setuptime` calculated as time from INVITE to 200 OK
- `from_uri` and `to_uri` captured from INVITE request

**Collected For:**
- ✅ Successful calls (200 OK)
- ✅ Cancelled calls (`report_cancels=1`)
- ❌ Early media (180 Ringing) - not collected (`early_media=0`)

**Not Collected:**
- Failed calls (unless cancelled)
- OPTIONS requests
- REGISTER requests
- Other non-INVITE methods (unless part of call flow)

### Example Record

```sql
SELECT * FROM acc WHERE id = 12;
```

| id | method | from_tag | to_tag | callid | sip_code | time | duration | ms_duration | setuptime | created | from_uri | to_uri |
|----|-------|----------|--------|--------|----------|------|----------|-------------|-----------|---------|----------|--------|
| 12 | INVITE | 3976936221 | 9d688bf9-... | 2_3977016247@192.168.1.232 | 200 | 2026-01-17 22:18:30 | 6 | 5070 | 2 | 2026-01-17 22:18:28 | sip:1000@example.com | sip:1001@example.com |

---

## 2. Dialog State Tracking - `dialog` Table

### Purpose
Tracks active SIP dialogs (calls) for call state monitoring and CDR correlation.

**Important:** Dialog records are **call-specific**, not endpoint-specific. They track individual calls and should only disappear when the call ends, NOT when an endpoint registers from a new location.

### Storage Location
- **Database:** MySQL (`opensips` database)
- **Table:** `dialog`
- **Module:** OpenSIPS `dialog` module
- **Mode:** Cached DB (`db_mode=2`) - writes to DB periodically

### Configuration
**File:** `config/opensips.cfg.template`

```opensips
modparam("dialog", "db_url", "mysql://opensips:your-password@localhost/opensips")
modparam("dialog", "db_mode", 2)              # Cached DB mode
modparam("dialog", "db_update_period", 10)     # Flush to DB every 10 seconds
```

### Persistence
⚠️ **Cached with Periodic Flush**
- Data is cached in memory for performance (`db_mode=2`)
- Flushed to database every 10 seconds (`db_update_period=10`)
- **Normal restart**: Data persists (loaded from database on startup)
- **Crash/abnormal shutdown**: Up to 10 seconds of dialog state may be lost
- **Note**: CDR records (`acc` table) are still created even if dialog state is lost

### Schema

| Column | Type | Description |
|--------|------|-------------|
| `dlg_id` | BIGINT(10) PRIMARY KEY | Dialog ID |
| `callid` | CHAR(255) | SIP Call-ID header |
| `from_uri` | CHAR(255) | From SIP URI |
| `from_tag` | CHAR(64) | From tag |
| `to_uri` | CHAR(255) | To SIP URI |
| `to_tag` | CHAR(64) | To tag |
| `mangled_from_uri` | CHAR(255) | NAT-mangled From URI |
| `mangled_to_uri` | CHAR(255) | NAT-mangled To URI |
| `caller_cseq` | CHAR(11) | Caller CSeq |
| `callee_cseq` | CHAR(11) | Callee CSeq |
| `caller_ping_cseq` | INTEGER | Caller ping CSeq |
| `callee_ping_cseq` | INTEGER | Callee ping CSeq |
| `caller_route_set` | TEXT(512) | Caller Record-Route headers |
| `callee_route_set` | TEXT(512) | Callee Record-Route headers |
| `caller_contact` | CHAR(255) | Caller Contact header |
| `callee_contact` | CHAR(255) | Callee Contact header |
| `caller_sock` | CHAR(64) | Caller socket info |
| `callee_sock` | CHAR(64) | Callee socket info |
| `state` | INTEGER | **Dialog state (1-5)** |
| `start_time` | INTEGER | Dialog start time (Unix timestamp) |
| `timeout` | INTEGER | Dialog timeout (seconds) |
| `vars` | BLOB(4096) | Dialog variables |
| `profiles` | TEXT(512) | Dialog profiles |
| `script_flags` | CHAR(255) | Script flags |
| `module_flags` | INTEGER | Module flags |
| `flags` | INTEGER | Dialog flags |
| `rt_on_answer` | CHAR(64) | Route on answer |
| `rt_on_timeout` | CHAR(64) | Route on timeout |
| `rt_on_hangup` | CHAR(64) | Route on hangup |

### Dialog States

| State | Name | Description |
|-------|------|-------------|
| 1 | Unconfirmed | Dialog created, no reply yet |
| 2 | Early | Provisional reply (180 Ringing) received |
| 3 | Confirmed | Final reply (200 OK) received, ACK not yet matched |
| 4 | Established | **Call is active and established** |
| 5 | Ended | Dialog terminated (BYE received) |

### What Gets Collected

**Collected For:**
- ✅ All INVITE-initiated dialogs
- ✅ Active calls (state 4)
- ✅ Call setup (states 1-3)
- ✅ Ended calls (state 5)

**Update Frequency:**
- Cached in memory for performance
- Flushed to database every 10 seconds (`db_update_period=10`)
- May appear empty immediately after call starts (cached)

**Lifecycle:**
- **Created:** When INVITE is received (state 1: Unconfirmed)
- **Updated:** As call progresses (states 2-4)
- **Ended:** When BYE is received (state 5: Ended)
- **Cleanup:** Ended dialogs (state 5) should be cleaned up automatically by OpenSIPS
- **NOT affected by:** Endpoint registration changes (unrelated to calls)

**Used For:**
- CDR correlation (acc module uses dialog to correlate INVITE/BYE)
- Call state monitoring
- Active call tracking

### Example Query

```sql
-- View active calls (state 4)
SELECT callid, from_uri, to_uri, state, FROM_UNIXTIME(start_time) as start_time
FROM dialog 
WHERE state = 4;

-- View all dialogs
SELECT callid, state, FROM_UNIXTIME(start_time) as start_time
FROM dialog 
ORDER BY start_time DESC 
LIMIT 10;
```

---

## 3. Endpoint Registration Statistics - `location` Table

### Purpose
Tracks registered endpoints for routing and endpoint statistics.

**Important:** Location records are **endpoint-specific** and **ephemeral**. They should update/replace when an endpoint registers from a new location.

### Storage Location
- **Database:** MySQL (`opensips` database)
- **Table:** `location`
- **Module:** OpenSIPS `usrloc` module
- **Mode:** Cached DB (`db_mode=2`)

### Configuration
**File:** `config/opensips.cfg.template`

```opensips
modparam("usrloc", "db_url", "mysql://opensips:your-password@localhost/opensips")
modparam("usrloc", "db_mode", 2)  # Cached DB mode
modparam("usrloc", "timer_interval", 10)  # Flush to DB every 10 seconds
```

### Persistence
⚠️ **Cached with Periodic Flush**
- Data is cached in memory for performance (`db_mode=2`)
- Flushed to database every 10 seconds (`timer_interval=10`)
- **Normal restart**: Data persists (loaded from database on startup)
- **Crash/abnormal shutdown**: Up to 10 seconds of registration changes may be lost
- **Note**: Expired registrations are cleaned up automatically based on `expires` timestamp

### Schema

| Column | Type | Description |
|--------|------|-------------|
| `contact_id` | BIGINT UNSIGNED PRIMARY KEY | Auto-incrementing contact ID |
| `username` | CHAR(64) | Username part of AoR |
| `domain` | CHAR(64) | Domain part of AoR |
| `contact` | TEXT | Full Contact header |
| `received` | CHAR(255) | NAT: received IP:port |
| `path` | CHAR(255) | Path header (for NAT) |
| `expires` | INT | Expiration time (Unix timestamp) |
| `q` | FLOAT(10,2) | Contact priority (q-value) |
| `callid` | CHAR(255) | SIP Call-ID from REGISTER |
| `cseq` | INT | CSeq from REGISTER |
| `last_modified` | DATETIME | Last modification time |
| `flags` | INT | Contact flags |
| `cflags` | CHAR(255) | Custom flags |
| `user_agent` | CHAR(255) | **User-Agent header** |
| `socket` | CHAR(64) | Local socket info |
| `methods` | INT | Supported methods |
| `sip_instance` | CHAR(255) | SIP instance ID |
| `kv_store` | TEXT(512) | Key-value store |
| `attr` | CHAR(255) | Custom attributes |

### What Gets Collected

**Collected For:**
- ✅ Successful REGISTER requests (2xx responses only)
- ✅ All registered endpoints
- ✅ Multi-tenant support (username + domain)

**Not Collected For:**
- ❌ Failed registrations (401, 403, etc.)
- ❌ Unregistered endpoints

**Lifecycle & Ephemeral Nature:**
- **Created:** When endpoint successfully registers (2xx response)
- **Updated:** When endpoint re-registers from same or different location
  - `save("location")` updates existing contact if same AoR
  - Multiple contacts per AoR allowed (for load balancing)
- **Expired:** Based on `expires` timestamp (Unix timestamp)
- **Replaced:** When endpoint registers from new location (new Contact header)
  - Old contact expires naturally or is replaced
  - New contact created with updated IP/port
- **Deleted:** When registration expires or endpoint de-registers (Expires: 0)

**Statistics Available:**
- Total registered endpoints per domain
- Registration timestamps (`last_modified`)
- Endpoint user agents
- Registration expiration times
- NAT information (`received` field)

### Example Queries

```sql
-- Count registered endpoints per domain
SELECT domain, COUNT(*) as endpoint_count
FROM location
WHERE expires > UNIX_TIMESTAMP()
GROUP BY domain;

-- View all registered endpoints
SELECT username, domain, contact, FROM_UNIXTIME(expires) as expires_at, user_agent
FROM location
WHERE expires > UNIX_TIMESTAMP()
ORDER BY last_modified DESC;

-- Find endpoints expiring soon
SELECT username, domain, FROM_UNIXTIME(expires) as expires_at
FROM location
WHERE expires BETWEEN UNIX_TIMESTAMP() AND UNIX_TIMESTAMP() + 3600
ORDER BY expires;
```

---

## Ephemeral Nature of Statistics

### `location` Table - ✅ Ephemeral (Endpoint-Specific)

**Yes, location records are ephemeral and should update/replace when endpoints register from new locations:**

- **When endpoint registers from new location:**
  - `save("location")` updates existing contact if same AoR (username@domain)
  - Creates new contact if different Contact header (different IP/port)
  - Old contacts expire based on `expires` timestamp
  - Multiple contacts per AoR allowed (for load balancing)

- **When endpoint de-registers:**
  - Sends REGISTER with `Expires: 0`
  - Contact expires immediately (`expires` set to current time)
  - Removed from active lookups (filtered by `expires > UNIX_TIMESTAMP()`)

- **Automatic cleanup:**
  - Expired contacts filtered out in queries (`expires > UNIX_TIMESTAMP()`)
  - OpenSIPS usrloc module handles expiration automatically
  - Old contacts naturally expire and become inactive

**Example:**
```
Endpoint registers from 192.168.1.100:5060
→ Contact created: username=1000, domain=example.com, contact=sip:1000@192.168.1.100:5060

Endpoint moves, registers from 192.168.1.200:5060
→ Contact updated/replaced: contact=sip:1000@192.168.1.200:5060
→ Old contact expires or is replaced
```

### `dialog` Table - ⚠️ Ephemeral (Call-Specific, NOT Location-Specific)

**Dialog records are ephemeral per call, but NOT tied to endpoint registration locations:**

- **Lifecycle:**
  - Created when INVITE received (state 1)
  - Updated as call progresses (states 2-4)
  - Ended when BYE received (state 5)
  - Should be cleaned up when call ends

- **NOT affected by:**
  - Endpoint registration changes (unrelated to calls)
  - Endpoint moving to new location (doesn't affect active calls)
  - New registrations (calls are independent of registrations)

- **Cleanup:**
  - Ended dialogs (state 5) should be cleaned up automatically
  - Timeout-based cleanup for stuck dialogs
  - May persist briefly after call ends (up to 10 seconds due to caching)

**Example:**
```
Call starts: INVITE received
→ Dialog created: callid=abc123, state=1

Call active: 200 OK + ACK received
→ Dialog updated: state=4 (Established)

Call ends: BYE received
→ Dialog updated: state=5 (Ended)
→ Should be cleaned up automatically

Endpoint registers from new location (unrelated)
→ Dialog record NOT affected (still state=5, waiting cleanup)
```

**Key Point:** Dialog records track **calls**, not **endpoint locations**. An endpoint registering from a new location does NOT affect active call dialogs.

---

## Statistics Retention & Data Loss

### ⚠️ Important: Statistics Will Be Lost Over Time

**Not all statistics persist indefinitely:**

| Table | Retention | Data Loss |
|-------|-----------|-----------|
| **`acc`** | ✅ **Persistent** | ❌ **No data loss** - Records persist indefinitely (unless manually deleted) |
| **`dialog`** | ⚠️ **Ephemeral** | ✅ **Yes, data lost** - Cleaned up when calls end (state 5) |
| **`location`** | ⚠️ **Ephemeral** | ✅ **Yes, data lost** - Expired registrations cleaned up automatically |

### Implications for Statistics

**What You'll Have Long-Term:**
- ✅ **Call Detail Records (CDR)** - Complete call history in `acc` table
  - Call duration, timestamps, SIP URIs
  - Billing and reporting data
  - Historical call analysis

**What You'll Lose Over Time:**
- ❌ **Active Call State History** - `dialog` records cleaned up after calls end
  - Cannot analyze historical call state transitions
  - Cannot see which calls were active at specific times
  - Only current/active calls visible

- ❌ **Registration History** - `location` records expire and are cleaned up
  - Cannot see historical registration patterns
  - Cannot track endpoint registration changes over time
  - Cannot analyze registration duration trends
  - Only current registrations visible

### Why This Happens

**Design Philosophy:**
- `acc` table: Designed for billing/reporting → **Persistent**
- `dialog` table: Designed for call routing → **Operational, not archival**
- `location` table: Designed for endpoint routing → **Operational, not archival**

**Performance & Storage:**
- Keeping all dialog/location records would cause database bloat
- These tables are optimized for fast lookups, not historical analysis
- Cleanup prevents unbounded growth

### Solutions for Long-Term Statistics

If you need historical statistics, consider:

1. **Archive `acc` records** (already persistent, but may want to archive old records)
2. **Create statistics snapshots** - Periodically query and store:
   - Active call counts per time period
   - Registration counts per domain
   - Endpoint registration durations
3. **Export before cleanup** - Export dialog/location data before cleanup runs
4. **Separate statistics database** - Copy relevant data to analytics database
5. **Use `acc` table for call statistics** - Most call statistics can be derived from CDR records

---

## Statistics Summary

### Currently Collected

| Category | Table | What's Tracked | Frequency | Retention |
|----------|-------|---------------|-----------|-----------|
| **Call Records** | `acc` | Call duration, timestamps, SIP URIs, response codes | Per call | ✅ Persistent |
| **Call State** | `dialog` | Active call state, dialog info | Every 10 seconds | ⚠️ Ephemeral |
| **Registrations** | `location` | Registered endpoints, user agents, expiration | Per registration | ⚠️ Ephemeral |

### Not Currently Collected (But Available via MI)

These statistics are **available via OpenSIPS Management Interface (MI)** but **not persisted to database**:

- ❌ Request rate statistics (requests per second) - Available via `core:rcv_requests`
- ❌ Error rate statistics (failed requests) - Available via `core:rcv_replies` with error codes
- ❌ IP-based statistics (requests per IP) - Available via MI commands
- ❌ Method-based statistics (REGISTER count, INVITE count, etc.) - Available via `core:rcv_requests` breakdown
- ❌ Domain-based call statistics (calls per domain) - Can be derived from `acc` table
- ❌ Endpoint call statistics (calls per endpoint) - Can be derived from `acc` table
- ❌ Dispatcher health statistics (backend availability) - Available via `dispatcher:*` MI commands
- ❌ NAT traversal statistics - Available via `nathelper:*` MI commands
- ❌ Transaction statistics - Available via `tm:*` MI commands
- ❌ Dialog statistics - Available via `dialog:*` MI commands
- ❌ Memory usage - Available via `shmem:*` MI commands
- ❌ Processing times - Available via performance profiling

**Access Example:**
```bash
# Get all statistics
opensips-cli -x mi get_statistics

# Get specific statistic
opensips-cli -x mi get_statistics core:rcv_requests

# Get dispatcher statistics
opensips-cli -x mi get_statistics dispatcher:active_destinations
```

### Potential Enhancements

See `docs/MASTER-PROJECT-PLAN.md` for planned statistics enhancements:

1. **Security Statistics** (High Priority)
   - Failed registration attempts
   - Scanner detection events
   - Rate limiting violations

2. **Enhanced Statistics Dashboard** (Medium Priority)
   - Calls per domain
   - Calls per endpoint
   - Call duration trends
   - Peak call times

3. **Performance Statistics** (Medium Priority)
   - Request processing times
   - Dispatcher response times
   - Database query performance

4. **Prometheus/Grafana Integration** (Planned - On Roadmap)
   - Scrape OpenSIPS MI statistics via Prometheus exporter
   - Store real-time statistics in time-series database
   - Historical analysis and visualization via Grafana
   - Alerting on thresholds
   - **Benefits:**
     - Persist real-time statistics that are currently ephemeral
     - Historical trending and analysis
     - Real-time dashboards
     - Alerting on performance issues
   - **Status:** Planned - See `docs/MASTER-PROJECT-PLAN.md` for details

---

## Database Access

### Credentials
- **Database:** `opensips`
- **User:** `opensips`
- **Password:** Stored in `/etc/opensips/.mysql_credentials`

### Example Queries

```bash
# Connect to database
mysql -u opensips -p opensips

# View recent CDRs
SELECT * FROM acc ORDER BY created DESC LIMIT 10;

# View active calls
SELECT * FROM dialog WHERE state = 4;

# View registered endpoints
SELECT * FROM location WHERE expires > UNIX_TIMESTAMP();
```

---

## Real-Time Statistics via Management Interface (MI)

### Overview

OpenSIPS 3.6 provides extensive real-time statistics through its **Management Interface (MI)**, but these statistics are **NOT stored in database tables by default**. They are accessed dynamically at runtime.

### Available Statistics

**Core Statistics:**
- `core:rcv_requests` - Total received requests
- `core:rcv_replies` - Total received replies
- `core:fwd_requests` - Total forwarded requests
- `core:fwd_replies` - Total forwarded replies
- `core:drop_requests` - Dropped requests
- `core:err_requests` - Error requests

**Transaction Statistics:**
- `tm:transactions` - Total transactions
- `tm:active_transactions` - Active transactions
- `tm:UAS_transactions` - UAS transactions
- `tm:UAC_transactions` - UAC transactions

**Dialog Statistics:**
- `dialog:active_dialogs` - Active dialogs
- `dialog:early_dialogs` - Early dialogs
- `dialog:processed_dialogs` - Processed dialogs

**Dispatcher Statistics:**
- `dispatcher:active_destinations` - Active destinations
- `dispatcher:inactive_destinations` - Inactive destinations

**Module-Specific Statistics:**
- `nathelper:*` - NAT traversal statistics
- `usrloc:*` - User location statistics
- `acc:*` - Accounting statistics
- `shmem:*` - Shared memory statistics

### Access Methods

**1. Command Line (opensips-cli):**
```bash
# Get all statistics
opensips-cli -x mi get_statistics

# Get specific statistic
opensips-cli -x mi get_statistics core:rcv_requests

# Get dispatcher statistics
opensips-cli -x mi get_statistics dispatcher:active_destinations
```

**2. Script Variables:**
```opensips
# In opensips.cfg routing script
xlog("Total requests received: $stat(rcv_requests)\n");
xlog("Active dialogs: $stat(active_dialogs)\n");
```

**3. Management Interface (MI) Commands:**
```bash
# Via FIFO
opensipsctl fifo get_statistics

# Via MI HTTP (if enabled)
curl http://localhost:8080/mi/get_statistics
```

### Prometheus/Grafana Integration (Planned)

**Status:** On roadmap - See `docs/MASTER-PROJECT-PLAN.md`

**Proposed Solution:**
- **Prometheus Exporter**: Scrape OpenSIPS MI statistics
- **Time-Series Database**: Store historical statistics in Prometheus
- **Grafana Dashboards**: Visualize statistics and trends
- **Alerting**: Alert on thresholds (high error rates, low availability, etc.)

**Benefits:**
- ✅ Persist real-time statistics that are currently ephemeral
- ✅ Historical trending and analysis
- ✅ Real-time dashboards
- ✅ Alerting on performance issues
- ✅ Integration with existing monitoring infrastructure

**OpenSIPS 3.6 Support:**
- OpenSIPS 3.6 supports Prometheus integration
- Can expose statistics via HTTP endpoint for scraping
- Compatible with standard Prometheus exporters

**References:**
- OpenSIPS 3.6 Core Statistics Documentation: https://opensips.org/docs/modules/3.6.x/core.html#statistics
- OpenSIPS Management Interface: https://opensips.org/docs/modules/3.6.x/mi_fifo.html
- **Prometheus/Grafana Deployment Plan:** `PROMETHEUS-GRAFANA-PLAN.md` - Complete deployment plan

---

## Related Documentation

- `docs/PROJECT-CONTEXT.md` - Project overview
- `../guides/technical/DIALOG-STATE-EXPLANATION.md` - Dialog state details
- `../MASTER-PROJECT-PLAN.md` - Planned enhancements (includes Prometheus/Grafana)
- `PROMETHEUS-GRAFANA-PLAN.md` - **Complete Prometheus/Grafana deployment plan**
- `workingdocs/SESSION-SUMMARY-ACCOUNTING-CDR.md` - CDR implementation details
- OpenSIPS 3.6 Statistics Documentation: https://opensips.org/docs/modules/3.6.x/core.html#statistics

---

**Last Updated:** January 2026  
**Maintained By:** Project Team
