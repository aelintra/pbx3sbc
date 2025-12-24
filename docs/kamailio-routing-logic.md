# Kamailio Routing Logic

This document explains how Kamailio routes SIP requests, with special focus on handling OPTIONS requests from Asterisk backends to endpoints.

## Overview

Kamailio acts as a SIP edge router that:
1. Validates incoming requests against known domains
2. Routes requests to appropriate Asterisk backends using the dispatcher module
3. Tracks endpoint locations during registration
4. Routes OPTIONS health checks from Asterisk back to endpoints

## Request Flow

### 1. Initial Request Processing

All incoming SIP requests go through `request_route` which performs:
- **Basic hygiene checks**: Max-Forwards header validation, sanity checks
- **Scanner detection**: Blocks known SIP scanners
- **In-dialog handling**: Routes requests with To-tags through dialog handling
- **Method validation**: Only allows REGISTER, INVITE, ACK, BYE, CANCEL, OPTIONS

### 2. Domain Validation

After initial checks, requests go to `route[DOMAIN_CHECK]`:
- Extracts domain from Request-URI
- Validates domain consistency (R-URI must match To header domain)
- Queries database to find dispatcher set ID for the domain
- Blocks requests for unknown or disabled domains (door-knocker protection)

### 3. Dispatcher Routing

Valid requests go to `route[TO_DISPATCHER]`:
- Uses dispatcher module to select a healthy Asterisk backend
- Dispatcher maintains in-memory cache of backend destinations
- Only healthy backends (passing OPTIONS health checks) are selected
- Uses round-robin algorithm (algorithm "4") for load distribution
- Records route for in-dialog requests
- Relays request to selected backend

## Special Handling: REGISTER Requests

### Endpoint Location Tracking

When a REGISTER request arrives:

1. **Extract endpoint information**:
   - AoR (Address of Record): `user@domain` from To header
   - Contact IP: From Contact header's host
   - Contact Port: From Contact header's port (defaults to 5060)
   - Expires: From Expires header (defaults to 3600 seconds)

2. **Store in database**:
   - Table: `endpoint_locations`
   - Stores: `aor`, `contact_ip`, `contact_port`, `expires`
   - Uses `INSERT OR REPLACE` to update existing entries
   - Expiration time calculated as: `current_time + expires_seconds`

3. **Continue normal routing**:
   - REGISTER is then forwarded to Asterisk backend via dispatcher
   - Asterisk handles the actual registration

**Why we track this:**
- Asterisk needs to send OPTIONS health checks to endpoints
- These OPTIONS requests come back through Kamailio
- We need to know the endpoint's actual IP/port to route them correctly

## Special Handling: OPTIONS Requests from Asterisk

### The Problem

Asterisk periodically sends OPTIONS requests to registered endpoints for:
- **Health checking**: Verify endpoint is still reachable
- **NAT keepalive**: Keep NAT pinholes open

These OPTIONS requests:
- Originate from Asterisk backend (dispatcher destination)
- Are addressed to the endpoint's AoR
- Need to be routed to the endpoint's actual IP/port (not Kamailio's IP)

### The Solution

When an OPTIONS request arrives:

1. **Detect source**:
   - Check if request is from a known dispatcher destination using `ds_is_from_list()`
   - If yes, this is an OPTIONS from Asterisk to an endpoint

2. **Lookup endpoint location**:
   - Extract AoR from To header: `user@domain`
   - Query `endpoint_locations` table for matching entry
   - Check that entry hasn't expired: `expires > datetime('now')`

3. **Route to endpoint**:
   - Construct destination URI: `sip:user@endpoint_ip:endpoint_port`
   - Set `$du` variable with endpoint destination
   - Relay request to endpoint using `route(RELAY)`

4. **Fallback**:
   - If endpoint location not found in database
   - Reply with stateless 200 OK
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
aor: H5CCvFpY@pdhlocal.vcloudpbx.com
contact_ip: 192.168.1.138
contact_port: 45891
expires: 2024-12-23 21:45:00
```

## Complete Flow Example

### Registration Flow

```
1. Endpoint sends REGISTER
   Contact: sip:user@192.168.1.138:45891
   To: sip:user@pdhlocal.vcloudpbx.com
   ↓
2. Kamailio extracts endpoint info
   - AoR: user@pdhlocal.vcloudpbx.com
   - IP: 192.168.1.138
   - Port: 45891
   ↓
3. Kamailio stores in endpoint_locations table
   ↓
4. Kamailio looks up domain → dispatcher set ID
   ↓
5. Kamailio selects healthy Asterisk backend
   ↓
6. Kamailio forwards REGISTER to Asterisk
   ↓
7. Asterisk processes registration
```

### OPTIONS Health Check Flow

```
1. Asterisk sends OPTIONS to endpoint
   From: Asterisk (192.168.1.205:5060)
   To: sip:user@pdhlocal.vcloudpbx.com
   ↓
2. Kamailio receives OPTIONS
   - Detects source is dispatcher destination (Asterisk)
   ↓
3. Kamailio extracts AoR from To header
   - AoR: user@pdhlocal.vcloudpbx.com
   ↓
4. Kamailio looks up endpoint location in database
   - Finds: 192.168.1.138:45891
   ↓
5. Kamailio routes OPTIONS to endpoint
   $du = sip:user@192.168.1.138:45891
   ↓
6. Endpoint receives OPTIONS
   ↓
7. Endpoint replies with 200 OK
   ↓
8. NAT pinhole stays open
   Health check succeeds
```

## Benefits

1. **NAT Traversal**: OPTIONS keep NAT pinholes open, allowing incoming calls
2. **Health Monitoring**: Asterisk can detect when endpoints go offline
3. **Transparent Routing**: Endpoints don't need to know about Kamailio's presence
4. **Scalability**: Database lookup is fast, supports many endpoints

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
sudo journalctl -u kamailio -f | grep OPTIONS
```

**Look for:**
- "Routing OPTIONS from Asterisk ... to endpoint ..." (success)
- "OPTIONS from Asterisk ... endpoint location not found" (failure)

**Verify database:**
```bash
sqlite3 /var/lib/kamailio/routing.db "SELECT * FROM endpoint_locations;"
```

## Configuration Parameters

### Dispatcher Module

- `ds_ping_method`: OPTIONS (health check method)
- `ds_ping_interval`: 30 (seconds between health checks)
- `ds_probing_threshold`: 2 (consecutive failures before marking down)
- `ds_inactive_threshold`: 2 (consecutive successes before marking up)

### Endpoint Location Tracking

- Expiration: Based on Expires header in REGISTER (default 3600 seconds)
- Cleanup: Expired entries are automatically ignored (not deleted)
- Updates: New REGISTER requests update existing entries

## Future Enhancements

Potential improvements:
1. **Automatic cleanup**: Periodic job to delete expired entries
2. **Multiple contacts**: Support for GRUU (Globally Routable User Agent URIs)
3. **Registration state**: Use registrar module for more robust tracking
4. **Statistics**: Track OPTIONS success/failure rates

