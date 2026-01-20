# Master Project Plan

## Overview

This document provides a comprehensive overview of all planned work for the PBX3sbc project, organized by functional area and priority. This is the single source of truth for project planning.

**Last Updated:** January 2026  
**Current Branch:** `main`  
**Current Status:** ✅ Core functionality complete and stable

## Current State

### System Status

**Architecture:**
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

### Current Configuration

**Main Files:**
- **OpenSIPS Config:** `config/opensips.cfg.template` (1004 lines)
- **Database Schema:** `scripts/init-database.sh`
- **Installation:** `install.sh` (automated installer)

**Database Tables:**
- `domain` - Domain → dispatcher_setid mapping (with `setid` column)
- `dispatcher` - Asterisk backend destinations (OpenSIPS 3.6 version 9 schema)
- `location` - Registered endpoint contact information (OpenSIPS usrloc module) ✅ **MIGRATED**
- `acc` - Accounting/CDR records (with `from_uri`, `to_uri` columns)
- `dialog` - Dialog state tracking

### Recent Accomplishments

**Latest Work:**
- ✅ Endpoint cleanup routine with automated timer
- ✅ Dialog state documentation
- ✅ MySQL port opening procedure
- ✅ Endpoint location creation documentation
- ✅ Security/threat detection project plan created
- ✅ Master project plan created
- ✅ Usrloc migration plan created (branch: `usrloc`)

**Key Fixes Implemented:**
- ✅ NOTIFY routing for endpoints behind NAT
- ✅ ACK/BYE routing with private IP detection
- ✅ NAT traversal for in-dialog requests
- ✅ CDR/Accounting mode working
- ✅ Dialog state tracking

## Current State

### ✅ Completed Features

- **Core SIP Routing:**
  - Domain-based routing with multi-tenancy
  - Health-aware routing via dispatcher module
  - Bidirectional routing (endpoints ↔ Asterisk)
  - NAT traversal for in-dialog requests (ACK/BYE/NOTIFY)

- **Database & Management:**
  - MySQL routing database
  - Endpoint location tracking (`location` table via usrloc module) ✅ **MIGRATED**
  - Domain and dispatcher management scripts
  - Automated installation script

- **Security (Basic):**
  - Scanner detection (drops known scanners)
  - Domain validation (door-knocker protection)
  - Attack mitigation (stateless drops)

- **Management Interface:**
  - Web-based admin panel (Laravel + Filament)
  - Domain and Dispatcher management (MVP complete)
  - CDR and Dialog viewing (MVP complete)
  - CDR statistics widget

- **Documentation:**
  - Installation guides
  - Configuration documentation
  - Dialog state explanation
  - Endpoint location documentation
  - MySQL port opening procedure
  - Endpoint cleanup procedures
  - Project context guide

---

## Project Areas

### 1. Security & Threat Detection

**Status:** 📋 Planned (Project plan created)  
**Priority:** High  
**Timeline:** 11 weeks (Phase 0-5)

**Sub-Project:** See [SECURITY-THREAT-DETECTION-PROJECT.md](SECURITY-THREAT-DETECTION-PROJECT.md)

**Overview:**
Comprehensive security enhancement project including registration security, rate limiting, threat detection, monitoring, and IP management.

**Phases:**
- **Phase 0:** Research & Evaluation (Week 1) - Research OpenSIPS modules
- **Phase 1:** Registration Security Foundation (Weeks 2-3)
- **Phase 2:** Rate Limiting & Attack Mitigation (Weeks 4-5)
- **Phase 3:** Monitoring & Alerting (Weeks 6-7)
- **Phase 4:** Advanced Threat Detection (Weeks 8-9)
- **Phase 5:** IP Management & Blocking (Weeks 10-11)

**Key Deliverables:**
- Registration status tracking
- Failed registration tracking
- Rate limiting (IP-based and registration-specific)
- Flood detection
- Security event logging
- Alerting system (email/SMS/webhook)
- IP blocking/whitelisting system
- Threat detection tools

**Dependencies:**
- Phase 0 research must be completed first
- Requires evaluation of OpenSIPS modules before implementation

---

### 2. Monitoring & Statistics

**Status:** ✅ **Metrics Collection Complete** (Grafana deferred)  
**Priority:** Medium-High  
**Timeline:** Metrics collection complete, Grafana deferred

**From Wishlist:**
- ✅ Statistics - Prometheus metrics collection (complete)
- 📋 Grafana dashboards (deferred to future step)
- 📋 Asterisk Node Failure notification - via email or txt
- 📋 Doorknock and flood alerts

#### 2.1 Prometheus & Grafana Integration ✅ **Metrics Collection Complete**

**Objective:** Provide comprehensive statistics and monitoring dashboards

**Status:**
- ✅ Prometheus metrics export (OpenSIPS built-in module) - **COMPLETE**
- ✅ Prometheus server installation - **COMPLETE**
- ✅ Node Exporter installation - **COMPLETE**
- 📋 Grafana dashboards - **DEFERRED** (Prometheus UI sufficient for now)

**Components:**
- ✅ Prometheus metrics exporter for OpenSIPS (built-in module)
- ✅ Prometheus server for metrics collection
- ✅ Node Exporter for system metrics
- 📋 Grafana dashboards for visualization (deferred)
- Key metrics:
  - Call statistics (INVITE, BYE, ACK counts)
  - Registration statistics
  - Dispatcher health metrics
  - Endpoint statistics
  - Security event metrics
  - Performance metrics (response times, errors)

**Implementation:**
- Use OpenSIPS `statistics` module
- Create Prometheus exporter (or use existing)
- Design Grafana dashboards
- Set up alerting rules

**Files to Create:**
- `scripts/setup-prometheus.sh` - Prometheus installation
- `scripts/setup-grafana.sh` - Grafana installation
- `config/prometheus-opensips.yml` - Prometheus configuration
- `config/grafana-dashboards/` - Dashboard JSON files

**Dependencies:**
- Security project Phase 3 (security event logging) for security metrics

#### 2.2 Asterisk Node Failure Notification

**Objective:** Alert when Asterisk backend nodes fail

**Implementation:**
- Monitor dispatcher health status
- Detect when node goes from active to inactive
- Send email/SMS notification
- Track node downtime

**Components:**
- Health check monitoring script
- Alert sending mechanism
- Node status tracking

**Files to Create:**
- `scripts/monitor-asterisk-nodes.sh` - Node monitoring
- `scripts/send-node-alert.sh` - Alert sending
- Database table for node status history

**Integration:**
- Can leverage security alerting system (Phase 3)
- Use dispatcher module events if available

#### 2.3 Security Alerts

**Objective:** Alert on security events (doorknock, floods, attacks)

**Implementation:**
- Part of Security & Threat Detection project Phase 3
- Email/SMS/webhook alerts
- Alert aggregation to prevent spam

**Dependencies:**
- Security project Phase 3

---

### 3. High Availability & Load Balancing

**Status:** 📋 Planned  
**Priority:** Medium  
**Timeline:** 6-8 weeks

**From Wishlist:**
- OpenSIPS load balancing/failover

#### 3.1 Multiple OpenSIPS Instances

**Objective:** Deploy multiple OpenSIPS instances for high availability

**Architecture:**
- Multiple OpenSIPS SBC instances
- Shared MySQL database (RDS or replicated)
- Load balancer in front (AWS ELB, HAProxy, etc.)
- Session replication (if needed)

**Components:**
- Database replication/synchronization
- Load balancer configuration
- Health checks for OpenSIPS instances
- Session state management (if stateful features needed)

**Considerations:**
- OpenSIPS is mostly stateless (database-backed routing)
- May need session replication for dialog state
- Load balancer must handle SIP properly (UDP, TCP, TLS)

**Files to Create:**
- `docs/HA-DEPLOYMENT-GUIDE.md` - High availability guide
- `config/haproxy-opensips.cfg` - HAProxy configuration
- `scripts/setup-ha.sh` - HA setup script

**Dependencies:**
- Containerization (for easier multi-instance deployment)
- Database replication strategy

#### 3.2 Session Replication

**Objective:** Share dialog state across OpenSIPS instances

**Options:**
- Use OpenSIPS clustering module
- Use shared database for dialog state
- Use external session store (Redis, etc.)

**Research Required:**
- Evaluate OpenSIPS clustering capabilities
- Determine if dialog state replication needed
- Test performance impact

---

### 4. TLS & WebRTC Support

**Status:** 📋 Planned  
**Priority:** Medium  
**Timeline:** 4-6 weeks

**From Wishlist:**
- TLS from endpoint to openSIPS then TCP to Asterisk
- WebRTC TLS support - then route to Asterisk

#### 4.1 TLS Support

**Objective:** Enable TLS encryption for SIP traffic

**Components:**
- TLS certificate management
- OpenSIPS TLS configuration
- Endpoint TLS configuration
- Asterisk TLS support

**Implementation:**
- Configure `proto_tls` module
- Set up certificate authority
- Configure TLS ports (5061)
- Update firewall rules

**Files to Create:**
- `scripts/setup-tls.sh` - TLS certificate setup
- `docs/TLS-CONFIGURATION.md` - TLS configuration guide
- `config/tls-certificates/` - Certificate management

**Considerations:**
- Certificate management and renewal
- Performance impact of TLS
- Compatibility with endpoints

#### 4.2 WebRTC Support

**Objective:** Support WebRTC endpoints

**Components:**
- WebRTC gateway functionality
- TURN/STUN server integration
- SDP handling for WebRTC
- TLS requirement for WebRTC

**Implementation:**
- Research OpenSIPS WebRTC capabilities
- Integrate TURN server (coturn, etc.)
- Configure WebRTC-specific routing
- Handle ICE candidates

**Files to Create:**
- `docs/WEBRTC-SUPPORT.md` - WebRTC configuration guide
- `scripts/setup-turn-server.sh` - TURN server setup

**Dependencies:**
- TLS support (required for WebRTC)
- TURN server deployment

---

### 5. Management Interface

**Status:** ✅ **In Progress** (MVP Complete)  
**Priority:** High  
**Timeline:** 8-12 weeks total (MVP: ✅ Complete, Remaining: 4-6 weeks)

**Repository:** Separate repository at `pbx3sbc-admin`  
**Technology Stack:** Laravel 12 + Filament 3.x (TALL stack: Tailwind CSS, Alpine.js, Livewire, Laravel)

**From Wishlist:**
- Web front-end to manage database, UFW firewall and Certificates
- What stack? ✅ **Decided: Laravel + Filament**
- Onboard or API? ✅ **Decided: Integrated Laravel app (no separate API)**
- Security and sign-in? ✅ **Decided: Filament built-in authentication**
- Backup/recovery model for openSIPS.cfg and MySQL database

#### 5.1 Web Management Interface

**Objective:** Web-based management interface for OpenSIPS SBC

**✅ Completed Features (MVP):**
- ✅ **Domain Management** - Full CRUD with validation (domain format, setid)
- ✅ **Dispatcher Management** - Full CRUD with validation (SIP URI format, state, probe_mode, weight, priority)
- ✅ **CDR Management** - Read-only viewing with filtering and search
- ✅ **Dialog Management** - Read-only viewing of active calls with state filtering
- ✅ **CDR Statistics Widget** - Dashboard widget showing CDR statistics
- ✅ **Authentication** - Filament built-in user authentication
- ✅ **Database Integration** - Connects to same MySQL database as OpenSIPS
- ✅ **Automated Installer** - `install.sh` script for easy setup

**📋 Planned Features:**
- 📋 **Endpoint Location Viewing** - View registered endpoints (read-only)
- 📋 **Security Event Viewing** - View security events (depends on Security project Phase 3)
- 📋 **IP Blocking/Whitelisting** - Manage IP blocks (depends on Security project Phase 5)
- 📋 **Firewall Rule Management** - Manage UFW rules via web interface
- 📋 **Certificate Management** - Manage TLS certificates
- 📋 **Statistics Dashboard** - Enhanced dashboard with more widgets
- 📋 **OpenSIPS MI Integration** - Optional integration with OpenSIPS Management Interface
- 📋 **Service Management** - Manage Linux systemd services
- 📋 **S3/Minio Object Storage Management** - Manage backup storage

**🔍 Requirements to Investigate:**
- 🔍 **Flexible Deployment** - Support both co-located (same server as OpenSIPS) and separate deployment
  - **Current State:** Admin panel can run on same server as OpenSIPS
  - **Requirement:** Must also support remote deployment (different server)
  - **Potential Solution:** Containerization (Docker) for easier deployment flexibility
  - **Investigation Needed:**
    - Evaluate containerization approach (Docker/Docker Compose)
    - Assess remote database connection requirements
    - Consider network security implications (database access across servers)
    - Evaluate alternative deployment methods (if containerization not preferred)
  - **Dependencies:** May align with Containerization project (Section 6)

**Architecture:**
- **Stack:** Laravel 12 + Filament 3.x (TALL stack)
- **Database:** Shared MySQL database with OpenSIPS
- **Authentication:** Filament built-in (Laravel sessions)
- **Deployment:** Single Laravel application (no separate frontend/backend)

**Key Files:**
- `pbx3sbc-admin/app/Filament/Resources/DomainResource.php` - Domain management
- `pbx3sbc-admin/app/Filament/Resources/DispatcherResource.php` - Dispatcher management
- `pbx3sbc-admin/app/Filament/Resources/CdrResource.php` - CDR viewing
- `pbx3sbc-admin/app/Filament/Resources/DialogResource.php` - Active calls viewing
- `pbx3sbc-admin/app/Filament/Widgets/CdrStatsWidget.php` - CDR statistics widget
- `pbx3sbc-admin/install.sh` - Automated installer

**Documentation:**
- `pbx3sbc-admin/README.md` - Installation and usage guide
- `pbx3sbc-admin/workingdocs/ADMIN-PANEL-DESIGN.md` - Architecture design
- `pbx3sbc-admin/workingdocs/TWO-REPO-STRATEGY.md` - Two-repository strategy explanation

**Dependencies:**
- Security project Phase 3 (for security event viewing)
- Security project Phase 5 (for IP blocking/whitelisting)
- Statistics project (for enhanced dashboard)
- Containerization project (for flexible deployment - optional but recommended)

#### 5.2 Backup & Recovery

**Objective:** Automated backup and recovery system

**Components:**
- OpenSIPS config backup
- MySQL database backup
- Automated backup scheduling
- Recovery procedures
- Backup verification

**Implementation:**
- Database backup script (mysqldump)
- Config file backup
- Backup storage (local + remote)
- Retention policies
- Recovery testing

**Files to Create:**
- `scripts/backup-opensips.sh` - Backup script
- `scripts/restore-opensips.sh` - Recovery script
- `docs/BACKUP-RECOVERY.md` - Backup/recovery guide
- `config/backup-schedule.conf` - Backup configuration

**Integration:**
- Can be part of management interface
- Can be standalone scripts

---

### 6. Containerization

**Status:** 📋 Planned  
**Priority:** Medium (after local testing)  
**Timeline:** 4-6 weeks

**Containerization:**
- Containerize OpenSIPS deployment
- Multi-container architecture
- AWS/cloud deployment ready

#### 6.1 Docker Deployment

**Objective:** Containerize OpenSIPS for easier deployment

**Components:**
- Dockerfile for OpenSIPS
- Docker Compose configuration
- Environment variable configuration
- Secrets management
- Health checks

**Approach:**
- Use official OpenSIPS Docker image as base
- Multi-container: OpenSIPS + MySQL + Management Interface
- Use RDS MySQL for production (managed)
- Host networking mode for SIP UDP

**Admin Panel Deployment Flexibility:**
- Support both co-located (same Docker Compose stack) and separate deployment
- Admin panel container should be able to connect to remote MySQL database
- Enable flexible deployment scenarios:
  - **Co-located:** Admin panel in same Docker Compose as OpenSIPS (shared network)
  - **Separate:** Admin panel on different server/container (remote database connection)
- Consider network security for remote database access (VPN, firewall rules, MySQL user permissions)

**Files to Create:**
- `Dockerfile` - OpenSIPS container
- `docker-compose.yml` - Multi-container setup
- `docs/CONTAINER-DEPLOYMENT.md` - Container deployment guide
- `.env.example` - Environment variables template

**Dependencies:**
- Complete local testing
- Validate AWS deployment
- Lock down configuration

#### 6.2 Kubernetes Deployment (Optional)

**Objective:** Kubernetes deployment for production scale

**Components:**
- Kubernetes manifests
- Helm charts (optional)
- Service definitions
- Ingress configuration
- ConfigMaps and Secrets

**Files to Create:**
- `k8s/` - Kubernetes manifests
- `helm/` - Helm charts (if using Helm)
- `docs/KUBERNETES-DEPLOYMENT.md` - K8s deployment guide

**Dependencies:**
- Docker deployment working
- Kubernetes cluster available

---

### 7. Testing & Quality Assurance

**Status:** 📋 Ongoing  
**Priority:** High  
**Timeline:** Continuous

#### 7.1 Automated Testing

**Objective:** Comprehensive test coverage

**Components:**
- Unit tests for scripts
- Integration tests for routing
- Security testing
- Performance testing
- Load testing

**Files to Create:**
- `tests/unit/` - Unit tests
- `tests/integration/` - Integration tests
- `tests/security/` - Security tests
- `scripts/run-tests.sh` - Test runner

#### 7.2 Test Environment

**Objective:** Dedicated test environment

**Components:**
- Test SIP endpoints
- Test Asterisk backends
- Test database
- Automated test scenarios

**Files to Create:**
- `docs/TEST-ENVIRONMENT.md` - Test environment setup
- `scripts/setup-test-environment.sh` - Test environment setup

---

### 8. Usrloc Module Migration ✅ **COMPLETE**

**Status:** ✅ **COMPLETE** - Migration finished and tested  
**Priority:** ✅ Completed  
**Timeline:** Completed  
**Branch:** Merged to `main`

**Sub-Project:** See [USRLOC-MIGRATION-PLAN.md](USRLOC-MIGRATION-PLAN.md)

**Overview:**
✅ **Migration Complete:** Migrated from custom `endpoint_locations` table to OpenSIPS standard `usrloc` module and `location` table. This addresses technical debt and aligns with OpenSIPS best practices for proxy-registrar pattern.

**Benefits Achieved:**
- ✅ Fixed stale registration issue (now storing only on 200 OK reply)
- ✅ Reduced technical debt (removed custom table maintenance)
- ✅ Aligned with OpenSIPS best practices (proxy-registrar pattern)
- ✅ Better features (path support, proper expiration, flags)
- ✅ Built-in multi-tenant support

**Completed Phases:**
- ✅ **Phase 0:** Research & Evaluation - Studied `usrloc` module API
- ✅ **Phase 1:** Module Setup & Configuration - Loaded module, created schema
- ✅ **Phase 2:** Parallel Implementation - Implemented alongside existing code
- ✅ **Phase 3:** Migration & Testing - Switched to `usrloc`, removed old code
- ✅ **Phase 4:** Cleanup & Documentation - Updated documentation

**Key Deliverables:**
- ✅ `usrloc` module integrated
- ✅ Proxy-registrar pattern implemented (save on reply, not request)
- ✅ All lookups using `lookup("location")` function
- ✅ Custom `endpoint_locations` table references removed from code
- ✅ Documentation updated

**Dependencies:**
- OpenSIPS `usrloc` module (standard, should be available)
- MySQL database (already in use)
- Can be done independently of other projects

**Impact:**
- Reduces technical debt
- Fixes stale registration bug
- Improves maintainability
- Aligns with OpenSIPS standards

---

## Priority Matrix

### High Priority (Next 3-6 Months)

1. ✅ **Usrloc Module Migration** - **COMPLETE**
   - **CRITICAL:** Prevents increasing technical debt
   - Fixes stale registration bug
   - Reduces technical debt (removes custom table)
   - Aligns with OpenSIPS best practices
   - Must complete before other major work

2. **Security & Threat Detection** (11 weeks)
   - Critical for production security
   - Foundation for other features
   - ✅ Can start now (usrloc migration complete)

3. **Monitoring & Statistics** (4-6 weeks)
   - Essential for operations
   - Overlaps with security monitoring

4. **Backup & Recovery** (2-3 weeks)
   - Critical for production
   - Can be done in parallel

### Medium Priority (6-12 Months)

5. **High Availability** (6-8 weeks)
   - Important for production reliability
   - Depends on containerization

6. **TLS & WebRTC** (4-6 weeks)
   - Security and feature enhancement
   - Customer requirements dependent

7. **Management Interface** (8-12 weeks)
   - Improves usability
   - Can be phased (API first, then UI)
   - Note: Endpoint location viewing feature depends on usrloc migration

### Lower Priority (12+ Months)

8. **Containerization** (4-6 weeks)
   - Deployment convenience
   - Depends on testing completion

9. **Kubernetes Deployment** (4-6 weeks)
   - Advanced deployment option
   - Only if needed for scale

---

## Dependencies & Sequencing

### Critical Path

```
✅ Usrloc Module Migration - COMPLETE
    ↓
Security Research (Phase 0)
    ↓
Security Implementation (Phases 1-5)
    ↓
Monitoring & Statistics
    ↓
High Availability
```

### Parallel Work

- **Backup & Recovery** can be done anytime ✅ (usrloc migration complete)
- **TLS Support** can be done independently ✅ (usrloc migration complete)
- **Management Interface** can start after Security Phase 3 (endpoint viewing now possible with usrloc module)
- **Containerization** can be done after local testing ✅ (usrloc migration complete)

### Blockers

- ✅ **Usrloc Migration** complete - No longer blocking other work
- **Security Phase 0** blocks Security implementation
- **Local Testing** blocks Containerization
- **Security Phase 3** enhances Monitoring capabilities

---

## Resource Estimates

### Development Time

- **Security & Threat Detection:** 11 weeks
- **Monitoring & Statistics:** 4-6 weeks
- **High Availability:** 6-8 weeks
- **TLS & WebRTC:** 4-6 weeks
- **Management Interface:** 8-12 weeks
- **Containerization:** 4-6 weeks
- **Backup & Recovery:** 2-3 weeks

**Total:** ~39-52 weeks (9-12 months) for all features

### With Parallelization (Updated Priority)

- ✅ **Phase 0:** Usrloc Module Migration - **COMPLETE**
- **Phase 1 (Months 2-4):** Security + Backup/Recovery
- **Phase 2 (Months 5-6):** Monitoring + TLS
- **Phase 3 (Months 7-9):** Management Interface + Containerization
- **Phase 4 (Months 10-12):** High Availability + WebRTC

**Estimated:** 10-13 months with focused effort (includes usrloc migration first)

---

## Success Metrics

### Security
- ✅ Zero successful brute force attacks
- ✅ Flood attacks detected and blocked
- ✅ Security events logged and alerted

### Reliability
- ✅ 99.9% uptime
- ✅ Automatic failover working
- ✅ Backup/recovery tested and verified

### Operations
- ✅ Statistics available via Prometheus/Grafana
- ✅ Alerts sent for critical events
- ✅ Management interface functional

### Performance
- ✅ No performance degradation from security checks
- ✅ Sub-second response times
- ✅ Handles expected load

---

## Risk Management

### Technical Risks

1. **Security Module Compatibility**
   - **Risk:** OpenSIPS modules don't meet requirements
   - **Mitigation:** Phase 0 research identifies alternatives

2. **Performance Impact**
   - **Risk:** Security checks slow down routing
   - **Mitigation:** Performance testing, optimization

3. **Complexity**
   - **Risk:** Too many features, hard to maintain
   - **Mitigation:** Phased approach, documentation

### Project Risks

1. **Scope Creep**
   - **Risk:** Adding features beyond plan
   - **Mitigation:** Stick to documented plan, review regularly

2. **Resource Constraints**
   - **Risk:** Not enough time/people
   - **Mitigation:** Prioritize, phase delivery

---

## Documentation Status

### ✅ Completed
- Installation guides
- Configuration documentation
- Dialog state explanation
- Endpoint location documentation
- MySQL port opening procedure
- Endpoint cleanup procedures
- Security/threat detection project plan

### 📋 Planned
- Security modules research
- Security architecture decisions
- TLS configuration guide
- WebRTC support guide
- High availability deployment guide
- Management interface design
- Backup/recovery guide
- Container deployment guide
- Kubernetes deployment guide

---

## Next Actions

### Immediate (This Week)
1. ✅ Create master project plan (this document)
2. ✅ Prioritize usrloc migration as top priority
3. ✅ Complete usrloc migration - **COMPLETE**

### Short Term (Next Month)
1. ✅ Usrloc migration complete - All phases finished
2. 📋 Focus on core system features
3. 📋 Security & Threat Detection project

### Medium Term (Next Quarter)
1. ⏳ Complete Security Phase 0-1
2. ⏳ Implement backup/recovery
3. ⏳ Begin monitoring/statistics work

---

## Related Documents

- [Security & Threat Detection Project](SECURITY-THREAT-DETECTION-PROJECT.md) - Detailed security project plan
- [Endpoint Location Creation](ENDPOINT-LOCATION-CREATION.md) - Endpoint location handling documentation
- [Endpoint Cleanup](ENDPOINT-CLEANUP.md) - Endpoint cleanup procedures
- [Dialog State Explanation](DIALOG-STATE-EXPLANATION.md) - Dialog state values and troubleshooting
- [MySQL Port Opening Procedure](MYSQL-PORT-OPENING-PROCEDURE.md) - MySQL port configuration guide

---

## Notes

- This is a living document - update as priorities change
- Review quarterly to adjust timeline and priorities
- Focus on high-priority items first
- Don't start new areas until current ones are stable
- Document decisions and rationale
