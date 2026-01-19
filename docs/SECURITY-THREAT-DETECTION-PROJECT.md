# Security & Threat Detection Project

## Overview

This document outlines a comprehensive security and threat detection enhancement project for the OpenSIPS SBC. The goal is to implement robust security measures, threat detection, and monitoring capabilities to protect against attacks and provide visibility into system security.

## Project Goals

1. **Protect against registration attacks** (brute force, enumeration)
2. **Detect and mitigate flood attacks** (SIP flooding, DoS)
3. **Monitor and alert on security events** (failed registrations, attacks)
4. **Implement rate limiting** for suspicious activity
5. **Track and analyze security patterns** for threat intelligence
6. **Provide security visibility** through logging and statistics

## Current Security State

### ✅ Already Implemented

- **Scanner Detection:** Drops known scanners (sipvicious, friendly-scanner, sipcli, nmap)
- **Domain Validation:** Door-knocker protection via domain table lookup
- **Attack Mitigation:** Stateless drops for attackers
- **Basic Logging:** OpenSIPS logs for debugging

### ⚠️ Security Gaps

- **No registration failure tracking** - Cannot detect brute force attacks
- **No rate limiting** - Vulnerable to flood attacks
- **No response-based cleanup** - Failed registrations persist
- **No security event monitoring** - Limited visibility into attacks
- **No alerting** - No notifications for security events
- **No threat intelligence** - Cannot track attack patterns

## Project Phases

### Phase 0: Research & Evaluation (Week 1)

**Goal:** Research existing OpenSIPS security modules and community solutions before building custom implementations

**Critical:** This phase must be completed before implementation to avoid reinventing wheels and creating technical debt.

#### 0.1 OpenSIPS Security Modules Research

**Objective:** Identify and evaluate built-in OpenSIPS modules for security features

**Research Areas:**

1. **Rate Limiting Modules:**
   - `ratelimit` module - Built-in rate limiting
   - `htable` module - Hash table for in-memory rate limiting
   - `ipban` module - IP banning capabilities
   - `permissions` module - IP-based access control
   - `userblacklist` module - User-based blacklisting

2. **Attack Mitigation Modules:**
   - `pike` module - Detect and block flooding attacks
   - `secfilter` module - Security filtering
   - `sanity` module - SIP message sanity checks (built-in)
   - `maxfwd` module - Max-Forwards header checking (built-in)

3. **Authentication & Authorization:**
   - `auth` module - Authentication framework
   - `auth_db` module - Database-backed authentication
   - `permissions` module - Access control lists

4. **Statistics & Monitoring:**
   - `statistics` module - Built-in statistics
   - `snmpstats` module - SNMP statistics
   - `mi_datagram` module - Management interface

**Research Tasks:**
- [ ] Review OpenSIPS 3.x module documentation for security modules
- [ ] Test `pike` module for flood detection capabilities
- [ ] Test `ratelimit` module for rate limiting features
- [ ] Test `ipban` module for IP blocking functionality
- [ ] Evaluate `htable` module for in-memory rate limiting performance
- [ ] Document module capabilities and limitations
- [ ] Compare module features vs. custom database approach

**Deliverables:**
- Research document: `docs/SECURITY-MODULES-RESEARCH.md`
- Module evaluation matrix
- Recommendations on what to use vs. build custom

#### 0.2 Community Solutions Research

**Objective:** Identify community-built security solutions and best practices

**Research Areas:**

1. **OpenSIPS Community:**
   - OpenSIPS mailing list archives
   - OpenSIPS GitHub repositories
   - Community forum discussions
   - User-contributed scripts and tools

2. **SIP Security Best Practices:**
   - RFC 3261 security considerations
   - SIP security best practices documents
   - Industry security guidelines
   - Common attack patterns and mitigations

3. **Integration Solutions:**
   - Prometheus/Grafana integrations
   - SIEM integrations
   - Log aggregation solutions
   - Alerting frameworks

**Research Tasks:**
- [ ] Search OpenSIPS GitHub for security-related projects
- [ ] Review OpenSIPS mailing list for security discussions
- [ ] Research SIP security best practices
- [ ] Identify existing monitoring/alerting integrations
- [ ] Document community solutions and patterns

**Deliverables:**
- Research document: `docs/COMMUNITY-SECURITY-SOLUTIONS.md`
- List of reusable community solutions
- Best practices compilation

#### 0.3 Architecture Decision Document

**Objective:** Document decisions on what to use vs. build custom

**Decision Framework:**
- Use existing module if it meets requirements
- Build custom if no suitable module exists
- Extend existing module if close but needs customization
- Consider maintenance burden of custom solutions

**Deliverables:**
- Architecture Decision Record (ADR): `docs/SECURITY-ARCHITECTURE-DECISIONS.md`
- Updated project plan based on research findings
- Revised implementation approach

#### 0.4 Proof of Concept

**Objective:** Test key modules before full implementation

**POC Tasks:**
- [ ] Install and test `pike` module for flood detection
- [ ] Install and test `ratelimit` module for rate limiting
- [ ] Install and test `ipban` module for IP blocking
- [ ] Evaluate performance impact of security modules
- [ ] Test integration with existing configuration

**Deliverables:**
- POC test results
- Performance benchmarks
- Integration notes

**Research Resources:**
- OpenSIPS Documentation: https://opensips.org/docs/
- OpenSIPS Modules: https://opensips.org/docs/modules/
- OpenSIPS GitHub: https://github.com/OpenSIPS/opensips
- OpenSIPS Mailing List: https://lists.opensips.org/
- SIP Security RFCs: RFC 3261, RFC 3325, RFC 4474

**Success Criteria:**
- ✅ All OpenSIPS security modules evaluated
- ✅ Community solutions researched
- ✅ Architecture decisions documented
- ✅ POC completed for key modules
- ✅ Project plan updated based on findings

**Note:** This research phase is critical. Do not proceed to Phase 1 implementation until research is complete and decisions are documented.

---

### Phase 1: Registration Security Foundation

**Goal:** Secure the registration process and track registration attempts

#### 1.1 Registration Status Tracking

**Objective:** Track registration state (pending, registered, failed, expired)

**Implementation:**
- Add `status` column to `endpoint_locations` table
- Update status on registration response
- Query by status for monitoring

**Database Changes:**
```sql
ALTER TABLE endpoint_locations 
ADD COLUMN status VARCHAR(20) DEFAULT 'pending',
ADD COLUMN last_response_code INT DEFAULT NULL,
ADD COLUMN last_response_reason VARCHAR(255) DEFAULT NULL,
ADD COLUMN registered_at DATETIME DEFAULT NULL,
ADD COLUMN failed_at DATETIME DEFAULT NULL;

CREATE INDEX idx_endpoint_locations_status ON endpoint_locations(status);
CREATE INDEX idx_endpoint_locations_registered_at ON endpoint_locations(registered_at);
```

**OpenSIPS Changes:**
- Update `onreply_route` to set status based on response
- Update REGISTER handler to set initial status
- Add status queries to monitoring

**Files to Modify:**
- `config/opensips.cfg.template` - Add status updates in onreply_route
- `scripts/init-database.sh` - Add status column migration
- `scripts/cleanup-expired-endpoints.sh` - Update to handle status

#### 1.2 Response-Based Cleanup

**Objective:** Immediately clean up failed registrations

**Implementation:**
- Delete endpoint_location records on registration failure (4xx, 5xx)
- Keep successful registrations (200 OK)
- Handle de-registration (Expires: 0) separately

**OpenSIPS Changes:**
```opensips
onreply_route {
    if (is_method("REGISTER")) {
        if ($rs >= 400) {
            # Registration failed - delete endpoint_location record
            $var(endpoint_aor) = $tU + "@" + $(tu{uri.domain});
            sql_query("DELETE FROM endpoint_locations WHERE aor='$var(endpoint_aor)'");
            xlog("L_NOTICE", "Registration failed ($rs), deleted endpoint_location for $var(endpoint_aor)\n");
        } else if ($rs == 200) {
            # Registration successful - update status
            $var(endpoint_aor) = $tU + "@" + $(tu{uri.domain});
            sql_query("UPDATE endpoint_locations SET status='registered', registered_at=NOW(), last_response_code=200 WHERE aor='$var(endpoint_aor)'");
        }
    }
}
```

**Files to Modify:**
- `config/opensips.cfg.template` - Add cleanup logic to onreply_route

#### 1.3 Failed Registration Tracking

**Objective:** Track all failed registration attempts for threat detection

**Database Schema:**
```sql
CREATE TABLE failed_registrations (
    id INT AUTO_INCREMENT PRIMARY KEY,
    aor VARCHAR(255) NOT NULL,
    source_ip VARCHAR(45) NOT NULL,
    source_port VARCHAR(10) NOT NULL,
    user_agent VARCHAR(255) DEFAULT NULL,
    response_code INT NOT NULL,
    response_reason VARCHAR(255) DEFAULT NULL,
    attempt_time DATETIME NOT NULL,
    expires_header INT DEFAULT NULL,
    INDEX idx_aor_time (aor, attempt_time),
    INDEX idx_source_ip_time (source_ip, attempt_time),
    INDEX idx_attempt_time (attempt_time),
    INDEX idx_response_code (response_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

**OpenSIPS Changes:**
- Log failed registrations to database in `onreply_route`
- Include source IP, user agent, response code
- Enable pattern detection

**Files to Create:**
- `scripts/init-database.sh` - Add failed_registrations table creation
- `scripts/analyze-failed-registrations.sh` - Analysis tool

**Files to Modify:**
- `config/opensips.cfg.template` - Add failed registration logging

---

### Phase 2: Rate Limiting & Attack Mitigation

**Goal:** Prevent flood attacks and limit suspicious activity

#### 2.1 IP-Based Rate Limiting

**Objective:** Limit requests per IP address

**Implementation Options:**
- Use OpenSIPS `ipban` module
- Custom rate limiting using database
- Use `htable` for in-memory rate limiting

**Database Schema:**
```sql
CREATE TABLE rate_limits (
    ip_address VARCHAR(45) PRIMARY KEY,
    request_count INT DEFAULT 0,
    window_start DATETIME NOT NULL,
    blocked_until DATETIME DEFAULT NULL,
    violation_count INT DEFAULT 0,
    last_violation DATETIME DEFAULT NULL,
    INDEX idx_blocked_until (blocked_until),
    INDEX idx_window_start (window_start)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

**Rate Limit Rules:**
- REGISTER: 10 requests per minute per IP
- INVITE: 30 requests per minute per IP
- OPTIONS: 60 requests per minute per IP
- Other methods: 100 requests per minute per IP

**OpenSIPS Changes:**
- Add rate limiting checks in request route
- Block IPs that exceed limits
- Log violations to database

**Files to Create:**
- `scripts/init-database.sh` - Add rate_limits table
- `scripts/unblock-ip.sh` - Manual IP unblocking tool

**Files to Modify:**
- `config/opensips.cfg.template` - Add rate limiting logic

#### 2.2 Registration-Specific Rate Limiting

**Objective:** Detect and block brute force registration attacks

**Implementation:**
- Track failed registration attempts per IP
- Block IPs with excessive failures
- Track failed attempts per AoR (username enumeration detection)

**Database Schema:**
```sql
CREATE TABLE registration_attempts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    source_ip VARCHAR(45) NOT NULL,
    aor VARCHAR(255) DEFAULT NULL,
    success BOOLEAN DEFAULT FALSE,
    response_code INT NOT NULL,
    attempt_time DATETIME NOT NULL,
    INDEX idx_source_ip_time (source_ip, attempt_time),
    INDEX idx_aor_time (aor, attempt_time),
    INDEX idx_attempt_time (attempt_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

**Blocking Rules:**
- Block IP after 5 failed registrations in 5 minutes
- Block IP after 10 failed registrations in 1 hour
- Alert on username enumeration (many different AoRs from same IP)

**Files to Create:**
- `scripts/init-database.sh` - Add registration_attempts table
- `scripts/detect-brute-force.sh` - Brute force detection tool

**Files to Modify:**
- `config/opensips.cfg.template` - Add registration rate limiting

#### 2.3 Flood Detection

**Objective:** Detect and mitigate SIP flood attacks

**Implementation:**
- Track requests per IP over time windows
- Detect sudden spikes in traffic
- Automatically block flood sources

**Database Schema:**
```sql
CREATE TABLE flood_detection (
    id INT AUTO_INCREMENT PRIMARY KEY,
    source_ip VARCHAR(45) NOT NULL,
    request_count INT NOT NULL,
    window_start DATETIME NOT NULL,
    window_end DATETIME NOT NULL,
    method VARCHAR(20) DEFAULT NULL,
    blocked BOOLEAN DEFAULT FALSE,
    INDEX idx_source_ip_window (source_ip, window_start),
    INDEX idx_window (window_start, window_end)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

**Detection Rules:**
- Alert on >100 requests per second from single IP
- Alert on >1000 requests per minute from single IP
- Auto-block IPs exceeding thresholds

**Files to Create:**
- `scripts/init-database.sh` - Add flood_detection table
- `scripts/detect-floods.sh` - Flood detection analysis tool

**Files to Modify:**
- `config/opensips.cfg.template` - Add flood detection logic

---

### Phase 3: Monitoring & Alerting

**Goal:** Provide visibility and alerting for security events

#### 3.1 Security Event Logging

**Objective:** Comprehensive logging of all security events

**Database Schema:**
```sql
CREATE TABLE security_events (
    id INT AUTO_INCREMENT PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL,
    severity VARCHAR(20) NOT NULL,
    source_ip VARCHAR(45) DEFAULT NULL,
    aor VARCHAR(255) DEFAULT NULL,
    description TEXT,
    event_time DATETIME NOT NULL,
    resolved BOOLEAN DEFAULT FALSE,
    resolved_at DATETIME DEFAULT NULL,
    INDEX idx_event_type_time (event_type, event_time),
    INDEX idx_source_ip_time (source_ip, event_time),
    INDEX idx_severity_time (severity, event_time),
    INDEX idx_unresolved (resolved, event_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

**Event Types:**
- `registration_failure` - Failed registration attempt
- `brute_force_detected` - Brute force attack detected
- `flood_detected` - Flood attack detected
- `rate_limit_exceeded` - Rate limit violation
- `scanner_detected` - Known scanner detected
- `ip_blocked` - IP address blocked
- `username_enumeration` - Possible username enumeration

**Severity Levels:**
- `info` - Informational events
- `warning` - Suspicious activity
- `error` - Security violations
- `critical` - Active attacks

**Files to Create:**
- `scripts/init-database.sh` - Add security_events table
- `scripts/view-security-events.sh` - View security events
- `scripts/resolve-security-event.sh` - Mark events as resolved

**Files to Modify:**
- `config/opensips.cfg.template` - Add security event logging

#### 3.2 Alerting System

**Objective:** Send alerts for critical security events

**Implementation:**
- Email alerts for critical events
- SMS alerts for critical events (optional)
- Webhook notifications (optional)
- Alert aggregation to prevent spam

**Alert Rules:**
- Critical: Immediate email + SMS
- Error: Email within 5 minutes
- Warning: Email digest (hourly)
- Info: Log only

**Database Schema:**
```sql
CREATE TABLE alert_config (
    id INT AUTO_INCREMENT PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL,
    severity VARCHAR(20) NOT NULL,
    email_enabled BOOLEAN DEFAULT TRUE,
    sms_enabled BOOLEAN DEFAULT FALSE,
    webhook_url VARCHAR(255) DEFAULT NULL,
    cooldown_minutes INT DEFAULT 60,
    last_alert_time DATETIME DEFAULT NULL,
    UNIQUE KEY unique_event_severity (event_type, severity)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

**Files to Create:**
- `scripts/send-alert.sh` - Alert sending script
- `scripts/configure-alerts.sh` - Alert configuration tool
- `scripts/init-database.sh` - Add alert_config table

#### 3.3 Statistics & Reporting

**Objective:** Provide security statistics and reports

**Statistics to Track:**
- Failed registration attempts (per hour/day)
- Blocked IPs count
- Brute force attacks detected
- Flood attacks detected
- Top attacking IPs
- Top targeted AoRs
- Security event trends

**Database Views:**
```sql
CREATE VIEW security_stats_hourly AS
SELECT 
    DATE_FORMAT(event_time, '%Y-%m-%d %H:00:00') as hour,
    event_type,
    COUNT(*) as event_count,
    COUNT(DISTINCT source_ip) as unique_ips
FROM security_events
GROUP BY hour, event_type;

CREATE VIEW top_attacking_ips AS
SELECT 
    source_ip,
    COUNT(*) as attack_count,
    COUNT(DISTINCT event_type) as attack_types,
    MIN(event_time) as first_seen,
    MAX(event_time) as last_seen
FROM security_events
WHERE severity IN ('error', 'critical')
GROUP BY source_ip
ORDER BY attack_count DESC;
```

**Files to Create:**
- `scripts/security-report.sh` - Generate security reports
- `scripts/view-security-stats.sh` - View security statistics
- `scripts/init-database.sh` - Add security statistics views

---

### Phase 4: Advanced Threat Detection

**Goal:** Advanced pattern detection and threat intelligence

#### 4.1 Username Enumeration Detection

**Objective:** Detect attempts to enumerate valid usernames

**Detection Logic:**
- Track unique AoRs attempted from same IP
- Alert on >10 different AoRs from single IP in short time
- Track success rate per IP (high success = valid user, low success = enumeration)

**Implementation:**
- Query `failed_registrations` table for patterns
- Analyze registration attempts per IP
- Flag suspicious enumeration patterns

**Files to Create:**
- `scripts/detect-username-enumeration.sh` - Enumeration detection tool

#### 4.2 Geographic Anomaly Detection

**Objective:** Detect suspicious geographic patterns

**Implementation:**
- Track source IP geolocation (optional, requires GeoIP database)
- Alert on registrations from unusual locations
- Track IP reputation (optional, requires threat intelligence feeds)

**Database Schema:**
```sql
CREATE TABLE ip_reputation (
    ip_address VARCHAR(45) PRIMARY KEY,
    country_code VARCHAR(2) DEFAULT NULL,
    is_vpn BOOLEAN DEFAULT FALSE,
    is_proxy BOOLEAN DEFAULT FALSE,
    is_tor BOOLEAN DEFAULT FALSE,
    reputation_score INT DEFAULT 50,
    last_updated DATETIME NOT NULL,
    INDEX idx_reputation_score (reputation_score),
    INDEX idx_country (country_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

**Files to Create:**
- `scripts/update-ip-reputation.sh` - Update IP reputation (optional)
- `scripts/init-database.sh` - Add ip_reputation table

#### 4.3 Behavioral Analysis

**Objective:** Detect anomalous behavior patterns

**Analysis Areas:**
- Unusual registration times
- Unusual request patterns
- Unusual user agent strings
- Unusual request rates

**Implementation:**
- Baseline normal behavior
- Detect deviations from baseline
- Alert on anomalies

**Files to Create:**
- `scripts/analyze-behavior.sh` - Behavioral analysis tool

---

### Phase 5: IP Management & Blocking

**Goal:** Comprehensive IP blocking and management

#### 5.1 IP Blocking System

**Objective:** Manage blocked IPs with expiration and whitelisting

**Database Schema:**
```sql
CREATE TABLE blocked_ips (
    id INT AUTO_INCREMENT PRIMARY KEY,
    ip_address VARCHAR(45) NOT NULL,
    reason VARCHAR(255) NOT NULL,
    blocked_at DATETIME NOT NULL,
    expires_at DATETIME DEFAULT NULL,
    auto_blocked BOOLEAN DEFAULT TRUE,
    unblocked_at DATETIME DEFAULT NULL,
    unblock_reason VARCHAR(255) DEFAULT NULL,
    INDEX idx_ip_address (ip_address),
    INDEX idx_expires_at (expires_at),
    INDEX idx_active (expires_at, unblocked_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE whitelisted_ips (
    id INT AUTO_INCREMENT PRIMARY KEY,
    ip_address VARCHAR(45) NOT NULL UNIQUE,
    description VARCHAR(255) DEFAULT NULL,
    created_at DATETIME NOT NULL,
    created_by VARCHAR(100) DEFAULT NULL,
    INDEX idx_ip_address (ip_address)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

**OpenSIPS Changes:**
- Check blocked_ips table in request route
- Check whitelisted_ips table (bypass blocking)
- Auto-expire blocks based on expires_at

**Files to Create:**
- `scripts/block-ip.sh` - Manually block an IP
- `scripts/unblock-ip.sh` - Unblock an IP
- `scripts/list-blocked-ips.sh` - List blocked IPs
- `scripts/whitelist-ip.sh` - Whitelist an IP
- `scripts/init-database.sh` - Add blocked_ips and whitelisted_ips tables

**Files to Modify:**
- `config/opensips.cfg.template` - Add IP blocking checks

#### 5.2 Automatic Block Expiration

**Objective:** Automatically unblock IPs after expiration period

**Implementation:**
- Cleanup script to unblock expired IPs
- Configurable expiration periods by block reason
- Log unblocking events

**Files to Create:**
- `scripts/expire-blocked-ips.sh` - Expire old blocks
- `scripts/cleanup-expired-endpoints.sh` - Add IP block expiration (or separate script)

---

## Implementation Plan

### Phase 0: Research & Evaluation (Week 1)
1. ⏳ Research OpenSIPS security modules
2. ⏳ Research community solutions
3. ⏳ Document architecture decisions
4. ⏳ Complete proof of concept
5. ⏳ Update project plan based on findings

### Phase 1: Foundation (Weeks 2-3)
1. ✅ Create project plan document
2. ⏳ Implement registration status tracking
3. ⏳ Implement response-based cleanup
4. ⏳ Create failed_registrations table
5. ⏳ Add failed registration logging

### Phase 2: Rate Limiting (Weeks 4-5)
1. ⏳ Implement IP-based rate limiting
2. ⏳ Implement registration-specific rate limiting
3. ⏳ Add flood detection
4. ⏳ Create blocking mechanisms

### Phase 3: Monitoring (Weeks 6-7)
1. ⏳ Create security_events table
2. ⏳ Implement security event logging
3. ⏳ Create alerting system
4. ⏳ Add statistics and reporting

### Phase 4: Advanced Detection (Weeks 8-9)
1. ⏳ Implement username enumeration detection
2. ⏳ Add geographic anomaly detection (optional)
3. ⏳ Implement behavioral analysis

### Phase 5: IP Management (Weeks 10-11)
1. ⏳ Create IP blocking system
2. ⏳ Add whitelisting
3. ⏳ Implement automatic expiration

## Database Schema Summary

### New Tables
1. `failed_registrations` - Track failed registration attempts
2. `rate_limits` - Track rate limiting per IP
3. `registration_attempts` - Track registration attempts for brute force detection
4. `flood_detection` - Track flood attack patterns
5. `security_events` - Comprehensive security event log
6. `alert_config` - Alert configuration
7. `blocked_ips` - IP blocking management
8. `whitelisted_ips` - IP whitelist
9. `ip_reputation` - IP reputation tracking (optional)

### Modified Tables
1. `endpoint_locations` - Add status tracking columns

### New Views
1. `security_stats_hourly` - Hourly security statistics
2. `top_attacking_ips` - Top attacking IPs

## Scripts to Create

### Database Management
- `scripts/init-database.sh` - Add all new tables
- `scripts/migrate-security-schema.sh` - Migration script for existing installations

### Analysis Tools
- `scripts/analyze-failed-registrations.sh`
- `scripts/detect-brute-force.sh`
- `scripts/detect-floods.sh`
- `scripts/detect-username-enumeration.sh`
- `scripts/analyze-behavior.sh`

### Management Tools
- `scripts/block-ip.sh`
- `scripts/unblock-ip.sh`
- `scripts/list-blocked-ips.sh`
- `scripts/whitelist-ip.sh`
- `scripts/view-security-events.sh`
- `scripts/view-security-stats.sh`
- `scripts/security-report.sh`
- `scripts/configure-alerts.sh`
- `scripts/send-alert.sh`
- `scripts/expire-blocked-ips.sh`

## Configuration Changes

### OpenSIPS Config (`config/opensips.cfg.template`)
- Add rate limiting checks in request route
- Add IP blocking checks
- Add security event logging
- Add response-based cleanup in onreply_route
- Add status updates in onreply_route
- Add flood detection logic

### Module Requirements

**Note:** Module requirements will be determined during Phase 0 research. Potential modules include:

- `pike` module - Flood detection (likely to use)
- `ratelimit` module - Rate limiting (evaluate vs. custom)
- `ipban` module - IP blocking (evaluate vs. custom)
- `htable` module - In-memory rate limiting (evaluate vs. database)
- `permissions` module - IP-based access control (evaluate)
- `statistics` module - Built-in statistics (likely to use)
- `geoip` module - Geographic detection (optional)

**Research Required:** Phase 0 will determine which modules to use vs. custom implementation.

## Testing Plan

### Unit Testing
- Test rate limiting logic
- Test IP blocking/unblocking
- Test status tracking
- Test failed registration logging

### Integration Testing
- Test end-to-end registration flow with security
- Test brute force detection
- Test flood detection
- Test alerting system

### Performance Testing
- Test rate limiting performance impact
- Test database query performance
- Test blocking check performance

## Documentation to Create

1. **Security Configuration Guide** - How to configure security features
2. **Threat Detection Guide** - How to use threat detection tools
3. **Alerting Setup Guide** - How to configure alerts
4. **IP Management Guide** - How to manage blocked/whitelisted IPs
5. **Security Monitoring Guide** - How to monitor security events
6. **Troubleshooting Guide** - Common security issues and solutions

## Success Criteria

### Phase 1 Complete When:
- ✅ Registration status tracked in database
- ✅ Failed registrations logged
- ✅ Response-based cleanup working
- ✅ Can query registration status

### Phase 2 Complete When:
- ✅ Rate limiting active and blocking excessive requests
- ✅ Brute force detection working
- ✅ Flood detection working
- ✅ IPs automatically blocked on violations

### Phase 3 Complete When:
- ✅ Security events logged to database
- ✅ Alerts sent for critical events
- ✅ Statistics and reports available
- ✅ Security dashboard functional

### Phase 4 Complete When:
- ✅ Username enumeration detected
- ✅ Behavioral anomalies detected
- ✅ Advanced patterns identified

### Phase 5 Complete When:
- ✅ IP blocking system functional
- ✅ Whitelisting working
- ✅ Automatic expiration working
- ✅ Management tools available

## Future Enhancements (Post-Project)

- Integration with threat intelligence feeds
- Machine learning for anomaly detection
- Real-time security dashboard (web UI)
- Integration with SIEM systems
- Automated response actions (beyond blocking)
- Distributed threat intelligence sharing

## Related Documentation

- [Endpoint Location Creation](ENDPOINT-LOCATION-CREATION.md) - Current registration handling
- [Endpoint Cleanup](ENDPOINT-CLEANUP.md) - Current cleanup procedures
- [OpenSIPS Routing Logic](opensips-routing-logic.md) - Current routing implementation

## Notes

- This is a comprehensive project that should be implemented in phases
- Each phase builds on the previous one
- Testing is critical at each phase
- Documentation should be updated as features are implemented
- Consider performance impact of security checks
- Balance security with usability
