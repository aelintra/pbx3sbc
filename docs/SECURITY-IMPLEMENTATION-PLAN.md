# Security & Threat Detection - Detailed Implementation Plan

**Date:** January 2026  
**Status:** 📋 Planning Phase  
**Confidence Levels:** ✅ High | ⚠️ Medium | 🔍 Needs Research

---

## Overview

This document provides a detailed, step-by-step implementation plan for the Security & Threat Detection project, with confidence levels for each task and identification of areas requiring additional research.

## Industry Context: Why Security is Critical

**VoIP providers actively block IP addresses and implement security measures** - they do not simply tolerate attacks. This plan implements industry-standard security practices for Session Border Controllers (SBCs).

### Why VoIP Security Matters

**Real Threats:**
- **Toll Fraud:** Attackers scan for weak IP phones to make unauthorized international calls, resulting in massive bills
- **Denial of Service (DoS):** Flooding servers with SIP requests can crash services for legitimate users
- **Call Quality Issues:** Malicious traffic consumes bandwidth, causing latency and call dropouts
- **Resource Depletion:** Attacks can exhaust server resources, impacting legitimate users

**Industry Standard Practices:**
1. **Active IP Blocking** - Block malicious IPs automatically (Phase 5)
2. **Rate Limiting** - Restrict request rates instead of full blocks (Phase 2)
3. **Flood Detection** - Detect and mitigate DoS attacks (Phase 2.3)
4. **Geo-Fencing/Allowlisting** - Restrict access to trusted IPs (Phase 5.1)
5. **Blacklisting** - Block known malicious IPs automatically (Phase 5.1)
6. **Brute Force Protection** - Detect and block password guessing attacks (Phase 2.2.3)

**Our Implementation:**
This plan implements all standard VoIP provider security practices, ensuring our OpenSIPS SBC provides enterprise-grade protection for Asterisk backends.

## Implementation Best Practices

### ⚠️ CRITICAL: Prefer Standard OpenSIPS Approaches

**Principle:** Use standard OpenSIPS modules and community-tested solutions whenever possible. Only build custom implementations when standard approaches don't meet our requirements.

**Why:**
- Leverages community-tested, maintained code
- Reduces technical debt
- Easier to maintain and upgrade
- Better performance (optimized modules)
- Follows OpenSIPS best practices

**Decision Process:**
1. **First:** Research standard OpenSIPS modules for the feature
2. **Test:** Evaluate if module meets requirements (POC)
3. **Decide:** Use module if it meets majority/all requirements
4. **Custom Only:** Build custom solution only if module doesn't meet critical requirements
5. **Document:** Always document why custom approach was chosen over module

### ⚠️ CRITICAL: Always Check Module Documentation Before Implementation

Before implementing any OpenSIPS module feature:
1. **Look up the module documentation** at: https://opensips.org/html/docs/modules/3.6.x/
2. **Review all available parameters** (`modparam` options)
3. **Review all available functions** (e.g., `pike_check_req()`, `rl_check()`, etc.)
4. **Review all available events** (e.g., `E_PIKE_BLOCKED`)
5. **Check for examples** in the documentation
6. **Verify compatibility** with OpenSIPS 3.6.3
7. **Compare with our plan** to ensure no conflicts or missing features

This ensures we use modules correctly and don't miss important features or best practices.

---

## Phase 0: Research & Evaluation (Week 1)

### 0.1 OpenSIPS Security Modules Research ✅ **HIGH CONFIDENCE**

**Status:** ✅ Basic research complete (see `docs/SECURITY-MODULES-RESEARCH.md`)

**Findings:**
- ✅ `pike.so` - Available for flood detection
- ✅ `ratelimit.so` - Available for rate limiting
- ✅ `permissions.so` - Available for IP access control (can replace ipban)
- ❌ `ipban.so` - Not available (use `permissions` or custom scripting)
- ⚠️ `htable.so` - Not found (may be built-in)

**Remaining Tasks:**

#### Task 0.1.1: Test Pike Module ✅ **COMPLETE**
- **What:** Load and test `pike` module in test environment
- **Why:** Verify flood detection capabilities and performance impact
- **Status:** ✅ **COMPLETE** - Module tested and merged to main
- **Results:** Pike module is working without disruption, benign behavior confirmed
- **Deliverable:** ✅ POC test results and configuration examples (see `docs/PHASE-0-PIKE-RESULTS.md`)

#### Task 0.1.2: Test Ratelimit Module ⏸️ **DEFERRED**
- **What:** Load and test `ratelimit` module
- **Why:** Verify rate limiting capabilities and algorithm options
- **Status:** ⏸️ **DEFERRED** - Moved down priority list
- **Reason:** Need to better understand module API and implications in live system before implementation
- **Research Needed:**
  - Module API documentation review (actual parameters and functions)
  - Algorithm selection (TAILDROP, RED, etc.)
  - Per-method rate limiting configuration
  - Per-IP vs per-user rate limiting
  - Performance impact
  - Live system implications
  - Integration with MySQL for persistence
- **Deliverable:** POC test results and configuration examples

#### Task 0.1.3: Test Permissions Module ⚠️ **MEDIUM CONFIDENCE**
- **What:** Load and test `permissions` module for IP blocking
- **Why:** Evaluate as replacement for missing `ipban` module
- **Confidence:** ⚠️ Medium - Need to test database-backed ACLs
- **Research Needed:**
  - Database schema for permissions module
  - Performance of database lookups
  - Multi-tenant support
  - Whitelist/blacklist management
- **Deliverable:** POC test results and schema examples

#### Task 0.1.4: Architecture Decision Document ✅ **HIGH CONFIDENCE**
- **What:** Document decisions on module usage vs custom implementation
- **Why:** Guide implementation approach
- **Confidence:** ✅ High - Can document based on research findings
- **Deliverable:** `docs/SECURITY-ARCHITECTURE-DECISIONS.md`

---

## Phase 1: Registration Security Foundation (Weeks 2-3)

### 1.1 Failed Registration Tracking ✅ **HIGH CONFIDENCE**

**Objective:** Track all failed registration attempts in database

**Implementation Steps:**

#### Step 1.1.1: Create Database Table ✅ **HIGH CONFIDENCE**
- **What:** Create `failed_registrations` table
- **Where:** `scripts/init-database.sh`
- **Confidence:** ✅ High - Standard SQL table creation
- **Schema:**
  ```sql
  CREATE TABLE failed_registrations (
      id INT AUTO_INCREMENT PRIMARY KEY,
      username VARCHAR(64) NOT NULL,
      domain VARCHAR(128) NOT NULL,
      source_ip VARCHAR(45) NOT NULL,
      source_port INT NOT NULL,
      user_agent VARCHAR(255) DEFAULT NULL,
      response_code INT NOT NULL,
      response_reason VARCHAR(255) DEFAULT NULL,
      attempt_time DATETIME NOT NULL,
      expires_header INT DEFAULT NULL,
      INDEX idx_username_domain_time (username, domain, attempt_time),
      INDEX idx_source_ip_time (source_ip, attempt_time),
      INDEX idx_attempt_time (attempt_time),
      INDEX idx_response_code (response_code)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ```
- **Note:** Using `username` and `domain` instead of `aor` to match `location` table structure

#### Step 1.1.2: Add Logging in onreply_route ✅ **HIGH CONFIDENCE**
- **What:** Log failed registrations (4xx, 5xx responses) to database
- **Where:** `config/opensips.cfg.template` - `onreply_route[handle_reply_reg]`
- **Confidence:** ✅ High - We know how onreply_route works, have access to `$rs`, `$rr`, `$si`, `$sp`
- **Implementation:**
  ```opensips
  onreply_route[handle_reply_reg] {
      if (is_method("REGISTER")) {
          if (t_check_status("2[0-9][0-9]")) {
              # Success - existing save() logic
              ...
          } else if ($rs >= 400) {
              # Failed registration - log to database
              $var(query) = "INSERT INTO failed_registrations 
                  (username, domain, source_ip, source_port, user_agent, 
                   response_code, response_reason, attempt_time) 
                  VALUES ('" + $tU + "', '" + $(tu{uri.domain}) + "', 
                          '" + $si + "', " + $sp + ", '" + $ua + "', 
                          " + $rs + ", '" + $rr + "', NOW())";
              sql_query($var(query));
              xlog("REGISTER: Failed registration logged - $tU@$(tu{uri.domain}) from $si:$sp, response $rs $rr\n");
          }
      }
  }
  ```
- **Challenges:**
  - Need to capture source IP:port from original request (may need AVP storage)
  - User agent extraction from request (need to store in request route)
  - SQL injection prevention (use parameterized queries if available)

#### Step 1.1.3: Store Request Metadata in Request Route ⚠️ **MEDIUM CONFIDENCE**
- **What:** Capture source IP, port, user agent in request route for use in onreply_route
- **Where:** `config/opensips.cfg.template` - REGISTER handling block
- **Confidence:** ⚠️ Medium - Need to verify AVP persistence across transaction boundaries
- **Implementation:**
  ```opensips
  if (is_method("REGISTER")) {
      # Store request metadata for security tracking
      $avp(reg_source_ip) = $si;
      $avp(reg_source_port) = $sp;
      $avp(reg_user_agent) = $ua;
      # These AVPs should persist to onreply_route via onreply_avp_mode=1
  }
  ```
- **Research Needed:**
  - Verify `onreply_avp_mode=1` makes AVPs available in onreply_route
  - Test AVP persistence across transaction boundaries
  - Check if transaction-scoped AVPs (`tu:`) are needed

### 1.2 Registration Status Tracking ✅ **HIGH CONFIDENCE**

**Objective:** Track registration status (pending, registered, failed, expired)

**Note:** Since we're using OpenSIPS `location` table (usrloc module), we can't directly modify it. Instead, we'll create a separate tracking table.

#### Step 1.2.1: Create Registration Status Table ✅ **HIGH CONFIDENCE**
- **What:** Create `registration_status` table to track registration state
- **Where:** `scripts/init-database.sh`
- **Confidence:** ✅ High - Standard SQL table creation
- **Schema:**
  ```sql
  CREATE TABLE registration_status (
      username VARCHAR(64) NOT NULL,
      domain VARCHAR(128) NOT NULL,
      status VARCHAR(20) DEFAULT 'pending',
      last_response_code INT DEFAULT NULL,
      last_response_reason VARCHAR(255) DEFAULT NULL,
      registered_at DATETIME DEFAULT NULL,
      failed_at DATETIME DEFAULT NULL,
      last_attempt_time DATETIME DEFAULT NULL,
      PRIMARY KEY (username, domain),
      INDEX idx_status (status),
      INDEX idx_registered_at (registered_at),
      INDEX idx_failed_at (failed_at)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ```

#### Step 1.2.2: Update Status in onreply_route ✅ **HIGH CONFIDENCE**
- **What:** Update registration status based on response code
- **Where:** `config/opensips.cfg.template` - `onreply_route[handle_reply_reg]`
- **Confidence:** ✅ High - Standard SQL UPDATE operations
- **Implementation:**
  ```opensips
  if ($rs >= 200 && $rs < 300) {
      # Success - update status to 'registered'
      $var(update_query) = "INSERT INTO registration_status 
          (username, domain, status, last_response_code, last_response_reason, registered_at, last_attempt_time) 
          VALUES ('" + $tU + "', '" + $(tu{uri.domain}) + "', 'registered', " + $rs + ", '" + $rr + "', NOW(), NOW())
          ON DUPLICATE KEY UPDATE 
          status='registered', last_response_code=" + $rs + ", 
          last_response_reason='" + $rr + "', registered_at=NOW(), last_attempt_time=NOW()";
      sql_query($var(update_query));
  } else if ($rs >= 400) {
      # Failed - update status to 'failed'
      $var(update_query) = "INSERT INTO registration_status 
          (username, domain, status, last_response_code, last_response_reason, failed_at, last_attempt_time) 
          VALUES ('" + $tU + "', '" + $(tu{uri.domain}) + "', 'failed', " + $rs + ", '" + $rr + "', NOW(), NOW())
          ON DUPLICATE KEY UPDATE 
          status='failed', last_response_code=" + $rs + ", 
          last_response_reason='" + $rr + "', failed_at=NOW(), last_attempt_time=NOW()";
      sql_query($var(update_query));
  }
  ```

### 1.3 Response-Based Cleanup ⚠️ **MEDIUM CONFIDENCE**

**Objective:** Clean up failed registrations immediately (not needed since we use usrloc `save()` which only saves on success)

**Note:** With usrloc module, `save()` only creates records on 200 OK, so failed registrations don't create location records. This may not be needed, but we can add explicit cleanup for safety.

#### Step 1.3.1: Add Cleanup Logic ⚠️ **MEDIUM CONFIDENCE**
- **What:** Delete location records on registration failure (if they exist)
- **Where:** `config/opensips.cfg.template` - `onreply_route[handle_reply_reg]`
- **Confidence:** ⚠️ Medium - Need to verify if location records can exist for failed registrations
- **Research Needed:**
  - Can location records exist for failed registrations with usrloc module?
  - Should we use OpenSIPS MI commands or direct SQL?
  - Performance impact of cleanup operations

---

## Phase 2: Rate Limiting & Attack Mitigation (Weeks 4-5)

### 2.1 IP-Based Rate Limiting ⏸️ **DEFERRED**

**Objective:** Limit requests per IP address

**Status:** ⏸️ **DEFERRED** - Moved down priority list pending better understanding of module API and live system implications.

**⚠️ STANDARD APPROACH FIRST:** Always test standard OpenSIPS modules before building custom solutions.

#### Option A: Use Ratelimit Module ⏸️ **DEFERRED - NEEDS DOCUMENTATION REVIEW**
- **What:** Load and configure `ratelimit` module (standard OpenSIPS module)
- **Status:** ⏸️ **DEFERRED** - Module API needs proper documentation review before implementation
- **Why Preferred:** Standard OpenSIPS module, community-tested, maintained, optimized
- **Why Deferred:** 
  - Module API differs from assumptions (parameters don't match expected)
  - Need to review official documentation thoroughly before implementation
  - Want to understand live system implications before deploying
- **Research Needed:**
  - **CRITICAL:** Review official module documentation at https://opensips.org/html/docs/modules/3.6.x/ratelimit.html
  - Module configuration parameters (actual API)
  - Function syntax and parameters (actual API)
  - Rate limit algorithm selection (TAILDROP, RED, etc.)
  - Per-IP rate limiting setup
  - Performance impact
  - Integration with MySQL for persistence (if needed)
  - Live system implications
- **Pros:** Built-in, well-tested, efficient, community-maintained, follows OpenSIPS best practices
- **Cons:** Need to learn module API (but worth it to avoid technical debt)
- **Decision Criteria:** Use this if it meets majority/all requirements

#### Option B: Custom Database Rate Limiting ⚠️ **FALLBACK ONLY - Use Only If Option A Doesn't Meet Requirements**
- **What:** Implement custom rate limiting using database queries
- **Confidence:** ✅ High - We know SQL and OpenSIPS scripting
- **When to Use:** Only if `ratelimit` module doesn't meet critical requirements
- **Implementation:**
  ```opensips
  route[CHECK_RATE_LIMIT] {
      $var(query) = "SELECT request_count, window_start, blocked_until 
          FROM rate_limits WHERE ip_address='" + $si + "'";
      if (sql_query($var(query), "$avp(rate_limit_info)")) {
          # Check if blocked
          # Check if window expired
          # Increment counter or create new entry
          # Block if threshold exceeded
      }
  }
  ```
- **Pros:** Full control, can customize exactly
- **Cons:** Database query overhead, more code to maintain, technical debt, not standard
- **Documentation Required:** Must document why custom approach was chosen over module

**Recommendation:** 
1. **First:** Test `ratelimit` module thoroughly (Option A) - this is the standard OpenSIPS approach
2. **Only if needed:** Use custom approach (Option B) if module doesn't meet critical requirements
3. **Document:** If using Option B, document exactly why Option A didn't meet requirements

#### Step 2.1.1: Create Rate Limits Table ⚠️ **ONLY IF RATELIMIT MODULE DOESN'T MEET REQUIREMENTS**
- **What:** Create `rate_limits` table (only if ratelimit module doesn't support persistence)
- **Where:** `scripts/init-database.sh`
- **Confidence:** ✅ High - Standard SQL table creation
- **When to Use:** Only if `ratelimit` module doesn't support database persistence or we need custom tracking
- **Schema:**
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

#### Step 2.1.2: Implement Rate Limiting Logic 🔍 **NEEDS RESEARCH**
- **What:** Add rate limiting checks in request route
- **Where:** `config/opensips.cfg.template` - `route{}` (early, before domain check)
- **Confidence:** 🔍 Needs Research - Depends on module choice
- **Research Needed:**
  - If using `ratelimit` module: Learn API and configuration
  - If using custom: Design efficient rate limiting algorithm
  - Window-based vs token bucket algorithm
  - Performance optimization (caching, batch updates)

### 2.2 Registration-Specific Rate Limiting ✅ **HIGH CONFIDENCE**

**Objective:** Detect and block brute force registration attacks

**⚠️ NOTE:** This section uses custom database tracking for registration attempts. This is acceptable because:
- We need to track registration attempts for analysis/reporting (not just rate limiting)
- The `ratelimit` module handles rate limiting, but we need detailed logging
- This complements the standard `ratelimit` module (doesn't replace it)

#### Step 2.2.1: Create Registration Attempts Table ✅ **HIGH CONFIDENCE**
- **What:** Create `registration_attempts` table
- **Where:** `scripts/init-database.sh`
- **Confidence:** ✅ High - Standard SQL table creation
- **Schema:**
  ```sql
  CREATE TABLE registration_attempts (
      id INT AUTO_INCREMENT PRIMARY KEY,
      source_ip VARCHAR(45) NOT NULL,
      username VARCHAR(64) DEFAULT NULL,
      domain VARCHAR(128) DEFAULT NULL,
      success BOOLEAN DEFAULT FALSE,
      response_code INT NOT NULL,
      attempt_time DATETIME NOT NULL,
      INDEX idx_source_ip_time (source_ip, attempt_time),
      INDEX idx_username_domain_time (username, domain, attempt_time),
      INDEX idx_attempt_time (attempt_time)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ```

#### Step 2.2.2: Track Registration Attempts ✅ **HIGH CONFIDENCE**
- **What:** Log all registration attempts (success and failure)
- **Where:** `config/opensips.cfg.template` - `onreply_route[handle_reply_reg]`
- **Confidence:** ✅ High - Similar to failed_registrations logging
- **Implementation:** Add INSERT to `registration_attempts` table in onreply_route

#### Step 2.2.3: Implement Brute Force Detection ✅ **HIGH CONFIDENCE** (Recommended: Fail2ban)

**Recommended Approach:** Use Fail2ban for brute force detection (monitors OpenSIPS logs and adds iptables rules)

#### Option A: Fail2ban Integration ✅ **HIGH CONFIDENCE** (Recommended)
- **What:** Configure Fail2ban to monitor OpenSIPS logs for failed registration patterns
- **Confidence:** ✅ High - Standard approach, well-documented
- **How it works:**
  - Fail2ban monitors OpenSIPS log files
  - Detects patterns indicating brute force (multiple failed registrations from same IP)
  - Automatically adds iptables rules to block IPs
  - Can be configured with ban duration and thresholds
- **Pros:** 
  - System-level blocking (more effective than application-level)
  - Automatic IPTables integration
  - Well-tested and maintained
  - Reduces load on OpenSIPS (blocking happens at firewall level)
- **Cons:** Requires Fail2ban installation and configuration
- **Implementation:**
  - Configure Fail2ban filter for OpenSIPS registration failures
  - Set up jail rules for registration brute force detection
  - Configure iptables action
- **Research Needed:**
  - Fail2ban filter patterns for OpenSIPS logs
  - Optimal ban duration and thresholds
  - Integration with existing firewall rules

#### Option B: Custom Database-Based Detection ⚠️ **MEDIUM CONFIDENCE** (Alternative)
- **What:** Check for excessive failed attempts and block IPs using database queries
- **Where:** `config/opensips.cfg.template` - `route{}` (before domain check)
- **Confidence:** ⚠️ Medium - Need to design efficient query pattern
- **Implementation:**
  ```opensips
  route[CHECK_BRUTE_FORCE] {
      # Check failed attempts in last 5 minutes
      $var(query) = "SELECT COUNT(*) FROM registration_attempts 
          WHERE source_ip='" + $si + "' 
          AND success=FALSE 
          AND attempt_time > DATE_SUB(NOW(), INTERVAL 5 MINUTE)";
      if (sql_query($var(query), "$avp(failed_count)")) {
          if ($(avp(failed_count)[0]) >= 5) {
              # Block IP
              xlog("L_WARN", "Brute force detected from $si - blocking\n");
              sl_send_reply(403, "Too Many Failed Attempts");
              exit;
          }
      }
  }
  ```
- **Pros:** Full control, integrated with OpenSIPS
- **Cons:** Database query overhead, less effective than firewall-level blocking
- **Research Needed:**
  - Efficient query patterns for time-windowed counting
  - Performance impact of database queries on every REGISTER
  - Caching strategies to reduce database load

**Recommendation:** Use Fail2ban (Option A) for brute force detection - it's the recommended method for password guessing attacks and provides system-level protection.

### 2.3 Flood Detection ✅ **HIGH CONFIDENCE** (with event_route)

**Objective:** Detect and mitigate SIP flood attacks

**Recommended Approach:** Use `pike` module (primary method) with `event_route` for logging and monitoring

#### Option A: Use Pike Module ✅ **HIGH CONFIDENCE** (Recommended)
- **What:** Load and configure `pike` module with `event_route` integration
- **Confidence:** ✅ High - Well-documented, recommended approach
- **Key Features:**
  - Automatic high-speed rate limiting of suspicious traffic
  - Tracks source IP traffic and blocks IPs exceeding thresholds
  - Works for both IPv4 and IPv6
  - Emits `E_PIKE_BLOCKED` event automatically when IP is blocked
  - Prevents DoS/scanning attacks
- **Pros:** Built-in, automatic, efficient, event-driven monitoring
- **Cons:** Need to configure thresholds appropriately
- **Research Needed:**
  - Optimal threshold configuration for our environment
  - Performance impact testing
  - Whitelist configuration for trusted sources

#### Option B: Custom Flood Detection ⚠️ **MEDIUM CONFIDENCE** (Not Recommended)
- **What:** Implement custom flood detection using database
- **Confidence:** ⚠️ Medium - More complex than rate limiting
- **Implementation:** Track requests per IP over time windows, detect spikes
- **Pros:** Full control
- **Cons:** Complex, performance concerns, may miss fast floods, reinventing the wheel

**Recommendation:** Use `pike` module (Option A) - it's the recommended method for IP banning and flood detection.

#### Step 2.3.1: Configure Pike Module ✅ **HIGH CONFIDENCE**
- **What:** Load and configure `pike` module for flood detection
- **Where:** `config/opensips.cfg.template` - Module loading and modparam sections
- **Confidence:** ✅ High - Well-documented approach
- **Pike Operational Modes:**
  - **Automatic Mode (Recommended):** Pike installs internal hooks to monitor all incoming requests/replies and automatically drops packets when floods are detected
  - **Manual Mode:** Call `pike_check_req()` in routing script to check specific requests and decide action based on return code
- **Implementation (Automatic Mode):**
  ```opensips
  # Load pike module
  loadmodule "pike.so"
  
  # Configure pike thresholds
  modparam("pike", "sampling_time_unit", 2)  # 2 seconds (smaller = better detection of peaks, but slower)
  modparam("pike", "reqs_density_per_unit", 16)  # 16 requests per 2 seconds threshold
  modparam("pike", "remove_latency", 4)  # Remove block after 4 sampling units (8 seconds)
  modparam("pike", "pike_log_level", 1)  # Logging detail level (0=none, 1=blocked IPs, 2=all)
  
  # Optional: Whitelist trusted sources via check_route
  # modparam("pike", "check_route", "CHECK_WHITELIST")  # Route to run before analyzing each packet
  ```
- **Alternative Implementation (Manual Mode):**
  ```opensips
  # In request route, check for floods manually
  if (!pike_check_req()) {
      # IP is flooding - take action
      xlog("L_WARN", "PIKE: Flood detected from $si\n");
      sl_send_reply(503, "Service Unavailable");
      exit;
  }
  ```
- **Research Needed:**
  - Optimal threshold values for our environment (may need tuning)
  - Performance impact testing
  - Whether to use automatic or manual mode (automatic recommended for simplicity)
  - Whether to use `check_route` for whitelisting trusted sources

#### Step 2.3.2: Implement Event Route for Pike Blocking ✅ **HIGH CONFIDENCE**
- **What:** Add `event_route[E_PIKE_BLOCKED]` to log and handle blocked IPs
- **Where:** `config/opensips.cfg.template` - Event route section
- **Confidence:** ✅ High - Standard event route pattern, documented community practice
- **Implementation:**
  ```opensips
  event_route[E_PIKE_BLOCKED] {
      # Log blocked IP
      xlog("L_WARN", "PIKE: IP $si blocked due to flood detection\n");
      
      # Log to security_events table (if Phase 3 implemented)
      # $var(query) = "INSERT INTO security_events (event_type, source_ip, severity, details, event_time) 
      #     VALUES ('flood_detected', '" + $si + "', 'high', 'Pike module blocked IP', NOW())";
      # sql_query($var(query));
      
      # Optional: Trigger external script for firewall integration
      # Using exec module to pipe blocked IPs to iptables/ipset
      # Note: Consider using ipset instead of raw iptables to avoid duplicate rules
      # exec("/usr/local/bin/block-ip.sh", "$si");
  }
  ```
- **Benefits:**
  - Automatic logging when pike blocks an IP (works with automatic mode)
  - Can trigger external scripts for firewall integration (iptables/ipset)
  - Can integrate with security_events table for monitoring
- **Firewall Integration Options:**
  - **iptables:** Direct firewall rules (may create duplicates)
  - **ipset (Recommended):** More efficient, avoids duplicate rules, better for large IP lists
  - **Fail2ban:** Can also monitor pike logs and add firewall rules
- **Note:** This is a documented community pattern - users successfully combine pike detection with exec module to pipe blocked IPs to iptables with timeout rules

---

## Phase 3: Monitoring & Alerting (Weeks 6-7)

### 3.1 Security Event Logging ✅ **HIGH CONFIDENCE**

**Objective:** Comprehensive logging of all security events

#### Step 3.1.1: Create Security Events Table ✅ **HIGH CONFIDENCE**
- **What:** Create `security_events` table
- **Where:** `scripts/init-database.sh`
- **Confidence:** ✅ High - Standard SQL table creation
- **Schema:** (as defined in project plan)

#### Step 3.1.2: Add Security Event Logging ✅ **HIGH CONFIDENCE**
- **What:** Log security events throughout the configuration
- **Where:** Multiple locations in `config/opensips.cfg.template`
- **Confidence:** ✅ High - Standard SQL INSERT operations
- **Implementation Points:**
  - Registration failures → `registration_failure` event
  - Brute force detection → `brute_force_detected` event
  - Flood detection → `flood_detected` event
  - Rate limit violations → `rate_limit_exceeded` event
  - IP blocking → `ip_blocked` event
  - Scanner detection → `scanner_detected` event

### 3.2 Alerting System ⚠️ **MEDIUM CONFIDENCE**

**Objective:** Send alerts for critical security events

#### Step 3.2.1: Create Alert Configuration Table ✅ **HIGH CONFIDENCE**
- **What:** Create `alert_config` table
- **Where:** `scripts/init-database.sh`
- **Confidence:** ✅ High - Standard SQL table creation

#### Step 3.2.2: Create Alert Sending Script ⚠️ **MEDIUM CONFIDENCE**
- **What:** Create `scripts/send-alert.sh` for email/SMS/webhook alerts
- **Where:** New file `scripts/send-alert.sh`
- **Confidence:** ⚠️ Medium - Need to research email/SMS sending options
- **Research Needed:**
  - Email sending (sendmail, SMTP, mail command)
  - SMS sending (Twilio, AWS SNS, etc.)
  - Webhook implementation
  - Alert aggregation to prevent spam
  - Configuration management

#### Step 3.2.3: Integrate Alerting ⚠️ **MEDIUM CONFIDENCE**
- **What:** Call alert script when critical events occur
- **Where:** `config/opensips.cfg.template` - Various security check points
- **Confidence:** ⚠️ Medium - Depends on alert script implementation
- **Implementation:** Use `exec()` or external script calls (need to verify OpenSIPS capabilities)

### 3.3 Statistics & Reporting ✅ **HIGH CONFIDENCE**

**Objective:** Provide security statistics and reports

#### Step 3.3.1: Create Database Views ✅ **HIGH CONFIDENCE**
- **What:** Create SQL views for security statistics
- **Where:** `scripts/init-database.sh`
- **Confidence:** ✅ High - Standard SQL view creation
- **Views:**
  - `security_stats_hourly` - Hourly event counts
  - `top_attacking_ips` - Top attacking IPs
  - `registration_failure_stats` - Registration failure trends

#### Step 3.3.2: Create Reporting Scripts ✅ **HIGH CONFIDENCE**
- **What:** Create scripts to generate security reports
- **Where:** `scripts/security-report.sh`, `scripts/view-security-stats.sh`
- **Confidence:** ✅ High - Standard SQL queries and shell scripting

---

## Phase 4: Advanced Threat Detection (Weeks 8-9)

### 4.1 Username Enumeration Detection ⚠️ **MEDIUM CONFIDENCE**

**Objective:** Detect attempts to enumerate valid usernames

#### Step 4.1.1: Implement Enumeration Detection Logic ⚠️ **MEDIUM CONFIDENCE**
- **What:** Analyze registration attempts to detect enumeration patterns
- **Where:** `scripts/detect-username-enumeration.sh` (analysis script)
- **Confidence:** ⚠️ Medium - Need to design detection algorithm
- **Research Needed:**
  - Pattern detection algorithms
  - Threshold determination (how many unique AoRs = enumeration?)
  - Real-time vs batch analysis
  - False positive handling

### 4.2 Geographic Anomaly Detection 🔍 **NEEDS RESEARCH**

**Objective:** Detect suspicious geographic patterns

**Status:** Optional feature, requires external services

**Industry Context:** Many VoIP providers use Geo-IP blocking to restrict traffic from countries/regions where they don't operate, preventing international fraud. This is a common practice but requires external GeoIP services.

#### Step 4.2.1: Research GeoIP Integration 🔍 **NEEDS RESEARCH**
- **What:** Research GeoIP database integration
- **Confidence:** 🔍 Needs Research - External dependency
- **Research Needed:**
  - GeoIP database options (MaxMind, etc.)
  - OpenSIPS GeoIP module availability
  - Integration approach
  - Cost and licensing
  - Performance impact
  - Use case: Block traffic from specific countries/regions

### 4.3 Behavioral Analysis 🔍 **NEEDS RESEARCH**

**Objective:** Detect anomalous behavior patterns

**Status:** Advanced feature, requires baseline establishment

#### Step 4.3.1: Design Behavioral Analysis System 🔍 **NEEDS RESEARCH**
- **What:** Design system to detect behavioral anomalies
- **Confidence:** 🔍 Needs Research - Complex machine learning/statistical analysis
- **Research Needed:**
  - Baseline establishment methodology
  - Anomaly detection algorithms
  - Real-time vs batch processing
  - False positive rates
  - Performance impact

---

## Phase 5: IP Management & Blocking (Weeks 10-11)

### 5.0 Scanner Protection Enhancement 🔍 **NEEDS RESEARCH**

**Objective:** Enhance scanner detection beyond basic User-Agent matching

**Current Implementation:** Basic User-Agent pattern matching (sipvicious, friendly-scanner, sipcli, nmap)

**Enhancement Options:**

#### Option A: dst_blacklist Module 🔍 **NEEDS RESEARCH**
- **What:** Use `dst_blacklist` module to prevent OpenSIPS from sending requests to known bad destinations
- **Purpose:** Can be used to manage temporary bans and prevent requests to known scanner IPs
- **Confidence:** 🔍 Needs Research - Need to verify module availability and API
- **Research Needed:**
  - Module availability in OpenSIPS 3.6.3
  - API and configuration
  - Integration with IP blocking system
  - Performance impact

#### Option B: APIBan Integration 🔍 **NEEDS RESEARCH**
- **What:** Integrate APIBan for protecting against known scanners using shared threat intelligence
- **Purpose:** Leverage community threat intelligence for scanner detection
- **Confidence:** 🔍 Needs Research - External service integration
- **Research Needed:**
  - APIBan service availability and API
  - Integration approach (REST API, database sync, etc.)
  - Cost and rate limits
  - Performance impact (API calls vs cached data)
  - Privacy considerations

**Recommendation:** Research both options - `dst_blacklist` for internal blocking, APIBan for threat intelligence (if available and cost-effective).

### 5.1 IP Blocking System 🔍 **NEEDS RESEARCH** (Evaluate permissions module first)

**Objective:** Manage blocked IPs with expiration and whitelisting

**⚠️ STANDARD APPROACH FIRST:** Before implementing custom IP blocking, evaluate if `permissions` module can meet requirements.

**Evaluation Order:**
1. **First:** Test `permissions` module with database-backed ACLs (standard OpenSIPS approach)
2. **Check:** Can `permissions` module handle:
   - IP whitelisting/blacklisting
   - Expiration/automatic removal
   - Database persistence
   - Multi-tenant support
3. **Only if needed:** Use custom database approach if `permissions` module doesn't meet critical requirements
4. **Document:** If using custom approach, document why `permissions` module didn't meet requirements

**Note:** Pike module (Phase 2.3) already provides automatic IP blocking for floods. This section is for manual/administrative IP blocking.

#### Step 5.1.1: Create Blocked IPs Table ⚠️ **ONLY IF PERMISSIONS MODULE DOESN'T MEET REQUIREMENTS**
- **What:** Create `blocked_ips` and `whitelisted_ips` tables (only if permissions module insufficient)
- **Where:** `scripts/init-database.sh`
- **Confidence:** ✅ High - Standard SQL table creation
- **When to Use:** Only if `permissions` module doesn't support required features
- **Schema:** (as defined in project plan)

#### Step 5.1.2: Add IP Blocking Checks ✅ **HIGH CONFIDENCE**
- **What:** Check blocked/whitelisted IPs in request route
- **Where:** `config/opensips.cfg.template` - `route{}` (very early, before other checks)
- **Confidence:** ✅ High - Standard database query and conditional logic
- **Implementation:**
  ```opensips
  route {
      # Check IP blocking first (before other processing)
      route(CHECK_IP_BLOCKING);
      if ($var(is_blocked) == 1) {
          sl_send_reply(403, "IP Blocked");
          exit;
      }
      # ... rest of routing logic
  }
  
  route[CHECK_IP_BLOCKING] {
      $var(is_blocked) = 0;
      # Check whitelist first (bypass blocking)
      $var(whitelist_query) = "SELECT COUNT(*) FROM whitelisted_ips WHERE ip_address='" + $si + "'";
      if (sql_query($var(whitelist_query), "$avp(whitelist_check)")) {
          if ($(avp(whitelist_check)[0]) > 0) {
              # Whitelisted - allow
              return;
          }
      }
      # Check blocked list
      $var(block_query) = "SELECT COUNT(*) FROM blocked_ips 
          WHERE ip_address='" + $si + "' 
          AND (expires_at IS NULL OR expires_at > NOW())
          AND unblocked_at IS NULL";
      if (sql_query($var(block_query), "$avp(block_check)")) {
          if ($(avp(block_check)[0]) > 0) {
              $var(is_blocked) = 1;
          }
      }
      return;
  }
  ```

#### Step 5.1.3: Create Management Scripts ✅ **HIGH CONFIDENCE**
- **What:** Create scripts for IP blocking management
- **Where:** `scripts/block-ip.sh`, `scripts/unblock-ip.sh`, `scripts/list-blocked-ips.sh`, `scripts/whitelist-ip.sh`
- **Confidence:** ✅ High - Standard shell scripts with MySQL commands

### 5.2 Automatic Block Expiration ✅ **HIGH CONFIDENCE**

**Objective:** Automatically unblock IPs after expiration period

#### Step 5.2.1: Create Expiration Script ✅ **HIGH CONFIDENCE**
- **What:** Create script to expire old blocks
- **Where:** `scripts/expire-blocked-ips.sh`
- **Confidence:** ✅ High - Standard SQL UPDATE operations
- **Implementation:** SQL UPDATE to set `unblocked_at` for expired blocks

#### Step 5.2.2: Create Systemd Timer ✅ **HIGH CONFIDENCE**
- **What:** Create systemd timer to run expiration script periodically
- **Where:** `scripts/expire-blocked-ips.timer`, `scripts/expire-blocked-ips.service`
- **Confidence:** ✅ High - Similar to existing cleanup timer

---

## Summary: Confidence Levels by Phase

### ✅ High Confidence (Can implement immediately)
- **Phase 1.1:** Failed registration tracking (database + logging)
- **Phase 1.2:** Registration status tracking
- **Phase 2.2:** Registration-specific rate limiting (custom database approach)
- **Phase 2.2.3:** Brute force detection ✅ **UPDATED:** Fail2ban recommended approach
- **Phase 2.3:** Flood detection ✅ **UPDATED:** Pike module with event_route (recommended method)
- **Phase 3.1:** Security event logging
- **Phase 3.3:** Statistics & reporting
- **Phase 5.1:** IP blocking system
- **Phase 5.2:** Automatic block expiration

### ⚠️ Medium Confidence (Need some research/testing)
- **Phase 1.3:** Response-based cleanup (need to verify if needed)
- **Phase 2.1:** IP-based rate limiting (if using custom approach)
- **Phase 3.2:** Alerting system (email/SMS integration)
- **Phase 4.1:** Username enumeration detection (algorithm design)

### 🔍 Needs Research (Require module testing/documentation)
- **Phase 0:** Module testing (pike, ratelimit, permissions)
- **Phase 2.1:** Rate limiting module integration (if using ratelimit module)
- **Phase 2.3:** Flood detection (pike module configuration) ✅ **UPDATED:** Now includes event_route implementation
- **Phase 5.0:** Scanner protection enhancement (dst_blacklist, APIBan)
- **Phase 4.2:** Geographic anomaly detection (external dependency)
- **Phase 4.3:** Behavioral analysis (complex algorithms)

---

## Recommended Implementation Order

### Week 1: Research Phase
1. ✅ Complete module research (already done)
2. ✅ Test pike module (POC) - **COMPLETE**
3. ⏸️ Test ratelimit module (POC) - **DEFERRED** (moved down priority list)
4. 🔍 Test permissions module (POC)
5. ✅ Document architecture decisions

### Weeks 2-3: Foundation (High Confidence)
1. ✅ Create database tables (failed_registrations, registration_status)
2. ✅ Add failed registration logging
3. ✅ Add registration status tracking
4. ✅ Test and verify logging works

### Weeks 4-5: Rate Limiting (Mixed Confidence)
1. ⏸️ Test ratelimit module OR implement custom rate limiting - **DEFERRED** (moved down priority list)
2. ✅ Implement registration-specific rate limiting
3. ✅ Configure pike module for flood detection - **COMPLETE** (merged to main)
4. ✅ Create brute force detection

### Weeks 6-7: Monitoring (High Confidence)
1. ✅ Create security_events table
2. ✅ Add security event logging throughout
3. ⚠️ Implement alerting system
4. ✅ Create statistics views and reporting scripts

### Weeks 8-9: Advanced Detection (Lower Confidence)
1. ⚠️ Implement username enumeration detection
2. 🔍 Research geographic detection (optional)
3. 🔍 Research behavioral analysis (optional)

### Weeks 10-11: IP Management (High Confidence)
1. ✅ Create IP blocking tables
2. ✅ Implement IP blocking checks
3. ✅ Create management scripts
4. ✅ Implement automatic expiration

---

## Key Research Areas

### Critical Research Needed:
1. ✅ **Pike Module:** Flood detection configuration and performance - **COMPLETE**
2. ⏸️ **Ratelimit Module:** Rate limiting algorithms and configuration - **DEFERRED** (moved down priority list)
3. **Permissions Module:** Database schema and performance
4. **AVP Persistence:** Verify AVPs persist to onreply_route
5. **Alert Integration:** How to call external scripts from OpenSIPS

### Important Research:
1. **Query Performance:** Optimize database queries for rate limiting
2. **Caching Strategies:** Reduce database load for security checks
3. **Enumeration Detection:** Algorithm design for pattern detection

### Optional Research:
1. **GeoIP Integration:** External service integration
2. **Behavioral Analysis:** Machine learning/statistical approaches

---

## Risk Assessment

### Low Risk (High Confidence)
- Database table creation
- SQL INSERT/UPDATE operations
- Shell script creation
- Basic security event logging

### Medium Risk (Medium Confidence)
- Rate limiting implementation (depends on module choice)
- Alert system integration (external dependencies)
- Query performance optimization

### High Risk (Needs Research)
- Module integration (pike, ratelimit, permissions)
- Flood detection configuration
- Advanced threat detection algorithms

---

## Next Steps

1. **Start with Phase 0:** Complete module testing and POC
2. **Begin Phase 1:** Implement high-confidence foundation features
3. **Iterate:** Test each phase before moving to next
4. **Document:** Update documentation as features are implemented

---

**Last Updated:** January 2026  
**Status:** Planning complete, ready for Phase 0 research

## Reference Links

- **OpenSIPS 3.6 Module Documentation Index:** https://opensips.org/html/docs/modules/3.6.x/ ⭐ **PRIMARY REFERENCE**
  - Use this to find documentation for any OpenSIPS 3.6 modules including:
    - `pike` - https://opensips.org/html/docs/modules/3.6.x/pike.html
    - `ratelimit` - https://opensips.org/html/docs/modules/3.6.x/ratelimit.html
    - `permissions` - https://opensips.org/html/docs/modules/3.6.x/permissions.html
    - `dst_blacklist` - https://opensips.org/html/docs/modules/3.6.x/dst_blacklist.html (if available)
    - And all other modules
