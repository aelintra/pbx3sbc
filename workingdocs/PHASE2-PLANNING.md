# Phase 2 Planning

## Overview
Planning document for Phase 2 development work.

## Database Schema Integration

### Requirement: Full OpenSIPS Schema Deployment
Deploy the entire OpenSIPS database schema during installation, as long as none of the tables conflict with Laravel base tables.

### Analysis Results
✅ **No table name conflicts found** between OpenSIPS and Laravel tables.

**Laravel Tables:**
- `users`, `password_reset_tokens`, `sessions`
- `cache`, `cache_locks`
- `jobs`, `job_batches`, `failed_jobs`

**OpenSIPS Tables:**
- `version`, `acc`, `missed_calls`, `dbaliases`, `subscriber`, `uri`
- `clusterer`, `dialog`, `dialplan`, `dispatcher`, `domain`
- `dr_gateways`, `dr_rules`, `dr_carriers`, `dr_groups`, `dr_partitions`
- `grp`, `re_grp`, `load_balancer`, `silo`, `address`
- `rtpproxy_sockets`, `rtpengine`, `speed_dial`, `tls_mgm`
- `location` (not used - we use `endpoint_locations` instead)

**Custom Tables:**
- `endpoint_locations` (custom endpoint tracking)

### Installation Order
1. **First:** Run `pbx3sbc/scripts/init-database.sh` (creates OpenSIPS tables)
2. **Then:** Run `php artisan migrate` (creates Laravel tables)

### Required: Admin Panel Installer Validation

**TODO:** Add checks in `pbx3sbc-admin` installer to fail gracefully if OpenSIPS tables are not present.

**Implementation Notes:**
- Check for key OpenSIPS tables before proceeding with Laravel migrations
- Suggested tables to check: `version`, `domain`, `dispatcher`, `endpoint_locations`
- Provide clear error message directing user to run `pbx3sbc/scripts/init-database.sh` first
- Exit gracefully with helpful instructions

**Example Check:**
```bash
# Check if OpenSIPS tables exist
if ! mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES LIKE 'domain';" | grep -q "domain"; then
    echo "ERROR: OpenSIPS database tables not found."
    echo "Please run: cd pbx3sbc && sudo ./scripts/init-database.sh"
    exit 1
fi
```

## Phase 2 Features

### 1. Accounting (CDR)
**Status:** Planned  
**OpenSIPS Module:** `acc` module  
**Database Tables:** `acc`, `missed_calls` (from standard-create.sql)

**Requirements:**
- Track all call attempts (INVITE, BYE, CANCEL)
- Store CDR data in MySQL database
- Capture: call duration, SIP codes, timestamps, call IDs
- Support for missed calls logging

**Implementation Tasks:**
- [ ] Load `acc` module in opensips.cfg
- [ ] Configure `acc` module parameters (db_url, log_level, etc.)
- [ ] Add accounting calls in routing logic (acc_log_request, acc_log_response)
- [ ] Verify `acc` and `missed_calls` tables exist in database
- [ ] Test accounting data collection
- [ ] Create admin panel interface for viewing CDRs

**References:**
- OpenSIPS `acc` module documentation
- Database schema already includes `acc` table (from standard-create.sql)

---

### 2. Statistics Gathering
**Status:** Planned  
**OpenSIPS Module:** `statistics` module (built-in)  
**Database Tables:** None (in-memory, can export to database)

**Requirements:**
- Track SIP message statistics (requests, responses, errors)
- Monitor dispatcher health statistics
- Export statistics for monitoring (Prometheus/Grafana mentioned in wishlist)
- Track system performance metrics

**Implementation Tasks:**
- [ ] Configure statistics module parameters
- [ ] Add statistics tracking in routing logic
- [ ] Set up statistics export mechanism (MI, HTTP, or database)
- [ ] Integrate with Prometheus exporter (if available)
- [ ] Create admin panel dashboard for statistics
- [ ] Document statistics endpoints

**References:**
- OpenSIPS statistics module (built-in)
- Consider `statistics` module for database-backed stats
- Prometheus integration may require custom exporter

---

### 3. WebRTC Support for Endpoints
**Status:** Planned  
**OpenSIPS Modules:** `rtpengine`, `proto_ws`, `proto_wss`  
**Additional Requirements:** Certificate creation and management

**Requirements:**
- Support WebRTC endpoints (browsers, WebRTC clients)
- Handle WebSocket (WS) and Secure WebSocket (WSS) transports
- RTP media handling via RTPEngine
- Certificate creation and management for WSS
- Automatic certificate renewal

**Implementation Tasks:**
- [ ] Load WebRTC transport modules (`proto_ws`, `proto_wss`)
- [ ] Configure WebSocket/WSS listeners (ports 80/443 or custom)
- [ ] Load and configure `rtpengine` module
- [ ] Set up RTPEngine service (separate daemon)
- [ ] Implement certificate creation script (Let's Encrypt or self-signed)
- [ ] Implement certificate management (renewal, rotation)
- [ ] Add certificate configuration to OpenSIPS config
- [ ] Update firewall rules for WebSocket ports
- [ ] Test WebRTC endpoint registration
- [ ] Test WebRTC call flow
- [ ] Create admin panel interface for certificate management
- [ ] Document WebRTC setup and certificate management

**Database Tables:**
- `rtpengine` table (from standard-create.sql) - for RTPEngine socket configuration
- `tls_mgm` table (from standard-create.sql) - for TLS certificate management

**References:**
- OpenSIPS WebRTC documentation
- RTPEngine documentation
- Let's Encrypt for certificate automation

---

### 4. Trunking Support to Upstream Carriers
**Status:** Planned  
**OpenSIPS Modules:** `drouting` (dialplan routing), `carrierroute` (alternative)  
**Database Tables:** `dr_gateways`, `dr_rules`, `dr_carriers`, `dr_groups`, `dr_partitions`

**Requirements:**
- Route outbound calls to upstream SIP carriers
- Support multiple carriers with failover
- Carrier authentication (IP-based or digest)
- Load balancing across carrier gateways
- Cost-based routing (if needed)

**Implementation Tasks:**
- [ ] Load `drouting` module
- [ ] Configure dialplan routing tables (dr_gateways, dr_rules, dr_carriers)
- [ ] Set up carrier gateway definitions
- [ ] Implement carrier authentication (IP whitelist or digest)
- [ ] Add outbound routing logic in opensips.cfg
- [ ] Test carrier trunk connectivity
- [ ] Test failover scenarios
- [ ] Create admin panel interface for carrier management
- [ ] Document carrier configuration

**Database Tables:**
- `dr_gateways` - Carrier gateway definitions
- `dr_rules` - Routing rules
- `dr_carriers` - Carrier definitions
- `dr_groups` - Carrier groups
- `dr_partitions` - Routing partitions

**References:**
- OpenSIPS `drouting` module documentation
- Database schema already includes dr_* tables (from standard-create.sql)

---

### 5. Trunking Support for Downstream Clients
**Status:** Planned  
**OpenSIPS Modules:** `dispatcher` (already in use), `permissions` (for IP-based auth)

**Requirements:**
- Allow downstream clients to register/connect as trunks
- IP-based authentication for trunk connections
- Domain-based routing for downstream trunks
- Support multiple downstream clients

**Implementation Tasks:**
- [ ] Configure IP-based authentication using `permissions` module
- [ ] Set up downstream trunk domains in `domain` table
- [ ] Configure dispatcher sets for downstream clients
- [ ] Add routing logic for downstream trunk traffic
- [ ] Test downstream trunk registration
- [ ] Test call routing to/from downstream trunks
- [ ] Create admin panel interface for downstream trunk management
- [ ] Document downstream trunk setup

**Database Tables:**
- `domain` - Already in use for domain routing
- `dispatcher` - Already in use for backend routing
- `address` - For IP-based permissions (from standard-create.sql)

**References:**
- OpenSIPS `permissions` module for IP-based auth
- Existing `dispatcher` and `domain` table usage

---

### 6. DDI Routing (Direct Dial-In)
**Status:** Planned  
**OpenSIPS Modules:** `dialplan` (for number translation)  
**Database Tables:** `dialplan`

**Requirements:**
- Route inbound calls from upstream carriers based on DDI (called number)
- Map DDI numbers to internal extensions/endpoints
- Support number translation and normalization
- Handle multiple DDI ranges per tenant

**Implementation Tasks:**
- [ ] Load `dialplan` module
- [ ] Configure `dialplan` table structure
- [ ] Implement DDI lookup logic in routing script
- [ ] Add number translation rules
- [ ] Test DDI routing from upstream carriers
- [ ] Test number translation
- [ ] Create admin panel interface for DDI management
- [ ] Document DDI routing configuration

**Database Tables:**
- `dialplan` - For number translation rules (from standard-create.sql)

**References:**
- OpenSIPS `dialplan` module documentation
- Database schema already includes `dialplan` table

---

### 7. SIP TLS Support
**Status:** Planned  
**OpenSIPS Modules:** `proto_tls`, `tls_mgm`  
**Database Tables:** `tls_mgm`

**Requirements:**
- Support SIP over TLS (SIPS) on port 5061
- Certificate management for TLS
- TLS client certificate validation (optional)
- Secure signaling for carrier trunks and endpoints

**Implementation Tasks:**
- [ ] Load `proto_tls` module
- [ ] Load `tls_mgm` module for certificate management
- [ ] Configure TLS listener (socket=tls:0.0.0.0:5061)
- [ ] Set up TLS certificates (server certificate)
- [ ] Configure TLS parameters (cipher suites, protocols)
- [ ] Add TLS certificate management scripts
- [ ] Update firewall rules for port 5061
- [ ] Test TLS endpoint registration
- [ ] Test TLS call flow
- [ ] Test TLS trunk connections
- [ ] Create admin panel interface for TLS certificate management
- [ ] Document TLS setup

**Database Tables:**
- `tls_mgm` - For TLS certificate management (from standard-create.sql)

**References:**
- OpenSIPS TLS documentation
- Certificate management overlaps with WebRTC certificate work

---

## Implementation Strategy

**Workflow:** One feature at a time, fully coded and tested before moving to the next.

**Implementation Order:**
1. **Accounting** - Foundation for monitoring and billing
2. **Statistics Gathering** - Essential for operations monitoring
3. **SIP TLS Support** - Security foundation
4. **Trunking to Upstream Carriers** - Core functionality
5. **DDI Routing** - Required for inbound carrier calls
6. **Trunking for Downstream Clients** - Extends functionality
7. **WebRTC Support** - Advanced feature (most complex)

**Development Process:**
- Complete all implementation tasks for one feature
- Test thoroughly (unit tests, integration tests, manual testing)
- Document the feature
- Commit and push to phase2 branch
- Only then proceed to the next feature

**Dependencies:**
- TLS support needed before WebRTC WSS (order already accounts for this)
- DDI routing depends on upstream trunking (order already accounts for this)

## Development Workflow

**Process for Each Feature:**
1. Review feature requirements and implementation tasks
2. Implement all code changes (OpenSIPS config, scripts, admin panel if needed)
3. Test thoroughly:
   - Unit tests (if applicable)
   - Integration tests
   - Manual testing in test environment
   - Verify database changes
   - Verify OpenSIPS functionality
4. Update documentation
5. Commit and push to `phase2` branch
6. **Only then** proceed to next feature

**Current Status:**
- Planning complete ✅
- Ready to begin Feature 1: Accounting

## Next Steps
- [ ] Implement OpenSIPS table validation in pbx3sbc-admin installer (prerequisite)
- [ ] Begin Feature 1: Accounting
  - Complete all implementation tasks
  - Test thoroughly
  - Document
  - Commit to phase2 branch
- [ ] Then proceed to Feature 2: Statistics Gathering
