# Phase 0: Research & Evaluation - Execution Plan

**Date:** January 2026  
**Status:** 📋 Ready to Execute  
**Goal:** Test and evaluate OpenSIPS security modules before implementation

---

## Overview

Phase 0 involves testing three key OpenSIPS security modules in a controlled environment to determine if they meet our requirements before committing to implementation. This follows the "standard approach first" principle.

---

## Prerequisites

### Test Environment
- ✅ OpenSIPS 3.6.3 installed and running
- ✅ MySQL database accessible
- ✅ Test SIP client available (or use existing phones)
- ✅ Access to OpenSIPS logs
- ✅ Ability to restart OpenSIPS service

### Documentation Access
- OpenSIPS 3.6 Module Documentation: https://opensips.org/html/docs/modules/3.6.x/
- Pike Module: https://opensips.org/html/docs/modules/3.6.x/pike.html
- Ratelimit Module: https://opensips.org/html/docs/modules/3.6.x/ratelimit.html
- Permissions Module: https://opensips.org/html/docs/modules/3.6.x/permissions.html

---

## Task 0.1.1: Test Pike Module (Flood Detection)

### Step 1: Review Pike Module Documentation
**Time:** 15 minutes

1. Read the pike module documentation
2. Note key parameters:
   - `sampling_time_unit` - Time window for sampling
   - `reqs_density_per_unit` - Request threshold per time unit
   - `remove_latency` - How long to keep IP blocked
   - `pike_log_level` - Logging detail
   - `check_route` - Optional route for whitelisting
3. Note available functions:
   - `pike_check_req()` - Manual mode check
   - Automatic mode (no function call needed)
4. Note events:
   - `E_PIKE_BLOCKED` - Event emitted when IP is blocked

**Deliverable:** Notes on pike module capabilities

### Step 2: Create Test Configuration
**Time:** 30 minutes

1. Create a test branch: `git checkout -b phase0-pike-test`
2. Add pike module to `config/opensips.cfg.template`:
   ```opensips
   loadmodule "pike.so"
   
   modparam("pike", "sampling_time_unit", 2)  # 2 seconds
   modparam("pike", "reqs_density_per_unit", 16)  # 16 requests per 2 seconds
   modparam("pike", "remove_latency", 4)  # Block for 8 seconds (4 * 2)
   modparam("pike", "pike_log_level", 1)  # Log blocked IPs
   ```

3. Add event route for logging:
   ```opensips
   event_route[E_PIKE_BLOCKED] {
       xlog("L_WARN", "PIKE: IP $si blocked due to flood detection\n");
   }
   ```

4. Test configuration syntax:
   ```bash
   opensips -C -f /etc/opensips/opensips.cfg
   ```

**Deliverable:** Test configuration file

### Step 3: Test Pike Module (Automatic Mode)
**Time:** 30 minutes

1. **Deploy test configuration:**
   ```bash
   sudo systemctl restart opensips
   sudo systemctl status opensips
   ```

2. **Test normal traffic:**
   - Send normal REGISTER requests (should work fine)
   - Verify no false positives
   - Check logs: `journalctl -u opensips -f`

3. **Test flood detection:**
   - Use SIPp or similar tool to send rapid requests:
     ```bash
     # Send 20 requests in 1 second (should trigger pike)
     sipp -sn uac -s 40004 -m 20 -r 20 -d 1000 sbc.example.com:5060
     ```
   - Or use existing phone to send rapid OPTIONS requests
   - Verify IP gets blocked
   - Check logs for `E_PIKE_BLOCKED` event
   - Verify blocked IP cannot send requests (should get 503 or dropped)

4. **Test unblocking:**
   - Wait for `remove_latency` period (8 seconds in example)
   - Verify IP can send requests again

**Deliverable:** Test results documenting:
- Does automatic mode work?
- What response does blocked IP get?
- Performance impact (check CPU/memory)
- Any false positives?

### Step 4: Test Pike Module (Manual Mode - Optional)
**Time:** 20 minutes

1. **Modify configuration for manual mode:**
   - Remove automatic hooks (don't load pike module automatically)
   - Add manual check in request route:
     ```opensips
     if (!pike_check_req()) {
         xlog("L_WARN", "PIKE: Flood detected from $si\n");
         sl_send_reply(503, "Service Unavailable");
         exit;
     }
     ```

2. **Test manual mode:**
   - Send flood of requests
   - Verify `pike_check_req()` returns FALSE for flooding IPs
   - Verify custom handling works

**Deliverable:** Comparison of automatic vs manual mode

### Step 5: Document Pike Findings
**Time:** 15 minutes

Create `docs/PHASE-0-PIKE-RESULTS.md` with:
- Module loaded successfully: Yes/No
- Automatic mode works: Yes/No
- Event route works: Yes/No
- Performance impact: Minimal/Moderate/Significant
- Configuration recommendations
- Any issues encountered
- Recommendation: Use/Don't use/Needs more testing

---

## Task 0.1.2: Test Ratelimit Module (Rate Limiting)

### Step 1: Review Ratelimit Module Documentation
**Time:** 15 minutes

1. Read the ratelimit module documentation
2. Note key parameters:
   - Algorithm options (TAILDROP, RED, etc.)
   - Database URL (for persistence)
   - Table name
   - Rate limit values
3. Note available functions:
   - `rl_check()` - Check rate limit
   - `rl_check_pipe()` - Check rate limit for specific pipe
4. Note database schema requirements

**Deliverable:** Notes on ratelimit module capabilities

### Step 2: Create Test Configuration
**Time:** 30 minutes

1. Create a test branch: `git checkout -b phase0-ratelimit-test`
2. Review database schema requirements
3. Add ratelimit module to `config/opensips.cfg.template`:
   ```opensips
   loadmodule "ratelimit.so"
   
   modparam("ratelimit", "db_url", "mysql://opensips:password@localhost/opensips")
   modparam("ratelimit", "db_table", "ratelimit")
   modparam("ratelimit", "pipe", "REGISTER:10:60")  # 10 requests per 60 seconds
   ```

4. Create database table (if needed):
   ```sql
   CREATE TABLE ratelimit (
       id INT AUTO_INCREMENT PRIMARY KEY,
       pipe VARCHAR(64) NOT NULL,
       key VARCHAR(64) NOT NULL,
       limit_value INT NOT NULL,
       window_start DATETIME NOT NULL,
       UNIQUE KEY (pipe, key)
   ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
   ```

5. Add rate limit check in request route:
   ```opensips
   if (is_method("REGISTER")) {
       if (!rl_check("REGISTER")) {
           xlog("L_WARN", "RATELIMIT: REGISTER rate limit exceeded from $si\n");
           sl_send_reply(429, "Too Many Requests");
           exit;
       }
   }
   ```

6. Test configuration syntax:
   ```bash
   opensips -C -f /etc/opensips/opensips.cfg
   ```

**Deliverable:** Test configuration file

### Step 3: Test Ratelimit Module
**Time:** 30 minutes

1. **Deploy test configuration:**
   ```bash
   sudo systemctl restart opensips
   sudo systemctl status opensips
   ```

2. **Test normal traffic:**
   - Send REGISTER requests within limit (e.g., 5 requests)
   - Verify all succeed
   - Check database for rate limit entries

3. **Test rate limit enforcement:**
   - Send requests exceeding limit (e.g., 15 requests in 60 seconds)
   - Verify 11th request gets 429 response
   - Check logs for rate limit messages
   - Verify database tracking works

4. **Test window expiration:**
   - Wait for window to expire (60 seconds)
   - Send new requests
   - Verify limit resets

5. **Test per-IP vs per-user:**
   - Try different key options (IP-based, user-based)
   - Verify correct behavior

**Deliverable:** Test results documenting:
- Does rate limiting work?
- Database persistence works: Yes/No
- Algorithm behavior (TAILDROP, RED, etc.)
- Performance impact
- Any issues encountered

### Step 4: Document Ratelimit Findings
**Time:** 15 minutes

Create `docs/PHASE-0-RATELIMIT-RESULTS.md` with:
- Module loaded successfully: Yes/No
- Rate limiting works: Yes/No
- Database persistence works: Yes/No
- Algorithm tested: TAILDROP/RED/etc.
- Performance impact: Minimal/Moderate/Significant
- Configuration recommendations
- Any issues encountered
- Recommendation: Use/Don't use/Needs more testing

---

## Task 0.1.3: Test Permissions Module (IP Access Control)

### Step 1: Review Permissions Module Documentation
**Time:** 15 minutes

1. Read the permissions module documentation
2. Note key parameters:
   - Database URL
   - Table name
   - Default allow/deny behavior
3. Note available functions:
   - `allow_address()` - Check if IP is allowed
   - `allow_source_address()` - Check source IP
   - `allow_trusted()` - Check trusted IPs
4. Note database schema requirements

**Deliverable:** Notes on permissions module capabilities

### Step 2: Create Test Configuration
**Time:** 30 minutes

1. Create a test branch: `git checkout -b phase0-permissions-test`
2. Review database schema requirements
3. Add permissions module to `config/opensips.cfg.template`:
   ```opensips
   loadmodule "permissions.so"
   
   modparam("permissions", "db_url", "mysql://opensips:password@localhost/opensips")
   modparam("permissions", "db_table", "permissions")
   modparam("permissions", "default_allow_file", "/etc/opensips/permissions.allow")
   ```

4. Create database table:
   ```sql
   CREATE TABLE permissions (
       id INT AUTO_INCREMENT PRIMARY KEY,
       grp INT NOT NULL DEFAULT 1,
       ip_addr VARCHAR(50) NOT NULL,
       mask INT NOT NULL DEFAULT 32,
       port INT NOT NULL DEFAULT 0,
       proto VARCHAR(4) DEFAULT NULL,
       pattern VARCHAR(64) DEFAULT NULL,
       context_info VARCHAR(32) DEFAULT NULL,
       INDEX idx_grp (grp),
       INDEX idx_ip_addr (ip_addr)
   ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
   ```

5. Add permission check in request route:
   ```opensips
   route {
       # Check IP permissions first
       if (!allow_source_address("1")) {  # Check group 1
           xlog("L_WARN", "PERMISSIONS: IP $si not allowed\n");
           sl_send_reply(403, "Forbidden");
           exit;
       }
       # ... rest of routing
   }
   ```

6. Test configuration syntax:
   ```bash
   opensips -C -f /etc/opensips/opensips.cfg
   ```

**Deliverable:** Test configuration file

### Step 3: Test Permissions Module
**Time:** 30 minutes

1. **Deploy test configuration:**
   ```bash
   sudo systemctl restart opensips
   sudo systemctl status opensips
   ```

2. **Test whitelist:**
   - Add test IP to permissions table:
     ```sql
     INSERT INTO permissions (grp, ip_addr, mask, port) 
     VALUES (1, '192.168.1.100', 32, 0);
     ```
   - Send request from whitelisted IP
   - Verify request succeeds

3. **Test blacklist:**
   - Remove IP from permissions table (or use different group)
   - Send request from non-whitelisted IP
   - Verify request gets 403 response

4. **Test database performance:**
   - Measure lookup time for permission checks
   - Check database query performance
   - Test with multiple entries

5. **Test multi-tenant support:**
   - Try different groups
   - Verify group-based access control works

**Deliverable:** Test results documenting:
- Does IP blocking work?
- Database lookups performant: Yes/No
- Multi-tenant support: Yes/No
- Whitelist/blacklist management: Easy/Complex
- Any issues encountered

### Step 4: Document Permissions Findings
**Time:** 15 minutes

Create `docs/PHASE-0-PERMISSIONS-RESULTS.md` with:
- Module loaded successfully: Yes/No
- IP blocking works: Yes/No
- Database performance: Good/Acceptable/Slow
- Multi-tenant support: Yes/No
- Configuration recommendations
- Any issues encountered
- Recommendation: Use/Don't use/Needs more testing

---

## Task 0.1.4: Create Architecture Decision Document

### Step 1: Compile All Findings
**Time:** 30 minutes

1. Review all test results:
   - Pike module results
   - Ratelimit module results
   - Permissions module results

2. Compare modules against requirements:
   - Does pike meet flood detection needs?
   - Does ratelimit meet rate limiting needs?
   - Does permissions meet IP blocking needs?

3. Identify gaps:
   - What features are missing?
   - What custom work is needed?
   - What alternatives exist?

### Step 2: Create Decision Document
**Time:** 45 minutes

Create `docs/SECURITY-ARCHITECTURE-DECISIONS.md` with:

1. **Executive Summary**
   - Overall recommendation
   - Modules to use vs custom implementation

2. **Module Decisions**
   - **Pike Module:**
     - Decision: Use/Don't use/Custom
     - Rationale
     - Configuration approach
   - **Ratelimit Module:**
     - Decision: Use/Don't use/Custom
     - Rationale
     - Configuration approach
   - **Permissions Module:**
     - Decision: Use/Don't use/Custom
     - Rationale
     - Configuration approach

3. **Implementation Plan**
   - Phase 1 approach (based on module decisions)
   - Phase 2 approach (based on module decisions)
   - Phase 5 approach (based on module decisions)

4. **Custom Implementation Needs**
   - What custom code is needed
   - Why custom code is needed
   - How it complements modules

**Deliverable:** Architecture decision document

---

## Phase 0 Completion Checklist

- [ ] Pike module tested and documented
- [ ] Ratelimit module tested and documented
- [ ] Permissions module tested and documented
- [ ] Architecture decision document created
- [ ] All findings reviewed and decisions made
- [ ] Ready to proceed to Phase 1

---

## Estimated Time

- Task 0.1.1 (Pike): ~2 hours
- Task 0.1.2 (Ratelimit): ~2 hours
- Task 0.1.3 (Permissions): ~2 hours
- Task 0.1.4 (Architecture): ~1.5 hours
- **Total:** ~7.5 hours (can be done over multiple sessions)

---

## Testing Tools Needed

1. **SIP Testing:**
   - Existing phones (for real-world testing)
   - SIPp (for flood/rate limit testing)
   - sipp (alternative SIP testing tool)

2. **Monitoring:**
   - OpenSIPS logs: `journalctl -u opensips -f`
   - MySQL queries: `mysql -u opensips -p opensips`
   - System monitoring: `top`, `htop`, `iostat`

3. **Configuration:**
   - Git branches for each test
   - Backup of working configuration
   - Ability to rollback quickly

---

## Risk Mitigation

1. **Test in isolated environment** - Don't test on production
2. **Use git branches** - Easy rollback if issues
3. **Backup configuration** - Save working config before changes
4. **Monitor closely** - Watch logs and system resources
5. **Test incrementally** - One module at a time

---

## Next Steps After Phase 0

Once Phase 0 is complete:
1. Review architecture decision document
2. Update Phase 1 implementation plan based on decisions
3. Begin Phase 1 implementation with confidence

---

**Last Updated:** January 2026  
**Status:** Ready to execute
