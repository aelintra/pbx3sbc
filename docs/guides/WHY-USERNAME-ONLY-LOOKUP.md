# Why Username-Only Lookup is Needed

**Purpose:** This document explains the fundamental reasons why username-only lookups are necessary in the PBX3sbc architecture.

**Date:** January 2026  
**Related:** 
- [MULTIPLE-DOMAINS-SAME-USERNAME.md](MULTIPLE-DOMAINS-SAME-USERNAME.md) - Required solution for multi-tenant deployments
- [USRLOC-MIGRATION-PLAN.md](USRLOC-MIGRATION-PLAN.md) - Implementation details

---

## The Core Problem

**Asterisk sends SIP requests to endpoints with IP addresses in the Request-URI instead of domain names.**

When this happens, we have:
- ✅ Username (e.g., `401`)
- ❌ Domain (we have an IP like `192.168.1.138`, not a domain like `example.com`)

We need to find where endpoint `401` is registered, but we can't use a normal domain-based lookup because we don't have the domain.

---

## Why Does Asterisk Send IPs Instead of Domains?

### 1. Asterisk's Internal Routing

Asterisk may construct Request-URIs based on:
- **Contact headers from REGISTER requests** - If the endpoint registered with an IP in the Contact header, Asterisk may use that IP
- **Internal routing tables** - Asterisk may maintain its own routing that uses IPs
- **NAT scenarios** - Asterisk may see the endpoint's public IP, not the domain

**Example:**
```
Endpoint registers: REGISTER sip:example.com
Contact: <sip:401@192.168.1.138:5060>

Asterisk stores: 401 → 192.168.1.138:5060

Later, Asterisk sends: INVITE sip:401@192.168.1.138:5060
```

### 2. Health Checks and Keepalives

Asterisk sends periodic OPTIONS requests to endpoints for:
- **Health checking** - Verify endpoint is still reachable
- **NAT keepalive** - Keep NAT pinholes open

These requests are often sent to the IP address that Asterisk knows about, not the domain.

**Example:**
```
Asterisk sends: OPTIONS sip:401@192.168.1.138:5060
```

### 3. Event Notifications

Asterisk sends NOTIFY requests for:
- Message waiting indicators
- Call state changes
- Presence updates

These also use IP addresses when the domain isn't available.

---

## Real-World Scenarios

### Scenario 1: INVITE from Asterisk to Endpoint

**What Happens:**
1. User dials extension `401` on Asterisk
2. Asterisk looks up where `401` is registered
3. Asterisk finds: `401` is at `192.168.1.138:5060` (from Contact header)
4. Asterisk sends: `INVITE sip:401@192.168.1.138:5060`

**The Problem:**
- Request-URI: `sip:401@192.168.1.138:5060`
- Domain part (`192.168.1.138`) is an IP, not a domain name
- We can't do: `lookup("location", "sip:401@192.168.1.138")` - that's not a valid AoR
- We need: `lookup("location", "sip:401@*")` - find `401` in any domain

**Code Location:** `config/opensips.cfg.template` lines 322-355

```opensips
# Check if Request-URI looks like an endpoint (has username and IP address, not domain)
if ($rd =~ "^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}") {
    # Request-URI domain is an IP, not a domain name
    # Extract username from Request-URI
    $var(endpoint_user) = $rU;  # Gets "401"
    
    # Use username-only lookup (no domain available)
    $var(lookup_user) = $var(endpoint_user);
    $var(lookup_aor) = "";  # Empty - triggers username-only lookup
    route(ENDPOINT_LOOKUP);
}
```

### Scenario 2: OPTIONS Health Check from Asterisk

**What Happens:**
1. Asterisk periodically sends OPTIONS to check if endpoint is alive
2. Asterisk uses the IP it knows about: `192.168.1.138`
3. Asterisk sends: `OPTIONS sip:401@192.168.1.138:5060`

**The Problem:**
- Request-URI: `sip:401@192.168.1.138:5060`
- To header: `<sip:401@192.168.1.138>` (also has IP)
- We need to route this to the endpoint's actual location
- But we only have the username `401`, not the domain

**Code Location:** `config/opensips.cfg.template` lines 170-277

```opensips
# Check if Request-URI looks like an endpoint (has username and IP address)
if ($rd =~ "^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}") {
    # Extract username
    $var(endpoint_user) = $tU;  # From To header
    if ($var(endpoint_user) == "") {
        $var(endpoint_user) = $rU;  # Fallback to Request-URI
    }
    
    # Try to get domain from To header
    $var(to_domain) = $(tu{uri.domain});
    if ($var(to_domain) =~ "^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}") {
        # To header also has IP, not domain - use username-only lookup
        $var(endpoint_aor) = "";
    }
    
    # Username-only lookup
    route(ENDPOINT_LOOKUP);
}
```

### Scenario 3: NOTIFY from Asterisk

**What Happens:**
1. Asterisk sends NOTIFY for message waiting indicator
2. Request-URI: `sip:401@192.168.1.138:5060`
3. Same problem - IP instead of domain

---

## Why Not Just Use the IP from Request-URI?

**Question:** If the Request-URI already has an IP (`192.168.1.138`), why not just route to that IP?

**Answer:** Because that IP might not be the endpoint's current location!

### Reasons:

1. **NAT Traversal**
   - The IP in Request-URI might be the endpoint's public NAT IP
   - But we need to route to the endpoint's actual registered IP/port
   - The endpoint may have re-registered with a different IP/port

2. **Endpoint Mobility**
   - Endpoint may have moved to a different network
   - Endpoint may have re-registered with a new IP
   - We need the current registration, not the old IP from Request-URI

3. **Port Information**
   - Request-URI might have port `5060`
   - But endpoint registered with port `45891` (ephemeral port)
   - We need the actual registered port

4. **Contact URI Matching**
   - Some endpoints (like Snom) are picky about Request-URI matching Contact URI
   - We need to use the exact Contact URI from registration
   - Not a constructed URI from Request-URI IP

**Example:**
```
Asterisk sends: INVITE sip:401@192.168.1.138:5060

But endpoint registered as:
  AoR: 401@example.com
  Contact: sip:401@10.0.1.100:45891
  Registered IP: 10.0.1.100:45891

We need to route to: sip:401@10.0.1.100:45891
NOT to: sip:401@192.168.1.138:5060
```

---

## The Architecture Flow

### Normal Flow (Endpoint → Asterisk)

```
1. Endpoint registers: REGISTER sip:example.com
   Contact: <sip:401@10.0.1.100:45891>
   
2. OpenSIPS stores: 401@example.com → 10.0.1.100:45891
   
3. OpenSIPS forwards REGISTER to Asterisk
   
4. Asterisk processes registration
```

**No username-only lookup needed** - we have the full AoR (`401@example.com`).

### Reverse Flow (Asterisk → Endpoint)

```
1. Asterisk sends: INVITE sip:401@192.168.1.138:5060
   (IP in Request-URI, not domain)
   
2. OpenSIPS receives request
   
3. OpenSIPS detects: Request-URI domain is IP (not domain name)
   
4. OpenSIPS extracts: username = "401"
   
5. OpenSIPS needs to find: Where is "401" registered?
   
6. Problem: We don't have the domain!
   - Request-URI has: 192.168.1.138 (IP)
   - To header might have: 192.168.1.138 (IP)
   - We need: example.com (domain)
   
7. Solution: Username-only lookup
   - Search for: "401" in any domain
   - Find: 401@example.com → 10.0.1.100:45891
   - Route to: sip:401@10.0.1.100:45891
```

**Username-only lookup IS needed** - we only have the username, not the domain.

---

## Why This Happens in Our Architecture

### Our Architecture

```
SIP Endpoints → OpenSIPS SBC → Asterisk Backends
```

**Key Point:** OpenSIPS is a proxy/edge router, not the registrar.

1. **Endpoints register through OpenSIPS to Asterisk**
   - OpenSIPS tracks endpoint locations (for routing back)
   - Asterisk is the actual registrar

2. **Asterisk sends requests back to endpoints**
   - Asterisk may not know about OpenSIPS's domain structure
   - Asterisk may use IPs from Contact headers
   - Asterisk may construct Request-URIs with IPs

3. **OpenSIPS needs to route these requests**
   - But Request-URI has IP, not domain
   - We need username-only lookup to find the endpoint

### Why Not Fix Asterisk?

**Question:** Why not configure Asterisk to use domains instead of IPs?

**Answer:** 
- Asterisk's behavior depends on how it was configured
- Asterisk may be using IPs for performance (no DNS lookup)
- Asterisk may be using IPs from Contact headers (NAT scenarios)
- We can't always control Asterisk's Request-URI construction
- **It's more robust to handle both cases** (domain and IP)

---

## Detection Logic

The code detects when username-only lookup is needed:

```opensips
# Check if Request-URI domain is an IP address
if ($rd =~ "^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}") {
    # Domain is an IP, not a domain name
    # Need username-only lookup
    $var(endpoint_user) = $rU;
    $var(lookup_aor) = "";  # Empty = username-only lookup
    route(ENDPOINT_LOOKUP);
}
```

**Pattern:** `^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}`
- Matches: `192.168.1.138`, `10.0.1.100`, etc.
- Does NOT match: `example.com`, `pbx.test.com`, etc.

---

## Summary

### Why Username-Only Lookup is Needed

1. **Asterisk sends requests with IPs in Request-URI**
   - Asterisk may not know or use domain names
   - Asterisk may use IPs from Contact headers
   - Asterisk may use IPs for performance

2. **We need to route to endpoints**
   - But Request-URI has IP, not domain
   - We can't do domain-based lookup
   - We need username-only lookup

3. **We can't use the IP from Request-URI**
   - IP might be outdated (endpoint moved)
   - Port might be wrong (ephemeral ports)
   - Need current registration information

4. **Our architecture requires it**
   - OpenSIPS is proxy, Asterisk is registrar
   - Asterisk sends requests back through OpenSIPS
   - OpenSIPS needs to route based on current registrations

### The Solution

**⚠️ IMPORTANT:** For multi-tenant deployments, wildcard lookup (`@*`) is **UNACCEPTABLE** because it returns "first match" which may route to the wrong customer.

**Required Solution:** Determine domain from source IP (which Asterisk sent request), then use domain-specific lookup:
```opensips
# 1. Determine domain from source IP (via dispatcher → domain mapping)
# 2. Use domain-specific lookup
lookup("location", "uri", "sip:401@tenant-a.com")
```

This ensures routing to the correct customer/domain.

**See:** [MULTIPLE-DOMAINS-SAME-USERNAME.md](MULTIPLE-DOMAINS-SAME-USERNAME.md) for detailed solution and [USRLOC-MIGRATION-PLAN.md](USRLOC-MIGRATION-PLAN.md) for implementation.

---

**Status:** ✅ Documented  
**Next Steps:** See [MULTIPLE-DOMAINS-SAME-USERNAME.md](MULTIPLE-DOMAINS-SAME-USERNAME.md) for the required solution and [USRLOC-MIGRATION-PLAN.md](USRLOC-MIGRATION-PLAN.md) for implementation details
