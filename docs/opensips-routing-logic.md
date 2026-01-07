# OpenSIPS Routing Logic

This document explains how OpenSIPS routes SIP requests, with special focus on handling OPTIONS requests from Asterisk backends to endpoints, PRACK handling for 100rel support, and NAT traversal.

## Overview

OpenSIPS acts as a SIP edge router that:
1. Validates incoming requests against known domains
2. Routes requests to appropriate Asterisk backends using the dispatcher module
3. Tracks endpoint locations during registration
4. Routes OPTIONS health checks from Asterisk back to endpoints
5. Handles PRACK requests for 100rel (reliable provisional responses) support
6. Performs NAT traversal fixes for endpoints behind NAT

## Request Flow

### 1. Initial Request Processing

All incoming SIP requests go through `route` which performs:
- **Basic hygiene checks**: Max-Forwards header validation
- **Scanner detection**: Blocks known SIP scanners (sipvicious, friendly-scanner, sipcli, nmap)
- **In-dialog handling**: Routes requests with To-tags through `route[WITHINDLG]`
- **Method validation**: Allows REGISTER, INVITE, ACK, BYE, CANCEL, OPTIONS, NOTIFY, SUBSCRIBE, PRACK

### 2. Domain Validation

After initial checks, requests go to `route[DOMAIN_CHECK]`:
- Checks if Request-URI domain is an IP address (for endpoint routing)
- If IP address, performs endpoint lookup and routes directly to endpoint
- Otherwise, extracts domain from Request-URI
- Validates domain consistency (R-URI must match To header domain)
- Queries database to find dispatcher set ID for the domain
- Blocks requests for unknown or disabled domains (door-knocker protection)

### 3. Dispatcher Routing

Valid requests go to `route[TO_DISPATCHER]`:
- Uses dispatcher module to select a healthy Asterisk backend
- Dispatcher maintains in-memory cache of backend destinations
- Only healthy backends (passing OPTIONS health checks) are selected
- Uses round-robin algorithm (algorithm "4") for load distribution
- Records route for in-dialog requests using `record_route()`
- Arms failure route for transaction error handling
- Relays request to selected backend using `t_relay()`

## Special Handling: REGISTER Requests

### Endpoint Location Tracking

When a REGISTER request arrives:

1. **Extract endpoint information**:
   - AoR (Address of Record): `user@domain` from To header
   - Contact IP: From source IP (`$si`) - more reliable than Contact header for NAT scenarios
   - Contact Port: From source port (`$sp`) - defaults to 5060 if missing
   - Expires: From Expires header (defaults to 3600 seconds)

2. **Fix NAT in REGISTER**:
   - Calls `fix_nated_register()` to fix Contact header for NAT traversal
   - Ensures Asterisk receives correct public IP information

3. **Store in database**:
   - Table: `endpoint_locations`
   - Stores: `aor`, `contact_ip`, `contact_port`, `expires`
   - Uses `INSERT OR REPLACE` to update existing entries
   - Expiration time calculated as: `datetime('now', '+N seconds')` using SQLite syntax

4. **Continue normal routing**:
   - REGISTER is then forwarded to Asterisk backend via dispatcher
   - Asterisk handles the actual registration

**Why we track this:**
- Asterisk needs to send OPTIONS health checks to endpoints
- These OPTIONS requests come back through Kamailio
- We need to know the endpoint's actual IP/port to route them correctly

## Special Handling: OPTIONS and NOTIFY Requests from Asterisk

### The Problem

Asterisk periodically sends OPTIONS and NOTIFY requests to registered endpoints for:
- **Health checking**: Verify endpoint is still reachable (OPTIONS)
- **NAT keepalive**: Keep NAT pinholes open (OPTIONS)
- **Event notifications**: Message waiting indicators, call state changes (NOTIFY)

These requests:
- Originate from Asterisk backend (dispatcher destination)
- Are addressed to the endpoint's AoR or IP address
- Need to be routed to the endpoint's actual IP/port (not OpenSIPS's IP)

### The Solution

When an OPTIONS or NOTIFY request arrives:

1. **Detect endpoint routing need**:
   - Check if Request-URI looks like an endpoint (has username and IP address)
   - If Request-URI domain matches IP pattern: `^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}`
   - This indicates routing to an endpoint, not to Asterisk

2. **Lookup endpoint location**:
   - Extract username from To header or Request-URI
   - Use `route[ENDPOINT_LOOKUP]` helper route
   - Tries exact AoR match first, then username-only match
   - Query `endpoint_locations` table for matching entry
   - Check that entry hasn't expired: `expires > datetime('now')`

3. **Route to endpoint**:
   - Use `route[BUILD_ENDPOINT_URI]` to construct destination URI
   - Sets `$du` (destination URI) and `$ru` (Request-URI) correctly
   - Handles domain fallback logic for Request-URI
   - Relay request to endpoint using `route(RELAY)`

4. **Fallback**:
   - If endpoint location not found in database
   - For OPTIONS: Reply with stateless 200 OK
   - For NOTIFY: Try to extract IP from Contact header, otherwise reply 404
   - Health check works, but NAT pinhole may close
   - Logs warning for troubleshooting

## Database Schema

### endpoint_locations Table

```sql
CREATE TABLE endpoint_locations (
    aor TEXT PRIMARY KEY,           -- Address of Record: user@domain
    contact_ip TEXT NOT NULL,       -- Endpoint's actual IP address
    contact_port TEXT NOT NULL,     -- Endpoint's port (usually 5060)
    expires TEXT NOT NULL           -- Expiration time (SQLite datetime)
);

CREATE INDEX idx_endpoint_locations_expires ON endpoint_locations(expires);
```

**Example data:**
```
aor: H5CCvFpY@example.com
contact_ip: 10.0.1.200
contact_port: 45891
expires: 2024-12-23 21:45:00
```

## Complete Flow Example

### Registration Flow

```
1. Endpoint sends REGISTER
   Contact: sip:user@10.0.1.200:45891
   To: sip:user@example.com
   Source: 74.83.23.44:5060 (public NAT IP)
   ↓
2. OpenSIPS extracts endpoint info
   - AoR: user@example.com
   - IP: 74.83.23.44 (from source, not Contact header)
   - Port: 5060 (from source port)
   ↓
3. OpenSIPS fixes NAT: fix_nated_register()
   - Updates Contact header with public IP
   ↓
4. OpenSIPS stores in endpoint_locations table
   ↓
5. OpenSIPS looks up domain → dispatcher set ID
   ↓
6. OpenSIPS selects healthy Asterisk backend
   ↓
7. OpenSIPS forwards REGISTER to Asterisk
   ↓
8. Asterisk processes registration
```

### OPTIONS Health Check Flow

```
1. Asterisk sends OPTIONS to endpoint
   From: Asterisk (52.4.93.21:5060)
   To: sip:44107@100.31.156.173 (or sip:44107@example.com)
   Request-URI: sip:44107@192.168.1.138:52596 (endpoint IP)
   ↓
2. OpenSIPS receives OPTIONS
   - Detects Request-URI looks like endpoint (IP address)
   ↓
3. OpenSIPS extracts username from Request-URI or To header
   - Username: 44107
   ↓
4. OpenSIPS looks up endpoint location in database (route[ENDPOINT_LOOKUP])
   - Finds: 74.83.23.44:5060 (public NAT IP)
   ↓
5. OpenSIPS builds destination URI (route[BUILD_ENDPOINT_URI])
   $du = sip:44107@74.83.23.44:5060
   $ru = sip:44107@example.com (with domain fallback)
   ↓
6. OpenSIPS routes OPTIONS to endpoint (route[RELAY])
   ↓
7. Endpoint receives OPTIONS
   ↓
8. Endpoint replies with 200 OK
   - OpenSIPS fixes NAT in response: fix_nated_contact()
   ↓
9. NAT pinhole stays open
   Health check succeeds
```

## Special Handling: PRACK and 100rel Support

### The Problem

Some endpoints (like snom phones) use 100rel (RFC 3262) for reliable provisional responses:
- Endpoint sends 180 Ringing with `Require: 100rel` and `RSeq: 1`
- Expects PRACK (Provisional Response ACKnowledgment) in response
- If PRACK doesn't arrive, endpoint retransmits 180 Ringing
- Without PRACK handling, calls timeout and fail

### The Solution

OpenSIPS now handles PRACK requests:

1. **PRACK in allowed methods**: Added to method validation
2. **PRACK in WITHINDLG route**: Handled similar to ACK with transaction matching
3. **PRACK in RELAY route**: NAT IP fixing for endpoints behind NAT
4. **Transaction-based routing**: Uses `t_check_trans()` and `t_relay()` for proper forwarding

This enables:
- 100rel support for reliable provisional responses
- Proper call completion when endpoints require PRACK
- NAT traversal for PRACK requests to endpoints behind NAT

## Special Handling: NAT Traversal

### The Problem

Endpoints behind NAT send:
- Contact headers with private IPs (e.g., `192.168.1.138:52596`)
- SDP with private IPs in connection addresses
- Asterisk can't reach these private IPs for RTP

### The Solution

OpenSIPS uses the `nathelper` module to fix NAT issues:

1. **In responses (onreply_route)**:
   - `fix_nated_contact()`: Fixes Contact headers to use public NAT IP
   - `fix_nated_sdp("rewrite-media-ip")`: Fixes SDP media IP addresses (c= line)
   - Ensures Asterisk receives public IPs for RTP establishment

2. **In REGISTER requests**:
   - `fix_nated_register()`: Fixes Contact header before forwarding to Asterisk
   - Ensures Asterisk tracks correct public IP for endpoint

3. **In-dialog requests (ACK, PRACK, BYE, NOTIFY)**:
   - NAT IP lookup from database for endpoints behind NAT
   - Updates destination URI to use public NAT IP from database

## Benefits

1. **NAT Traversal**: OPTIONS keep NAT pinholes open, allowing incoming calls
2. **Health Monitoring**: Asterisk can detect when endpoints go offline
3. **Transparent Routing**: Endpoints don't need to know about OpenSIPS's presence
4. **Scalability**: Database lookup is fast, supports many endpoints
5. **100rel Support**: PRACK handling enables reliable provisional responses
6. **Audio Quality**: NAT fixing ensures RTP establishes correctly with proper IP addresses

## Troubleshooting

### Endpoint becomes unavailable after registration

**Symptoms:**
- Endpoint registers successfully
- Shortly after, Asterisk marks it as unreachable

**Possible causes:**
1. Endpoint location not stored in database
   - Check: `SELECT * FROM endpoint_locations WHERE aor='user@domain';`
   - Solution: Verify REGISTER is being processed correctly

2. Endpoint location expired
   - Check: `SELECT * FROM endpoint_locations WHERE expires > datetime('now');`
   - Solution: Endpoint needs to re-register before expiration

3. OPTIONS not being routed
   - Check Kamailio logs for: "OPTIONS from Asterisk ... endpoint location not found"
   - Solution: Verify database lookup is working

### OPTIONS not reaching endpoint

**Check logs:**
```bash
sudo journalctl -u opensips -f | grep OPTIONS
```

**Look for:**
- "Routing OPTIONS from Asterisk ... to endpoint ..." (success)
- "OPTIONS/NOTIFY from Asterisk ... endpoint location not found" (failure)
- "ENDPOINT_LOOKUP: Success - IP=..." (endpoint found)

**Verify database:**
```bash
sqlite3 /etc/opensips/opensips.db "SELECT * FROM endpoint_locations;"
```

## Configuration Parameters

### Dispatcher Module

- `ds_ping_method`: OPTIONS (health check method)
- `ds_ping_interval`: 30 (seconds between health checks)
- `ds_probing_threshold`: 2 (consecutive failures before marking down)
- `options_reply_codes`: 200 (acceptable response codes for health checks)

### NAT Helper Module

- `fix_nated_contact()`: Fixes Contact headers in responses
- `fix_nated_sdp("rewrite-media-ip")`: Fixes SDP media IP addresses
- `fix_nated_register()`: Fixes Contact headers in REGISTER requests

### Endpoint Location Tracking

- Expiration: Based on Expires header in REGISTER (default 3600 seconds)
- Cleanup: Expired entries are automatically ignored (not deleted)
- Updates: New REGISTER requests update existing entries

## Database Location

The routing database is located at:
- `/etc/opensips/opensips.db` (SQLite database)

This database contains:
- `sip_domains`: Domain to dispatcher set mappings
- `dispatcher`: Asterisk backend destinations
- `endpoint_locations`: Endpoint IP/port tracking
- Standard OpenSIPS tables (version, location, etc.)

## Future Enhancements

Potential improvements:
1. **Automatic cleanup**: Periodic job to delete expired entries
2. **Multiple contacts**: Support for GRUU (Globally Routable User Agent URIs)
3. **Registration state**: Use registrar module for more robust tracking
4. **Statistics**: Track OPTIONS success/failure rates
5. **RTPProxy integration**: For more advanced NAT traversal scenarios

