# Phase 0: Research & Evaluation - Execution Plan

**Date:** January 2026  
**Status:** 📋 Ready to Execute  
**Goal:** Test and evaluate OpenSIPS security modules before implementation

---

## Overview

Phase 0 involves testing key OpenSIPS security modules in a controlled environment to determine if they meet our requirements before committing to implementation. This follows the "standard approach first" principle.

**Modules to Test:**
- Pike module (flood detection) ✅ **ACTIVE**
- Ratelimit module (rate limiting) ⏸️ **DEFERRED** - Will revisit later
- Permissions module ❌ **SKIPPED** - Using Fail2Ban instead (see `docs/PHASE-0-PERMISSIONS-DECISION.md`)

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
- Permissions Module: **SKIPPED** - Using Fail2Ban for IP blocking (see `docs/PHASE-0-PERMISSIONS-DECISION.md`)

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

## Task 0.1.2: Test Ratelimit Module (Rate Limiting) - **DEFERRED**

**Decision:** Defer ratelimit module testing for now

**Rationale:**
- Rate limiting is a future consideration
- Current priority is flood detection (Pike module)
- Can be evaluated later when rate limiting requirements are clearer

**Status:** ⏸️ **DEFERRED** - Will revisit in future phase

---

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

## Task 0.1.3: Permissions Module - **SKIPPED**

**Decision:** Skip permissions module testing

**Rationale:**
- Fail2Ban already provides effective IP blocking at firewall level (iptables/ufw)
- Fail2Ban blocks packets before they reach OpenSIPS (more effective)
- Permissions module would block at application level (less effective, adds load)
- Fail2Ban already implemented and working for brute force detection
- No clear advantage of permissions module over Fail2Ban for our use case
- Pike module handles automatic flood-based IP blocking
- Manual IP blocking can use Fail2Ban whitelist/ban management

**Conclusion:** Fail2Ban is sufficient for IP blocking needs. Permissions module testing is unnecessary.

**See:** `docs/PHASE-0-PERMISSIONS-DECISION.md` for detailed analysis

---

## Task 0.1.4: Create Architecture Decision Document

### Step 1: Compile All Findings
**Time:** 30 minutes

1. Review all test results:
   - Pike module results
   - Ratelimit module decision (deferred - will revisit later)
   - Permissions module decision (skipped - using Fail2Ban)

2. Compare modules against requirements:
   - Does pike meet flood detection needs?
   - Rate limiting: Deferred for future evaluation
   - Does Fail2Ban meet IP blocking needs? (permissions module skipped)

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
     - Decision: Deferred - Will evaluate in future phase
     - Rationale: Not immediate priority, can be added later
     - Configuration approach: TBD when evaluated
   - **IP Blocking:**
     - Decision: Use Fail2Ban (permissions module skipped)
     - Rationale: Fail2Ban provides firewall-level blocking (more effective)
     - Configuration: Already implemented

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
- [x] Ratelimit module decision made (deferred - will revisit later)
- [x] Permissions module decision made (skipped - using Fail2Ban)
- [ ] Architecture decision document created
- [ ] All findings reviewed and decisions made
- [ ] Ready to proceed to Phase 1

---

## Estimated Time

- Task 0.1.1 (Pike): ~2 hours
- Task 0.1.2 (Ratelimit): **DEFERRED** - Will revisit later
- Task 0.1.3 (Permissions): **SKIPPED** - Decision made (using Fail2Ban)
- Task 0.1.4 (Architecture): ~1.5 hours
- **Total:** ~3.5 hours (can be done over multiple sessions)

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
