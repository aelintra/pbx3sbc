# Requirements Summary for OpenSIPS Configuration

**Purpose:** This document summarizes the requirements, logic, and learnings from the Kamailio SBC implementation to guide OpenSIPS configuration.

**Date:** December 25, 2024

## System Architecture

- **SBC Role:** Kamailio/OpenSIPS acts as a Session Border Controller (SBC) between SIP endpoints and Asterisk backends
- **Endpoints:** SIP phones/softphones register through the SBC
- **Backends:** Multiple Asterisk servers behind the SBC (load balanced via dispatcher)
- **Database:** SQLite database for routing configuration and endpoint tracking

## Core Requirements

### 1. Endpoint Registration Tracking

**Requirement:** Track endpoint locations (IP:port) when they register, so we can route OPTIONS/NOTIFY from Asterisk back to endpoints.

**Implementation:**
- Extract AoR (Address of Record) from To header: `user@domain`
- Extract contact IP and port from Contact header or use source IP:port
- Store in `endpoint_locations` table with expiration time
- Handle Contact headers with complex parameters (angle brackets, `reg-id`, `sip.instance`, etc.)

**Database Schema:**
```sql
CREATE TABLE endpoint_locations (
    aor TEXT PRIMARY KEY,           -- Format: user@domain
    contact_ip TEXT NOT NULL,       -- Endpoint IP address
    contact_port TEXT NOT NULL,     -- Endpoint port
    expires DATETIME NOT NULL       -- Expiration timestamp
);
```

**Key Challenge:** Contact headers can have complex formats:
- `<sip:user@ip:port;line=xxx>;reg-id=1;+sip.instance="<urn:uuid:...>"`
- Need regex-based extraction, not URI parsing

### 2. OPTIONS/NOTIFY Routing from Asterisk to Endpoints

**Requirement:** When Asterisk sends OPTIONS (health checks) or NOTIFY (event notifications) to registered endpoints, route them to the actual endpoint IP:port.

**Logic Flow:**
1. Detect if request comes from a known Asterisk backend (check dispatcher table)
2. Extract endpoint identifier from To header (AoR or username)
3. Look up endpoint location from `endpoint_locations` table
4. Construct destination URI: `sip:user@ip:port`
5. Route to endpoint

**Key Challenges:**
- Dispatcher destinations can be stored in various formats: `IP`, `IP:PORT`, `sip:IP`, `sip:IP:PORT`
- To header from Asterisk may contain IP instead of domain
- Need fallback lookup by username only if exact match fails
- Request-URI must be valid - construct directly, don't try to rewrite invalid URIs

**Database Schema:**
```sql
CREATE TABLE dispatcher (
    id INTEGER PRIMARY KEY,
    setid INTEGER NOT NULL,         -- Dispatcher set ID
    destination TEXT NOT NULL,      -- Format varies: IP, IP:PORT, sip:IP, sip:IP:PORT
    flags INTEGER DEFAULT 0,
    priority INTEGER DEFAULT 0,
    attrs TEXT,
    description TEXT
);
```

### 3. INVITE Routing to Asterisk Backends

**Requirement:** Route INVITE requests from endpoints to healthy Asterisk backends using dispatcher.

**Logic Flow:**
1. Validate domain (door-knocker protection)
2. Look up dispatcher set ID for domain
3. Use dispatcher to select healthy backend
4. Forward INVITE via `t_relay()`

**Key Issue Encountered:**
- INVITE transactions were being cancelled with 408 Request Timeout ~26ms after receiving 100 Trying from Asterisk
- Issue persisted despite timer adjustments and configuration changes
- Suspected bug in Kamailio 5.5.4 transaction module
- **Resolution:** Upgrade to newer version (5.8.4) or consider OpenSIPS

### 4. Domain Validation (Door-Knocker Protection)

**Requirement:** Only allow requests for known, enabled domains.

**Database Schema:**
```sql
CREATE TABLE sip_domains (
    domain TEXT PRIMARY KEY,
    dispatcher_setid INTEGER NOT NULL,  -- Links to dispatcher set
    enabled INTEGER DEFAULT 1
);
```

**Logic:**
- Extract domain from Request-URI
- Query `sip_domains` table for enabled domain
- Block if not found or disabled
- Optional: Check R-URI domain matches To header domain

### 5. In-Dialog Request Handling

**Requirement:** Handle in-dialog requests (BYE, re-INVITE, etc.) using Record-Route headers.

**Logic:**
- Check for To-tag (indicates in-dialog)
- Use `loose_route()` to follow Record-Route
- Route to appropriate destination

## Routing Decision Flow

```
Request arrives
    ↓
Basic hygiene (Max-Forwards, sanity check)
    ↓
In-dialog? → Yes → Route via Record-Route
    ↓ No
Method allowed? → No → 405 Method Not Allowed
    ↓ Yes
CANCEL? → Yes → Match transaction, forward CANCEL
    ↓ No
OPTIONS/NOTIFY? → Yes → From Asterisk? → Yes → Route to endpoint
    ↓ No                                    ↓ No
REGISTER? → Yes → Track endpoint location → Continue to domain check
    ↓ No
Domain check → Valid? → No → Block
    ↓ Yes
Dispatcher selection → Healthy backend? → No → 503 Service Unavailable
    ↓ Yes
t_relay() to Asterisk
```

## Edge Cases and Solutions

### 1. Contact Header Parsing

**Problem:** Contact headers with angle brackets and complex parameters break URI parsing.

**Solution:** Use regex to extract IP and port:
```regex
@([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})  -- Extract IP
@IP:([0-9]+)                                       -- Extract port
```

### 2. Dispatcher Destination Matching

**Problem:** Destinations stored in various formats make matching difficult.

**Solution:** SQL query that handles all formats:
- `IP` (e.g., `10.0.1.100`)
- `IP:PORT` (e.g., `10.0.1.100:5060`)
- `sip:IP` (e.g., `sip:10.0.1.100`)
- `sip:IP:PORT` (e.g., `sip:10.0.1.100:5060`)

### 3. Request-URI Construction

**Problem:** Request-URI from Asterisk OPTIONS may be invalid (contains IP instead of domain).

**Solution:** Construct new Request-URI directly:
```
$du = "sip:" + username + "@" + endpoint_ip + ":" + endpoint_port;
$ru = $du;  // Set Request-URI to match destination
```

### 4. Endpoint Lookup Fallback

**Problem:** To header may have IP instead of domain, causing exact match to fail.

**Solution:** Two-tier lookup:
1. Try exact match: `user@domain`
2. Fallback to username-only: `user@%` (LIMIT 1)

## Transaction Handling

### Timer Configuration

**Recommended Settings:**
- `fr_timer`: 30 seconds (non-INVITE transactions)
- `fr_inv_timer`: 30 seconds (INVITE transactions)
- `restart_fr_on_each_reply`: 1 (reset timer on provisional responses)
- `retr_timer1`: 2000ms (initial retransmission)
- `retr_timer2`: 8000ms (maximum retransmission)

### Response Handling

**Provisional Responses (100-199):**
- Should reset transaction timers
- Should be forwarded to originator
- Keep transaction alive

**Final Responses (200-699):**
- Forward to originator
- Complete transaction

## Security Considerations

1. **Domain Validation:** Block requests for unknown domains
2. **Max-Forwards:** Limit hop count (default: 10)
3. **Sanity Check:** Validate SIP message format
4. **Scanner Blocking:** Drop known scanner User-Agents
5. **Domain Consistency:** Optional check that R-URI domain matches To header domain

## Logging Requirements

**Essential Logging:**
- All incoming requests (method, source, destination, Call-ID)
- INVITE requests specifically
- CANCEL requests
- OPTIONS/NOTIFY routing decisions
- Database lookup results
- Transaction failures
- Response handling

**Log Format Example:**
```
INFO: REQUEST: INVITE from 10.0.1.200:58396 to sip:402@domain.com (Call-ID: xxx)
INFO: Routing to sip:10.0.1.100 for domain=domain.com setid=10 method=INVITE
INFO: Response received: 100 Trying from 10.0.1.100
```

## Database Queries

### Endpoint Location Storage (REGISTER)
```sql
INSERT OR REPLACE INTO endpoint_locations (aor, contact_ip, contact_port, expires)
VALUES ('user@domain', '10.0.1.200', '58396', datetime(strftime('%s', 'now') + 3600, 'unixepoch'))
```

### Endpoint Location Lookup (OPTIONS/NOTIFY)
```sql
-- Exact match
SELECT contact_ip, contact_port FROM endpoint_locations
WHERE aor='user@domain' AND expires > datetime('now')

-- Username-only fallback
SELECT contact_ip, contact_port FROM endpoint_locations
WHERE aor LIKE 'user@%' AND expires > datetime('now') LIMIT 1
```

### Dispatcher Check (OPTIONS/NOTIFY)
```sql
SELECT COUNT(*) FROM dispatcher WHERE
    (destination = '10.0.1.100') OR
    (destination LIKE '10.0.1.100:%') OR
    (destination LIKE 'sip:10.0.1.100') OR
    (destination LIKE 'sip:10.0.1.100:%')
```

### Domain Validation
```sql
SELECT dispatcher_setid FROM sip_domains
WHERE domain='domain.com' AND enabled=1
```

## Key Differences: Kamailio vs OpenSIPS

### Similarities
- Both use similar routing script syntax
- Both have transaction module (`tm`)
- Both support SQLite via database modules
- Both have dispatcher module for load balancing
- Both use pseudo-variables for SIP header access

### Differences to Watch For
- Module names may differ slightly
- Function names may have different syntax
- Pseudo-variable syntax may vary
- Module parameters may have different names
- Some features may be implemented differently

## Testing Checklist

After OpenSIPS configuration, verify:

- [ ] Endpoints can REGISTER successfully
- [ ] Endpoint locations are stored in database
- [ ] OPTIONS from Asterisk route to endpoints
- [ ] NOTIFY from Asterisk route to endpoints
- [ ] INVITE requests route to Asterisk backends
- [ ] 100 Trying from Asterisk is forwarded to endpoints
- [ ] INVITE transactions complete successfully (no premature 408)
- [ ] In-dialog requests (BYE, re-INVITE) work correctly
- [ ] Domain validation blocks unknown domains
- [ ] Dispatcher health checks work correctly
- [ ] ACK for non-2xx responses handled correctly

## Known Issues from Kamailio Implementation

1. **INVITE 408 Timeout:** INVITE transactions were cancelled with 408 Request Timeout ~26ms after receiving 100 Trying. This was suspected to be a bug in Kamailio 5.5.4. Monitor for similar issues in OpenSIPS.

2. **Contact Header Parsing:** Complex Contact headers require regex extraction, not URI parsing.

3. **Dispatcher Matching:** Need flexible IP extraction from various destination formats.

4. **Request-URI Construction:** Must construct valid Request-URI directly, don't try to rewrite invalid ones.

## References

- **Troubleshooting Document:** `TROUBLESHOOTING-OPTIONS-ROUTING.md` - Contains detailed problem descriptions and solutions
- **Kamailio Config:** `config/kamailio.cfg.template` - Reference implementation (for logic, not syntax)
- **Database Schema:** `scripts/init-database.sh` - SQLite database structure

## Next Steps for OpenSIPS

1. Review OpenSIPS module documentation for equivalents:
   - Transaction Module (`tm`)
   - Dispatcher Module
   - SQL Operations Module
   - Database SQLite Module

2. Translate routing logic to OpenSIPS syntax:
   - Request routing
   - Response handling
   - Database queries
   - Pseudo-variables

3. Test each component:
   - REGISTER tracking
   - OPTIONS routing
   - INVITE routing
   - Transaction handling

4. Monitor for similar issues:
   - Premature transaction timeouts
   - Response forwarding problems
   - Transaction state issues

