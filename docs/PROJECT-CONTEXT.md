# Project Context - Quick Start Guide

**Purpose:** This document provides essential context for quickly understanding the PBX3sbc project, its architecture, key decisions, and current state. Use this as a starting point when beginning work on the project.

**Last Updated:** January 2026

---

## What Is This Project?

**PBX3sbc** is a SIP Edge Router (Session Border Controller) built on OpenSIPS that:
- **Protects** Asterisk PBX backends from SIP scans and attacks
- **Routes** SIP traffic between endpoints and Asterisk backends
- **Enables** multi-tenant domain-based routing
- **Provides** high availability with health-aware load balancing
- **Tracks** endpoint locations for bidirectional routing

### Key Characteristics

- **RTP Bypass:** RTP media flows directly between endpoints and Asterisk (SBC doesn't handle media)
- **Stateless Edge:** Designed for horizontal scalability
- **MySQL-Driven:** Routing decisions come from MySQL database
- **NAT-Aware:** Handles endpoints behind NAT correctly

---

## Architecture Overview

```
┌─────────────┐
│   SIP       │
│  Endpoints  │
│  (Phones)   │
└──────┬──────┘
       │ SIP (signaling only)
       │
       ▼
┌─────────────────────────────────┐
│      OpenSIPS SBC                │
│  ┌───────────────────────────┐  │
│  │  Routing Logic            │  │
│  │  - Domain validation      │  │
│  │  - Endpoint lookup        │  │
│  │  - Dispatcher selection   │  │
│  │  - NAT traversal          │  │
│  └───────────────────────────┘  │
└──────┬───────────────────┬───────┘
       │                   │
       │ SIP                │ SIP
       │ (to Asterisk)      │ (to endpoints)
       │                    │
       ▼                    ▼
┌─────────────┐      ┌─────────────┐
│  Asterisk   │      │  Endpoints  │
│  Backends   │      │  (Phones)   │
└─────────────┘      └─────────────┘
       │
       │ RTP (direct, bypasses SBC)
       │
       ▼
┌─────────────┐
│  Endpoints  │
└─────────────┘

       ┌─────────────┐
       │   MySQL     │
       │  Database   │
       │  - domains  │
       │  - dispatcher│
       │  - location │
       │    (usrloc) │
       │  - acc (CDR)│
       │  - dialog   │
       └─────────────┘
```

### Request Flow

1. **Inbound (Endpoint → Asterisk):**
   - REGISTER/INVITE arrives at OpenSIPS
   - Domain validated against `domain` table
   - Dispatcher selects healthy Asterisk backend
   - Request forwarded to Asterisk

2. **Outbound (Asterisk → Endpoint):**
   - OPTIONS/NOTIFY/INVITE arrives from Asterisk
   - Endpoint location looked up using `lookup("location")` function (usrloc module)
   - Request routed directly to endpoint IP:port

3. **In-Dialog (ACK/BYE):**
   - Uses `loose_route()` for Record-Route-based routing
   - NAT traversal fixes applied
   - Routes to correct destination (endpoint or Asterisk)

---

## Key Design Decisions

### 1. OpenSIPS `usrloc` Module and `location` Table ✅ **MIGRATED**

**Decision:** Use OpenSIPS standard `usrloc` module and `location` table (migrated from custom `endpoint_locations` table).

**Why:**
- ✅ Standard OpenSIPS approach (best practices)
- ✅ Built-in multi-tenant support (domain-aware lookups)
- ✅ Proper proxy-registrar pattern (store only on successful registration)
- ✅ Better features (path support, proper expiration, flags)
- ✅ Reduced technical debt (no custom table maintenance)

**Migration Status:** ✅ Complete - See `docs/USRLOC-MIGRATION-PLAN.md` and `workingdocs/SESSION-SUMMARY-USRLOC-LOOKUP-COMPLETE.md`

**Note:** Previously used custom `endpoint_locations` table (see `workingdocs/SIMPLIFIED-APPROACH.md` for historical context)

### 2. Domain → Dispatcher Linking via `setid` Column

**Decision:** Use explicit `setid` column in `domain` table to link domains to dispatcher sets.

**Why:**
- Decouples domain ID from routing set ID
- Allows domain IDs to change without breaking routing
- Explicit is better than implicit
- Easier to understand

**See:** `workingdocs/OpenSIPS-link-domains-with-dispatcher.md`

### 3. RTP Bypass (No Media Handling)

**Decision:** SBC does not handle RTP media - flows directly between endpoints and Asterisk.

**Why:**
- Reduces SBC load
- Lower latency for media
- Simpler architecture
- SBC focuses on signaling only

### 4. MySQL for All Routing Data

**Decision:** All routing decisions come from MySQL database (domains, dispatcher, endpoints).

**Why:**
- Centralized configuration
- Easy to update without config reloads
- Supports multi-tenant scenarios
- Database-driven routing is flexible

---

## Current State

### ✅ What's Working

- **Core Routing:**
  - Domain-based routing with multi-tenancy
  - Health-aware dispatcher routing (OPTIONS health checks)
  - Bidirectional routing (endpoints ↔ Asterisk)
  - Endpoint location tracking

- **NAT Handling:**
  - ✅ **Auto-detection**: Automatically detects NAT environment based on endpoint IPs
  - NAT traversal for REGISTER (`fix_nated_register()`)
  - Automatic SDP fixing for INVITE and responses when NAT detected
  - In-dialog request routing (ACK/BYE) with NAT IP lookup
  - NOTIFY routing to endpoints behind NAT
  - Works seamlessly in both LAN and NAT environments

- **Accounting:**
  - CDR (Call Detail Records) with `from_uri`/`to_uri`
  - Dialog state tracking
  - Duration calculation

- **Security (Basic):**
  - Scanner detection (drops known scanners)
  - Domain validation (door-knocker protection)
  - Method validation

- **Monitoring & Metrics (✅ Complete):**
  - Prometheus metrics export via built-in OpenSIPS module
  - Prometheus server for metrics collection and storage
  - Node Exporter for system metrics (CPU, memory, disk, network)
  - Real-time statistics collection (core, dialog, transaction, dispatcher, usrloc, acc)
  - Historical metrics storage (30-day retention)
  - Automated installation via `install.sh` script
  - **See:** `docs/PROMETHEUS-GRAFANA-PLAN.md` and `docs/PROMETHEUS-INSTALL-UBUNTU.md`

- **Management Interface (MVP Complete):**
  - Web-based admin panel (Laravel + Filament)
  - Domain and Dispatcher management (full CRUD)
  - CDR and Dialog viewing (read-only)
  - CDR statistics widget
  - Authentication and user management
  - **Repository:** `pbx3sbc-admin` (separate repository)

- **Automation:**
  - Automated installation script (includes Prometheus & Node Exporter)
  - Endpoint cleanup routine (daily timer)
  - Database initialization scripts

### 📋 What's Planned

See `docs/MASTER-PROJECT-PLAN.md` for complete project plan. Key areas:

1. **Security & Threat Detection** (High Priority)
   - Registration security
   - Rate limiting
   - IP reputation
   - Advanced monitoring

2. **Monitoring & Visualization** (Medium Priority - Metrics Collection Complete)
   - ✅ Prometheus metrics export (complete)
   - ✅ Prometheus server installation (complete)
   - ✅ Node Exporter installation (complete)
   - 📋 Grafana dashboards (optional - can use Prometheus UI)
   - 📋 Alerting rules configuration
   - 📋 Custom metrics and dashboards

3. **Management Interface** (High Priority - MVP Complete)
   - ✅ Domain/dispatcher management (complete)
   - ✅ CDR/Dialog viewing (complete)
   - 📋 Endpoint location viewing
   - 📋 Security event viewing (depends on Security project)
   - 📋 IP blocking/whitelisting (depends on Security project)
   - 📋 Firewall rule management
   - 📋 Certificate management
   - 📋 Enhanced statistics dashboard (can leverage Prometheus data)

4. **Backup & Recovery** (Medium Priority)
   - Automated backups
   - Recovery procedures

5. **Containerization** (Medium Priority)
   - Docker deployment
   - Kubernetes (optional)

---

## Database Schema

### Key Tables

**`domain`**
- Maps domains to dispatcher set IDs
- Columns: `id`, `domain`, `setid`, `enabled`
- Used for: Domain validation and routing

**`dispatcher`**
- Asterisk backend destinations
- Columns: `setid`, `destination`, `flags`, `priority`, `weight`, `attrs`
- Used for: Load balancing to Asterisk backends

**`location`** (OpenSIPS usrloc module)
- Registered endpoint contact information
- Columns: `username`, `domain`, `contact`, `received`, `expires`, `q`, `callid`, `cseq`, `last_modified`, `flags`, `cflags`, `user_agent`, `socket`, `methods`, `ruid`, `instance`, `reg_id`, `server_id`, `connection_id`, `tcpconn_id`, `keepalive`, `last_keepalive`, `ka_interval`, `attr`
- Used for: Routing back to endpoints (OPTIONS/NOTIFY/INVITE) via `lookup("location")` function
- **Note:** Migrated from custom `endpoint_locations` table - see `docs/USRLOC-MIGRATION-PLAN.md`

**`acc`**
- Accounting/CDR records
- Columns: `id`, `method`, `from_uri`, `to_uri`, `duration`, `ms_duration`, `sip_code`, `created`
- Used for: Call billing and reporting

**`dialog`**
- Dialog state tracking
- Columns: `hash_entry`, `hash_id`, `callid`, `from_uri`, `to_uri`, `state`, `start_time`, `timeout`
- Used for: Dialog state monitoring and CDR correlation

**See:** `scripts/init-database.sh` for complete schema

---

## Key Files

### Configuration

- **`config/opensips.cfg.template`** - Main OpenSIPS configuration (~1300 lines)
  - Routing logic
  - Module configuration
  - NAT handling
  - Dialog tracking

### Scripts

- **`install.sh`** - Automated installation script
- **`scripts/init-database.sh`** - Database schema initialization
- **`scripts/add-domain.sh`** - Add domain to routing
- **`scripts/add-dispatcher.sh`** - Add Asterisk backend destination
- **`scripts/cleanup-expired-endpoints.sh`** - Cleanup expired endpoint locations
- **`scripts/view-status.sh`** - View service status

### Documentation

- **`docs/MASTER-PROJECT-PLAN.md`** - Complete project plan
- **`docs/opensips-routing-logic.md`** - Detailed routing logic explanation
- **`docs/ENDPOINT-LOCATION-CREATION.md`** - When endpoint_location records are created
- **`docs/DIALOG-STATE-EXPLANATION.md`** - Dialog state values and meanings
- **`docs/NAT-AUTO-DETECTION.md`** - NAT environment auto-detection implementation
- **`docs/AUDIO-FIX-ACK-HANDLING.md`** - ACK forwarding fix and troubleshooting notes
- **`docs/SECURITY-THREAT-DETECTION-PROJECT.md`** - Security project plan
- **`docs/PROMETHEUS-GRAFANA-PLAN.md`** - Prometheus & Grafana deployment plan
- **`docs/PROMETHEUS-INSTALL-UBUNTU.md`** - Prometheus installation guide
- **`docs/STATISTICS-OVERVIEW.md`** - Statistics collection overview
- **`docs/TEST-DEPLOYMENT-CHECKLIST.md`** - Test deployment checklist

### Working Documents

- **`workingdocs/`** - Historical context, troubleshooting guides, session summaries

---

## Common Workflows

### Adding a New Domain

```bash
# Add domain with dispatcher set ID 10
sudo ./scripts/add-domain.sh example.com 10 1 "Example tenant"

# Add Asterisk backends for set ID 10
sudo ./scripts/add-dispatcher.sh 10 sip:10.0.1.10:5060 0 0
sudo ./scripts/add-dispatcher.sh 10 sip:10.0.1.11:5060 0 0
```

### Viewing Status

```bash
# View OpenSIPS service status
sudo ./scripts/view-status.sh

# Check endpoint locations (usrloc location table)
mysql -u opensips -p opensips -e "SELECT username, domain, contact, received, expires FROM location WHERE expires > UNIX_TIMESTAMP();"

# Check recent CDRs
mysql -u opensips -p opensips -e "SELECT * FROM acc ORDER BY created DESC LIMIT 10;"
```

### Troubleshooting

**⚠️ Important:** Comprehensive logging is critical for troubleshooting. Always check logs first!

1. **Check OpenSIPS logs:**
   ```bash
   journalctl -u opensips -f
   ```
   - Look for detailed request/response logging
   - Check NAT detection messages
   - Review ACK/PRACK forwarding logs
   - See `docs/AUDIO-FIX-ACK-HANDLING.md` for example of logging value

2. **Check database connectivity:**
   ```bash
   mysql -u opensips -p opensips -e "SELECT 1;"
   ```

3. **Verify endpoint registration:**
   ```bash
   # Check location table (usrloc module)
   mysql -u opensips -p opensips -e "SELECT username, domain, contact, received, expires FROM location WHERE username='1000' AND expires > UNIX_TIMESTAMP();"
   
   # Or use OpenSIPS MI command
   opensipsctl ul show
   ```

4. **Check dialog states:**
   ```bash
   mysql -u opensips -p opensips -e "SELECT callid, state, start_time FROM dialog ORDER BY start_time DESC LIMIT 10;"
   ```

5. **Troubleshooting ACK/RTP issues:**
   - Check logs for ACK forwarding errors
   - Verify NAT detection is working (`NAT environment detected` messages)
   - Check if SDP is being fixed correctly
   - See `docs/AUDIO-FIX-ACK-HANDLING.md` for detailed troubleshooting guide

---

## Important Concepts

### Dialog States

OpenSIPS dialog states (from `dialog` table):
- **State 1:** Unconfirmed (INVITE sent, no 200 OK yet)
- **State 2:** Early (180 Ringing received)
- **State 3:** Confirmed (200 OK received, call established)
- **State 4:** Established (call active)
- **State 5:** Ended (BYE received, call terminated)

**See:** `docs/DIALOG-STATE-EXPLANATION.md`

### Endpoint Location Creation ✅ **UPDATED - Proxy-Registrar Pattern**

Endpoint locations are created using OpenSIPS `save("location")` function **only after** receiving a successful 200 OK response from Asterisk (proxy-registrar pattern).

**Implementation:**
- `save("location")` called in `onreply_route` when REGISTER receives 200 OK
- Respects Asterisk's expiration decisions
- No stale registrations (failed registrations don't create records)
- Uses standard OpenSIPS `usrloc` module and `location` table

**Why:** Follows OpenSIPS best practices - only store locations for successful registrations.

**See:** 
- `docs/USRLOC-MIGRATION-PLAN.md` - Migration details
- `workingdocs/SESSION-SUMMARY-USRLOC-LOOKUP-COMPLETE.md` - Implementation summary
- `docs/ENDPOINT-LOCATION-CREATION.md` - Historical context (old approach)

### NAT Traversal

OpenSIPS handles NAT traversal with **automatic environment detection**:

- **Auto-Detection:** ✅ Automatically detects if endpoints are behind NAT by checking source IPs
  - Enables NAT fixes only when needed (endpoints sending private IPs)
  - Works seamlessly in both LAN and NAT environments
  - No manual configuration required

- **REGISTER:** Fixes Contact header with public IP (`fix_nated_register()`)
- **INVITE:** Automatically fixes SDP media IPs when NAT detected (`fix_nated_sdp()`)
- **Responses:** Automatically fixes Contact headers and SDP when NAT detected
- **In-dialog requests:** Routes ACK/BYE using Record-Route headers + NAT IP lookup
- **NOTIFY:** Routes to endpoint's public IP:port from location table

**Key functions:**
- `fix_nated_register()` - Fixes REGISTER Contact header (always enabled)
- `fix_nated_sdp("rewrite-media-ip")` - Fixes SDP media IPs (auto-enabled when NAT detected)
- `fix_nated_contact()` - Fixes Contact header in responses (auto-enabled when NAT detected)
- `loose_route()` - Routes in-dialog requests
- `route[CHECK_NAT_ENVIRONMENT]` - Auto-detects NAT environment

**See:** `docs/NAT-AUTO-DETECTION.md` for detailed implementation

---

## Where to Find More Information

### Architecture & Design
- `docs/opensips-routing-logic.md` - Detailed routing logic
- `docs/OPENSIPS-LOGIC-DIAGRAM.md` - Visual routing flow
- `workingdocs/SIMPLIFIED-APPROACH.md` - Design decisions

### Installation & Setup
- `docs/03-Install_notes.md` - Installation guide
- `docs/02-QUICKSTART.md` - Quick start guide
- `README.md` - Project overview

### Troubleshooting
- `workingdocs/SNOM-TROUBLESHOOTING.md` - Snom-specific issues
- `docs/DIALOG-STATE-EXPLANATION.md` - Dialog state troubleshooting
- `docs/ENDPOINT-CLEANUP.md` - Endpoint cleanup procedures

### Project Planning
- `docs/MASTER-PROJECT-PLAN.md` - Complete project plan
- `docs/SECURITY-THREAT-DETECTION-PROJECT.md` - Security project plan

### Historical Context
- `workingdocs/SESSION-SUMMARY*.md` - Historical fix documentation
- `workingdocs/CDR-VERIFICATION-*.md` - CDR testing documentation

---

## Quick Reference

### OpenSIPS Configuration Location
- Template: `config/opensips.cfg.template`
- Installed: `/etc/opensips/opensips.cfg`

### Database Credentials
- Default user: `opensips`
- Default database: `opensips`
- Credentials file: `/etc/opensips/.mysql_credentials`

### Service Management
```bash
# Start/stop/restart OpenSIPS
sudo systemctl start opensips
sudo systemctl stop opensips
sudo systemctl restart opensips

# Reload configuration (without dropping calls)
sudo opensipsctl fifo cfg_reload

# View status
sudo systemctl status opensips
```

### Log Locations
- OpenSIPS logs: `journalctl -u opensips`
- Database logs: MySQL error log (varies by installation)

---

## For AI Assistants

When starting work on this project:

1. **Read this document first** - Understand the architecture and key decisions
2. **Check `docs/MASTER-PROJECT-PLAN.md`** - See what's planned and current priorities
3. **Review `config/opensips.cfg.template`** - Understand the routing logic
4. **Check `workingdocs/`** - Look for relevant historical context
5. **Ask clarifying questions** - If something is unclear, ask before making changes

**Key principles:**
- Keep it simple (we chose simple SQL over complex modules)
- Document decisions (especially architectural ones)
- Test changes thoroughly (SIP routing is complex)
- Maintain backward compatibility (production system)

---

**Last Updated:** January 2026  
**Maintained By:** Project Team  
**Questions?** See documentation in `docs/` directory or check `workingdocs/` for historical context.
