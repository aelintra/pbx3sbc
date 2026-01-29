# Phase 3.1 Security Event Logging - Deferred Analysis

**Date:** January 2026  
**Status:** ❌ **DEFERRED**  
**Decision:** Skip Phase 3.1 - Low value, minimal unique events

---

## Executive Summary

**Recommendation: Skip Phase 3.1 (`security_events` table)**

After analysis, Phase 3.1 would provide minimal value because:
1. Only one unique event type can be logged from OpenSIPS (`flood_detected` from Pike)
2. All other events are either already captured in detailed tables or happen outside OpenSIPS
3. Existing logging mechanisms (detailed tables, xlog, Fail2ban logs) already provide comprehensive coverage

---

## Proposed `security_events` Table

**Schema:**
```sql
CREATE TABLE security_events (
    id INT AUTO_INCREMENT PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL,      -- 'registration_failure', 'scanner_detected', 'flood_detected', etc.
    severity VARCHAR(20) NOT NULL,        -- 'info', 'warning', 'error', 'critical'
    source_ip VARCHAR(45) DEFAULT NULL,
    aor VARCHAR(255) DEFAULT NULL,
    description TEXT,
    event_time DATETIME NOT NULL,
    resolved BOOLEAN DEFAULT FALSE,
    resolved_at DATETIME DEFAULT NULL,
    ...
)
```

**Event Types Planned:**
- `registration_failure` - Failed registration attempt
- `scanner_detected` - Known scanner detected
- `flood_detected` - Flood attack detected
- `brute_force_detected` - Brute force attack detected
- `rate_limit_exceeded` - Rate limit violation
- `ip_blocked` - IP address blocked
- `username_enumeration` - Possible username enumeration

---

## Analysis: What Can OpenSIPS Actually Log?

### ✅ Events OpenSIPS CAN Log

**1. `flood_detected` - Pike Module**
- **Source:** `event_route[E_PIKE_BLOCKED]`
- **Status:** ✅ Can be logged from OpenSIPS
- **Current Logging:** Already logged via `xlog()` in event route
- **Value:** Only one unique event type that isn't already captured elsewhere

### ❌ Events Already in Detailed Tables

**2. `registration_failure`**
- **Overlaps with:** `failed_registrations` table
- **Status:** ❌ Already captured in detail
- **Detail Level:** `failed_registrations` has username, domain, source IP, user agent, response code, etc.
- **Value:** Would duplicate existing data

**3. `scanner_detected`**
- **Overlaps with:** `door_knock_attempts` table (when `reason='scanner_detected'`)
- **Status:** ❌ Already captured in detail
- **Detail Level:** `door_knock_attempts` has domain, source IP, user agent, method, request URI, reason, etc.
- **Value:** Would duplicate existing data

### ❌ Events OpenSIPS CANNOT Log

**4. `brute_force_detected`**
- **Source:** Fail2ban (external process)
- **Status:** ❌ OpenSIPS cannot detect when Fail2ban triggers
- **Why:** Fail2ban runs outside OpenSIPS, monitors log files, blocks at firewall level
- **Current Logging:** Fail2ban has its own logging system
- **Value:** Cannot be logged from OpenSIPS

**5. `ip_blocked`**
- **Manual Blocking:** Not an OpenSIPS event (admin action)
- **Fail2ban Blocking:** OpenSIPS doesn't know when Fail2ban blocks
- **Pike Blocking:** Already covered by `flood_detected`
- **Status:** ❌ Unclear/overlaps with other events
- **Value:** Cannot be logged from OpenSIPS (or overlaps with flood_detected)

### ⏸️ Events Deferred/Future

**6. `rate_limit_exceeded`**
- **Status:** ⏸️ Deferred/not implemented
- **Value:** Not applicable yet

**7. `username_enumeration`**
- **Status:** ⏸️ Future/deferred
- **Value:** Not applicable yet

---

## Conclusion

**Only one unique event** (`flood_detected` from Pike) can be logged from OpenSIPS that isn't already captured in detailed tables.

**Everything else:**
- Already in detailed tables (`failed_registrations`, `door_knock_attempts`)
- Happens outside OpenSIPS (Fail2ban, manual blocking)
- Deferred/future features

---

## Why Skip Phase 3.1

### 1. Minimal Unique Value
- Only one unique event type (`flood_detected`) that isn't already captured
- Not worth creating a whole table for one event type

### 2. Duplication Risk
- Would duplicate data already in `failed_registrations` and `door_knock_attempts`
- Creates maintenance burden (two places to update)

### 3. External Events
- Most security events (Fail2ban, manual blocking) happen outside OpenSIPS
- OpenSIPS cannot log events it doesn't know about

### 4. Existing Logging
- Pike floods already logged via `xlog()` in `event_route[E_PIKE_BLOCKED]`
- Fail2ban has its own logging system
- Detailed tables provide comprehensive data for analysis

### 5. Complexity vs. Value
- Adding another table for minimal benefit
- Would require logging code in multiple places
- Maintenance overhead without significant value

---

## Alternative: Use Existing Logging

### For Detailed Analysis
- **Use:** `failed_registrations` and `door_knock_attempts` tables
- **Provides:** Complete detailed data for security analysis

### For Flood Detection
- **Use:** Pike `xlog()` entries in `event_route[E_PIKE_BLOCKED]`
- **Monitor:** Log files or Fail2ban (if configured to monitor Pike logs)

### For Brute Force Detection
- **Use:** Fail2ban logs and status
- **Monitor:** `fail2ban-client status opensips-brute-force`
- **Query:** Fail2ban database or log files

### For Summary/Aggregation
- **Use:** SQL views (similar to Phase 1.2 approach)
- **Example:** Create views that aggregate data from detailed tables
- **Benefit:** No duplication, uses existing data

---

## Recommendation

**Skip Phase 3.1** - Focus on higher-value features:
- **Phase 3.3:** Statistics & Reporting (create views/scripts to analyze existing data)
- **Phase 5.1:** IP Blocking System (manual/administrative blocking)
- **Phase 3.2:** Alerting System (can monitor existing tables/logs)

**Future Revisit:**
If needed in the future, `security_events` table can be added when:
- More unique event types are available (rate limiting, username enumeration, etc.)
- Alerting/triage workflow requires unified event table
- Summary/aggregation needs exceed what views can provide

---

## Related Documentation

- [Security Implementation Plan](../SECURITY-IMPLEMENTATION-PLAN.md) - Overall security project plan
- [Phase 1.2 Deferred Analysis](PHASE-1.2-DEFERRED-ANALYSIS.md) - Similar value analysis for registration status tracking
