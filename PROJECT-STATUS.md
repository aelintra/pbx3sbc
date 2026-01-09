# PBX3sbc Project Status

**Last Updated:** January 2026  
**Current Branch:** `fulldb`  
**Status:** ✅ Basic functionality working, refactoring complete

## Recent Work Summary

### Latest Commits
1. **"merged the sercloud work - running OK"** (6c1a25f) - Most recent merge
2. **"Fix NOTIFY routing for endpoints behind NAT"** (3a9790f) - Critical fix for NOTIFY requests
3. **"Code cleanup: Extract helper routes and reduce duplication"** (4bf8d69)
4. **"Fix ACK/BYE routing: Only update NAT IP for private IPs"** (0eb1cb8, 9e8cd3e)

### Current Status
- ✅ **OpenSIPS implementation complete**
- ✅ **All refactoring complete**
- ✅ **Basic functionality working**
- ✅ **Using simple SQL approach with endpoint_locations table** (see SIMPLIFIED-APPROACH.md)

## Key Fixes Implemented

### 1. NOTIFY Routing Fix (Commit: 3a9790f)
**Issue:** NOTIFY requests from Asterisk to endpoints behind NAT were failing with null destination URI (`$du = <null>`), causing `t_relay()` failures.

**Root Cause:** 
- NOTIFY requests are in-dialog (have To-tag) and go through `route[WITHINDLG]` → `loose_route()` → `route[RELAY]`
- When NOTIFY has a private IP in Request-URI (e.g., `sip:40005@192.168.1.232:5060`), it needs to be routed to the endpoint's public NAT IP
- The NAT IP fix in `route[RELAY]` was only applied to ACK and BYE methods, not NOTIFY

**Solution:** Added NOTIFY to the NAT IP fix in `route[RELAY]` (line 756 in `config/opensips.cfg.template`)

**Files Modified:**
- `config/opensips.cfg.template` - Added NOTIFY to `is_method("ACK|BYE|NOTIFY")` check
- `OPENSIPS-MIGRATION-KNOWLEDGE.md` - Documented the fix and root cause

**Location:** See `route[RELAY]` in `config/opensips.cfg.template` (lines 744-801)

### 2. ACK/BYE Routing Fix
**Issue:** ACK/BYE routing was incorrectly modifying destination URI for public IPs/domains (Asterisk backends).

**Solution:** Added private IP check using `route[CHECK_PRIVATE_IP]` to only update NAT IP for endpoints behind NAT, not for Asterisk backends.

## Current Configuration

### Main Files
- **OpenSIPS Config:** `config/opensips.cfg.template` (883 lines)
- **Database Schema:** `scripts/init-database.sh`

### Key Features Working
- ✅ Domain-based routing with multi-tenancy
- ✅ Health-aware routing via dispatcher module
- ✅ Endpoint registration tracking (`endpoint_locations` table)
- ✅ Bidirectional routing:
  - Endpoints → Asterisk (via dispatcher)
  - Asterisk → Endpoints (OPTIONS/NOTIFY using endpoint_locations)
- ✅ NAT traversal for in-dialog requests (ACK/BYE/NOTIFY)
- ✅ Attack mitigation (drops known scanners)

### Database Schema
- `sip_domains` - Domain → dispatcher_setid mapping
- `dispatcher` - Asterisk backend destinations (OpenSIPS 3.6 version 9 schema)
- `endpoint_locations` - Registered endpoint IP/port for routing back to endpoints

## Current Branch Context

**Branch:** `fulldb`  
**Previous Branch:** `sercloud` (merged)

**Next Steps:**
- System is stable and working with SQL-based endpoint tracking

## Documentation References

### For NOTIFY Routing
- **Fix Location:** `config/opensips.cfg.template` - `route[RELAY]` (line 756)
- **Documentation:** `OPENSIPS-MIGRATION-KNOWLEDGE.md` - Section "Error: NOTIFY requests failing with null destination URI" (line 506)

### For NAT Traversal
- **Helper Route:** `route[CHECK_PRIVATE_IP]` (lines 728-742)
- **Helper Route:** `route[ENDPOINT_LOOKUP]` (lines 553-636)
- **Helper Route:** `route[BUILD_ENDPOINT_URI]` (lines 688-723)

### For Configuration Reference
- **OpenSIPS Configuration:** `config/opensips.cfg.template`
- **Database Setup:** `scripts/init-database.sh`
- **Installation:** `install.sh`

## Quick Reference for New Chat Sessions

### What We've Been Working On
- NAT traversal for in-dialog requests (ACK/BYE/NOTIFY)
- Endpoint location tracking and routing
- Health-aware routing with dispatcher module
- Control panel integration and domain management

### Recent Fixes
- NOTIFY routing for endpoints behind NAT (commit 3a9790f)
- ACK/BYE routing to only update NAT IP for private IPs
- Code cleanup and helper route extraction

### Current State
- ✅ All refactoring complete
- ✅ Basic functionality working
- ✅ Using SQL-based endpoint tracking (endpoint_locations table)

### Key Files to Reference
- `config/opensips.cfg.template` - Main OpenSIPS configuration
- `scripts/init-database.sh` - Database schema initialization
- `SIMPLIFIED-APPROACH.md` - Current architecture approach

## System Architecture

```
SIP Endpoints → OpenSIPS SBC → Asterisk Backends
                    ↓
            MySQL Database
```

**Key Points:**
- OpenSIPS acts as Session Border Controller (SBC)
- MySQL provides routing database
- RTP bypasses SBC (direct endpoint ↔ Asterisk)
- Endpoint locations tracked for bidirectional routing
- Control panel for web-based management

## Future Enhancements

### Containerization
**Status:** Planned  
**Priority:** Medium (after local testing and AWS deployment validation)

Containerize OpenSIPS deployment for easier AWS/cloud deployments:

- **Rationale:**
  - OpenSIPS uses minimal ports (5060/udp, 5060/tcp, 5061/tcp, 8888/tcp) - easy to containerize
  - Stateless routing logic (database-backed) - perfect for containers
  - Enables horizontal scaling and clean deployments
  - Works well with AWS ECS/Fargate, Kubernetes
  - **Note:** OpenSIPS has an official Docker image available - containerization is a popular deployment method

- **Resources:**
  - Official Docker repository: https://github.com/OpenSIPS/docker-opensips
  - Docker Hub: https://hub.docker.com/r/opensips/opensips
  - Supports OpenSIPS 3.4+ with configurable versions
  - Can install extra modules (e.g., MySQL module)

- **Approach:**
  - Consider using official OpenSIPS Docker image as base
  - Multi-container architecture (OpenSIPS + Control Panel)
  - Use RDS MySQL (managed, persistent)
  - Host networking mode for SIP UDP (better NAT traversal)
  - Configuration via environment variables and secrets
  - Dockerfile/Docker Compose setup

- **Prerequisites:**
  - Complete local testing with phones
  - Validate AWS deployment
  - Lock down configuration and behavior

**Related:** Containerization discussions and analysis documented in session notes

