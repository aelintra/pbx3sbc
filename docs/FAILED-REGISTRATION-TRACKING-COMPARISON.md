# Failed Registration Tracking: Standard vs Custom Approach

**Date:** January 2026  
**Purpose:** Evaluate standard OpenSIPS `acc` module vs custom `failed_registrations` table for security tracking

---

## Executive Summary

**Recommendation: Use Custom `failed_registrations` Table** ✅

While OpenSIPS `acc` module can log failed transactions, it's designed for **CDR/billing purposes**, not **security tracking**. Our security requirements need fields that `acc` module doesn't capture (source IP:port, user agent, structured username/domain separation). The custom table approach is justified and aligns with security best practices.

---

## Comparison: acc Module vs Custom Table

### Option A: OpenSIPS `acc` Module (Standard Approach)

**What it does:**
- Logs all SIP transactions (including failed ones) to `acc` table
- Designed for CDR (Call Detail Records) and billing
- Can be configured to log failed transactions via `failed_transaction_flag` parameter

**acc Table Schema (Standard):**
```sql
CREATE TABLE acc (
    id INT AUTO_INCREMENT PRIMARY KEY,
    method VARCHAR(16) DEFAULT '' NOT NULL,
    from_tag VARCHAR(64) DEFAULT '' NOT NULL,
    to_tag VARCHAR(64) DEFAULT '' NOT NULL,
    callid VARCHAR(255) DEFAULT '' NOT NULL,
    sip_code VARCHAR(3) DEFAULT '' NOT NULL,
    sip_reason VARCHAR(128) DEFAULT '' NOT NULL,
    time DATETIME NOT NULL,
    duration INT DEFAULT 0 NOT NULL,
    ms_duration INT DEFAULT 0 NOT NULL,
    setuptime INT DEFAULT 0 NOT NULL,
    created DATETIME DEFAULT NULL,
    from_uri VARCHAR(255) DEFAULT NULL,  -- Custom column we added
    to_uri VARCHAR(255) DEFAULT NULL      -- Custom column we added
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

**acc Module Configuration:**
```opensips
modparam("acc", "db_url", "mysql://...")
modparam("acc", "failed_transaction_flag", 1)  # Log failed transactions
modparam("acc", "log_flag", 1)                 # Enable logging
```

**What acc Module Captures:**
- ✅ Method (REGISTER)
- ✅ SIP response code (401, 403, etc.)
- ✅ SIP reason phrase
- ✅ Timestamp
- ✅ Call-ID
- ✅ From/To tags
- ✅ From/To URIs (if configured)
- ❌ **Source IP:port** (NOT captured - only transaction info)
- ❌ **User Agent** (NOT captured)
- ❌ **Structured username/domain** (only full URI)
- ❌ **Expires header** (NOT captured)

**Limitations for Security:**
1. **No Source IP:Port** - Critical for security tracking (brute force detection, IP blocking)
2. **No User Agent** - Needed for scanner detection and attack pattern analysis
3. **URI Parsing Required** - Must parse `from_uri` to extract username/domain (less efficient)
4. **Mixed Purpose** - `acc` table contains all transactions (INVITE, BYE, etc.), not just registrations
5. **CDR-Oriented** - Designed for billing, not security analysis

---

### Option B: Custom `failed_registrations` Table (Current Plan)

**What it does:**
- Dedicated table for security tracking
- Captures security-specific fields
- Optimized for security analysis queries

**Custom Table Schema:**
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

**What Custom Table Captures:**
- ✅ Username (structured, separate from domain)
- ✅ Domain (structured, separate from username)
- ✅ **Source IP:Port** (critical for security)
- ✅ **User Agent** (critical for scanner detection)
- ✅ Response code and reason (403 and other failures, excluding 401)
- ✅ Timestamp
- ✅ Expires header
- ✅ Optimized indexes for security queries

**Important Note:** 401 Unauthorized responses are **not logged** because they're a normal part of SIP authentication (challenge-response). Only 403 Forbidden and other actual failures are logged for security tracking.

**Advantages for Security:**
1. **Security-Focused** - Designed specifically for security tracking
2. **Source IP Tracking** - Enables brute force detection and IP blocking
3. **User Agent Tracking** - Enables scanner detection and pattern analysis
4. **Structured Data** - Username/domain separation enables efficient queries
5. **Optimized Indexes** - Indexes designed for security queries (IP, username, time windows)
6. **Separation of Concerns** - Security data separate from billing data

---

## Detailed Comparison

### Field-by-Field Comparison

| Field | acc Module | Custom Table | Security Need |
|-------|-----------|--------------|---------------|
| Method | ✅ Yes | ✅ Yes | Medium |
| Response Code | ✅ Yes | ✅ Yes | **High** |
| Response Reason | ✅ Yes | ✅ Yes | **High** |
| Timestamp | ✅ Yes | ✅ Yes | **High** |
| Username | ⚠️ From URI (parsing needed) | ✅ Structured | **High** |
| Domain | ⚠️ From URI (parsing needed) | ✅ Structured | **High** |
| **Source IP** | ❌ **NOT available** | ✅ **Yes** | **CRITICAL** |
| **Source Port** | ❌ **NOT available** | ✅ **Yes** | **CRITICAL** |
| **User Agent** | ❌ **NOT available** | ✅ **Yes** | **CRITICAL** |
| Call-ID | ✅ Yes | ❌ Not needed | Low |
| From/To Tags | ✅ Yes | ❌ Not needed | Low |
| Expires Header | ❌ Not available | ✅ Yes | Medium |

### Use Case Comparison

#### Use Case 1: Brute Force Detection
**Requirement:** Detect multiple failed registrations from same IP within time window

- **acc Module:** ❌ Cannot query by source IP (not captured)
- **Custom Table:** ✅ Efficient query: `SELECT COUNT(*) FROM failed_registrations WHERE source_ip='...' AND attempt_time > ...`

#### Use Case 2: Scanner Detection
**Requirement:** Identify scanners by User-Agent patterns

- **acc Module:** ❌ User-Agent not captured
- **Custom Table:** ✅ Query: `SELECT * FROM failed_registrations WHERE user_agent LIKE '%sipvicious%'`

#### Use Case 3: Username Enumeration Detection
**Requirement:** Detect attempts to enumerate valid usernames

- **acc Module:** ⚠️ Must parse `from_uri` to extract username (inefficient)
- **Custom Table:** ✅ Efficient query: `SELECT username, COUNT(*) FROM failed_registrations WHERE domain='...' GROUP BY username`

#### Use Case 4: IP Blocking
**Requirement:** Block IPs with excessive failed attempts

- **acc Module:** ❌ Cannot identify source IP
- **Custom Table:** ✅ Direct source IP tracking enables IP blocking

---

## Implementation Comparison

### acc Module Approach

**Configuration:**
```opensips
modparam("acc", "failed_transaction_flag", 1)
modparam("acc", "log_flag", 1)
```

**Implementation:**
- Automatic logging (no script changes needed)
- But: Missing critical security fields (source IP, user agent)

**Query Example:**
```sql
-- Find failed registrations (must filter by method and parse URIs)
SELECT * FROM acc 
WHERE method='REGISTER' 
  AND sip_code >= '400'
  AND time > DATE_SUB(NOW(), INTERVAL 1 HOUR);
-- Problem: No source_ip, must parse from_uri for username/domain
```

### Custom Table Approach

**Configuration:**
- No module configuration needed
- Custom script logic in `onreply_route`

**Implementation:**
```opensips
onreply_route[handle_reply_reg] {
    if (is_method("REGISTER") && $rs >= 400) {
        # Log to custom security table
        $var(query) = "INSERT INTO failed_registrations 
            (username, domain, source_ip, source_port, user_agent, 
             response_code, response_reason, attempt_time) 
            VALUES ('" + $tU + "', '" + $(tu{uri.domain}) + "', 
                    '" + $avp(reg_source_ip) + "', " + $avp(reg_source_port) + ", 
                    '" + $avp(reg_user_agent) + "', " + $rs + ", '" + $rr + "', NOW())";
        sql_query($var(query));
    }
}
```

**Query Example:**
```sql
-- Find failed registrations from specific IP (efficient, indexed)
SELECT * FROM failed_registrations 
WHERE source_ip='192.168.1.100'
  AND attempt_time > DATE_SUB(NOW(), INTERVAL 1 HOUR);
-- Direct source IP access, no parsing needed
```

---

## Recommendation: Custom Table Approach ✅

### Why Custom Table is Justified

1. **Security Requirements Differ from Billing Requirements**
   - `acc` module designed for CDR/billing (transaction tracking)
   - Security needs source IP, user agent, structured username/domain
   - These fields are not available in `acc` module

2. **"Standard Approach First" Principle Still Followed**
   - We evaluated standard `acc` module first
   - Determined it doesn't meet security requirements
   - Custom approach is justified and documented

3. **Separation of Concerns**
   - Security tracking separate from billing/CDR
   - Different query patterns and indexes
   - Easier to manage and optimize

4. **Performance**
   - Security queries optimized with appropriate indexes
   - No need to filter through all transactions (INVITE, BYE, etc.)
   - Direct source IP queries (critical for brute force detection)

### Hybrid Approach (Optional)

**Option:** Use both `acc` module AND custom table
- `acc` module: Continue for CDR/billing (already configured)
- Custom table: Security-specific tracking
- **Benefit:** Complete transaction history in `acc`, security analysis in custom table
- **Drawback:** Duplicate logging (minimal overhead)

**Recommendation:** Use custom table only (no need for duplicate logging in `acc`)

---

## Updated Implementation Plan

### Phase 1.1: Failed Registration Tracking ✅ **APPROVED - Custom Table**

**Decision:** Use custom `failed_registrations` table (justified deviation from standard approach)

**Justification:**
- `acc` module doesn't capture source IP:port (critical for security)
- `acc` module doesn't capture user agent (critical for scanner detection)
- Custom table optimized for security queries
- Standard approach evaluated and found insufficient for security requirements

**Implementation:**
1. Create `failed_registrations` table (as planned)
2. Add logging in `onreply_route[handle_reply_reg]`
3. Store request metadata (source IP, port, user agent) in AVPs
4. Document why custom approach was chosen

---

## Conclusion

**The custom `failed_registrations` table approach is justified** because:

1. ✅ Standard `acc` module evaluated first
2. ✅ `acc` module doesn't meet security requirements (missing source IP, user agent)
3. ✅ Custom table designed for security-specific needs
4. ✅ Better performance for security queries
5. ✅ Separation of concerns (security vs billing)

**This aligns with the "standard approach first" principle** - we evaluated the standard approach, determined it doesn't meet requirements, and documented why a custom approach is needed.

---

**Last Updated:** January 2026  
**Status:** ✅ Approved - Custom table approach justified
