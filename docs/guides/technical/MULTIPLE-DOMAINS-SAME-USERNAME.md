# Multiple Domains for Same Username - Critical Multi-Tenant Issue

**Purpose:** This document explains the critical problem of same username in multiple domains and the required solution for multi-tenant deployments.

**Date:** January 2026  
**Status:** ⚠️ **CRITICAL** - Must be solved for production  
**Related:** 
- [WHY-USERNAME-ONLY-LOOKUP.md](WHY-USERNAME-ONLY-LOOKUP.md) - Why username-only lookup is needed
- [USRLOC-MIGRATION-PLAN.md](USRLOC-MIGRATION-PLAN.md) - Implementation details

---

## ⚠️ CRITICAL BUSINESS REQUIREMENT

**Problem:** This is a **drop-in solution** for customers with fleets of Asterisk boxes, typically one or more per customer.

**Traditional Telephony Legacy:**
- Traditional telephony systems used repeating extension number ranges
- **2XX range is most common** (201, 202, 203, ... 299)
- This practice persisted when customers migrated to VoIP
- **Customers did NOT want to change extension numbers**

**Multi-Tenant Reality:**
```
Customer A (tenant-a.com):
  - Asterisk A: 10.0.1.10
  - Extensions: 201, 202, 203, ... 299
  - 401@tenant-a.com → Asterisk A

Customer B (tenant-b.com):
  - Asterisk B: 10.0.1.20
  - Extensions: 201, 202, 203, ... 299  ← SAME NUMBERS!
  - 401@tenant-b.com → Asterisk B

Customer C (tenant-c.com):
  - Asterisk C: 10.0.1.30
  - Extensions: 201, 202, 203, ... 299  ← SAME NUMBERS!
  - 401@tenant-c.com → Asterisk C
```

**The Problem:**
- When Asterisk sends: `INVITE sip:401@192.168.1.138:5060`
- We **MUST** route to the correct customer's endpoint
- **NOT** just "first match" - that would route to wrong customer!

**Impact:** 
- ❌ **Calls would go to wrong customer** (privacy/security issue)
- ❌ **Billing would be wrong** (wrong tenant charged)
- ❌ **Service would be broken** (calls fail or go to wrong place)

---

## The Scenario

**Problem:** What happens when username `401` is registered in multiple domains?

**Example:**
```
location table:
  username=401, domain=tenant-a.com, contact=sip:401@10.0.1.100:5060
  username=401, domain=tenant-b.com, contact=sip:401@10.0.1.200:5060
  username=401, domain=tenant-c.com, contact=sip:401@10.0.1.300:5060
```

**Question:** When we do `lookup("location", "uri", "sip:401@*")`, which one is returned?

**Answer:** **First match** - but this is **WRONG** for multi-tenant scenarios!

---

## Current Implementation Behavior

### SQL-Based Lookup (Current)

**Code:** `config/opensips.cfg.template` lines 620-635

```opensips
# Username-only lookup with LIMIT 1
$var(query) = "SELECT contact_ip FROM endpoint_locations 
               WHERE aor LIKE '401@%' 
               AND expires > NOW() 
               LIMIT 1";
```

**Behavior:**
- ✅ Returns **first match** (non-deterministic)
- ⚠️ Order depends on database storage/retrieval order
- ⚠️ May vary between queries
- ⚠️ No guarantee which domain is selected

**Example:**
```sql
-- Query 1 might return:
401@example.com → 10.0.1.100:5060

-- Query 2 might return:
401@test.com → 10.0.1.200:5060
```

**Problem:** Non-deterministic - same request might route to different endpoints!

---

## OpenSIPS `usrloc` Module Behavior

### Wildcard Lookup Behavior

**Syntax:**
```opensips
lookup("location", "uri", "sip:401@*")
```

**Expected Behavior:**
- Returns **first match** found in location table
- Order depends on usrloc module's internal storage/retrieval
- May be deterministic (based on insertion order) or non-deterministic
- **⚠️ Needs verification** - exact behavior may vary by OpenSIPS version

**What Gets Set:**
- `$du` - Destination URI (first match's contact)
- `$dst_uri` - Destination URI (alternative)
- `$dst_domain` - Destination domain (first match's domain)

**Example:**
```opensips
# If location table has:
#   401@example.com → sip:401@10.0.1.100:5060
#   401@test.com → sip:401@10.0.1.200:5060

lookup("location", "uri", "sip:401@*");
# Returns: First match (could be either domain)
# $du = "sip:401@10.0.1.100:5060" OR "sip:401@10.0.1.200:5060"
```

---

## Implications

### 1. Non-Deterministic Routing

**Problem:** Same username in multiple domains may route to different endpoints.

**Example:**
```
Request 1: INVITE sip:401@192.168.1.138
  → lookup("location", "uri", "sip:401@*")
  → Routes to: 401@example.com (10.0.1.100)

Request 2: INVITE sip:401@192.168.1.138  
  → lookup("location", "uri", "sip:401@*")
  → Routes to: 401@test.com (10.0.1.200)  ← Different!
```

**Impact:**
- Calls may go to wrong endpoint
- Inconsistent behavior
- Hard to debug

### 2. Load Balancing Effect

**Potential Benefit:** If multiple domains have same username, requests might be distributed across them.

**But:** This is **unintentional load balancing** - not controlled or predictable.

### 3. Multi-Tenant Confusion

**Problem:** In multi-tenant scenarios, same username in different domains should route to different tenants.

**Example:**
```
Tenant A: 401@tenant-a.com → Asterisk A
Tenant B: 401@tenant-b.com → Asterisk B

If Request-URI has IP, we can't determine which tenant!
```

---

## When This Happens

### Scenario 1: Legitimate Multi-Domain

**Case:** Same user legitimately registered in multiple domains.

**Example:**
- User `401` has extension in `example.com`
- User `401` also has extension in `test.com`
- Both are valid, active registrations

**Current Behavior:** First match wins (non-deterministic)

### Scenario 2: Registration Error

**Case:** Registration error causes duplicate entries.

**Example:**
- User `401` registers with `example.com`
- Registration fails, but record created
- User re-registers with `test.com`
- Both records exist (one expired, one active)

**Current Behavior:** Should only return active (non-expired) - handled by `expires > NOW()` check

### Scenario 3: Domain Migration

**Case:** User migrated from one domain to another.

**Example:**
- User `401` was in `old-domain.com`
- User `401` migrated to `new-domain.com`
- Old registration not cleaned up

**Current Behavior:** May route to old domain if it's still active

---

## Current Implementation Details

### SQL Query Order

**Current Code:**
```sql
SELECT contact_ip FROM endpoint_locations 
WHERE aor LIKE '401@%' 
AND expires > NOW() 
LIMIT 1
```

**Order:** Database-dependent (typically insertion order or primary key order)

**MySQL Behavior:**
- Without `ORDER BY`, order is **not guaranteed**
- May vary between queries
- May vary between MySQL versions
- May vary based on table structure/indexes

**Example:**
```sql
-- Table order (insertion order):
401@example.com (inserted first)
401@test.com (inserted second)

-- Query might return:
-- First match: 401@example.com
-- OR (if index order differs):
-- First match: 401@test.com
```

### Multiple Queries Issue

**Current Code Problem:**
```opensips
# Query 1: Get IP
SELECT contact_ip FROM endpoint_locations WHERE aor LIKE '401@%' LIMIT 1;
# Returns: 10.0.1.100 (from 401@example.com)

# Query 2: Get port  
SELECT contact_port FROM endpoint_locations WHERE aor LIKE '401@%' LIMIT 1;
# Returns: 5060 (from 401@test.com)  ← DIFFERENT DOMAIN!

# Query 3: Get contact_uri
SELECT contact_uri FROM endpoint_locations WHERE aor LIKE '401@%' LIMIT 1;
# Returns: sip:401@10.0.1.200 (from 401@test.com)  ← DIFFERENT AGAIN!
```

**Problem:** Each query might return a different domain's data!

**Current Mitigation:** Code does get `aor` in last query to identify which domain was selected, but this is still problematic.

---

## OpenSIPS `usrloc` Behavior (Expected)

### Single Lookup Call

**Advantage:** `lookup()` is a single function call, not multiple queries.

```opensips
if (lookup("location", "uri", "sip:401@*")) {
    # $du is set from single lookup
    # All data (contact, domain, etc.) comes from same record
    route(RELAY);
}
```

**Benefit:** 
- ✅ Consistent - all data from same domain
- ✅ No mixing of data from different domains
- ✅ Single atomic operation

**But:** Still returns first match (non-deterministic which domain)

---

## Potential Solutions

### Solution 1: Accept First Match (Current Approach)

**Approach:** Accept that first match is returned.

**Pros:**
- ✅ Simple
- ✅ Matches current behavior
- ✅ Fast (no additional queries)

**Cons:**
- ⚠️ Non-deterministic
- ⚠️ May route to wrong domain
- ⚠️ Hard to debug

**When Acceptable:**
- Single domain deployments
- Username uniqueness guaranteed
- Non-critical routing

### Solution 2: Prefer Specific Domain

**Approach:** If domain can be inferred, use it.

**Example:**
```opensips
# Try to infer domain from context
# If Request-URI has IP, but To header has domain:
$var(to_domain) = $(tu{uri.domain});
if ($var(to_domain) != "" && $var(to_domain) !~ "^[0-9]") {
    # To header has domain - use exact lookup
    if (lookup("location", "uri", "sip:" + $var(username) + "@" + $var(to_domain))) {
        route(RELAY);
    }
} else {
    # Fallback to wildcard
    lookup("location", "uri", "sip:" + $var(username) + "@*");
}
```

**Pros:**
- ✅ More deterministic
- ✅ Uses domain when available

**Cons:**
- ⚠️ More complex
- ⚠️ Still has fallback to wildcard

### Solution 3: Order by Priority/Preference

**Approach:** Query with `ORDER BY` to prefer certain domains.

**Example:**
```sql
SELECT contact_ip FROM endpoint_locations 
WHERE aor LIKE '401@%' 
AND expires > NOW() 
ORDER BY 
    CASE domain 
        WHEN 'example.com' THEN 1  -- Prefer example.com
        WHEN 'test.com' THEN 2    -- Then test.com
        ELSE 3                     -- Then others
    END
LIMIT 1
```

**Pros:**
- ✅ Deterministic
- ✅ Configurable priority

**Cons:**
- ⚠️ Requires domain priority configuration
- ⚠️ More complex
- ⚠️ Not available in `lookup()` function (would need SQL)

### Solution 4: Return All Matches, Select Best

**Approach:** Get all matches, then select based on criteria.

**Example:**
```opensips
# Get all domains for username
$var(query) = "SELECT domain, contact FROM location 
               WHERE username='401' 
               AND expires > UNIX_TIMESTAMP(NOW())";
sql_query($var(query), "$avp(domains)");

# Select best match (e.g., most recent, preferred domain, etc.)
# Then do lookup with specific domain
```

**Pros:**
- ✅ Full control
- ✅ Can implement complex selection logic

**Cons:**
- ⚠️ Very complex
- ⚠️ Performance impact (multiple queries)
- ⚠️ Bypasses usrloc module optimizations

### Solution 5: Prevent Duplicate Usernames

**Approach:** Enforce username uniqueness across domains.

**Implementation:**
- Database constraint: Unique username across all domains
- Registration validation: Reject if username exists in another domain
- Cleanup: Remove old registrations when new one created

**Pros:**
- ✅ Eliminates problem at source
- ✅ Deterministic behavior
- ✅ Simpler code

**Cons:**
- ⚠️ May not be acceptable for multi-tenant scenarios
- ⚠️ Requires business logic changes

---

## ⚠️ CRITICAL: Required Solution for Multi-Tenant

### The Problem with "First Match"

**Current "First Match" Approach is UNACCEPTABLE for multi-tenant deployments:**

```
Scenario:
  - Customer A: 401@tenant-a.com registered
  - Customer B: 401@tenant-b.com registered
  - Asterisk A (Customer A) sends: INVITE sip:401@192.168.1.138

With "first match":
  - lookup("location", "uri", "sip:401@*") might return 401@tenant-b.com
  - Call routes to Customer B's endpoint ← WRONG CUSTOMER!
  - Privacy violation, billing error, service failure
```

**This is a CRITICAL bug that must be fixed before production deployment.**

---

## Required Solution: Domain Context from Source IP

### How OpenSIPS Handles Multiple Domains

**OpenSIPS Architecture:**
- **`domain` module** - Manages domain-specific information and recognizes which domains are local
- **`usrloc` module** - Stores user location bindings with `username@domain` as the key
- **Lookups use full SIP URI** - `lookup("location", "uri", "sip:user@domain")` uses the complete AoR, not just username

**Key Point:** OpenSIPS treats `user@domainA` and `user@domainB` as **completely separate entities**:
- Each stored separately in `location` table
- Each has distinct contact information
- Lookups are domain-specific by design

**This means:** When we do `lookup("location", "uri", "sip:401@tenant-a.com")`, OpenSIPS will **only** find contacts for `401@tenant-a.com`, never `401@tenant-b.com`.

### Solution: Determine Domain from Asterisk Source IP

**Key Insight:** When Asterisk sends a request, we know which Asterisk it came from (source IP). We can use this to determine which customer/domain it belongs to.

**Architecture:**
```
Asterisk A (10.0.1.10) → Dispatcher Set 10 → Domain tenant-a.com
Asterisk B (10.0.1.20) → Dispatcher Set 20 → Domain tenant-b.com
Asterisk C (10.0.1.30) → Dispatcher Set 30 → Domain tenant-c.com
```

**Solution Approach:**
1. **Identify source Asterisk** - Use source IP (`$si`) from incoming request
2. **Find dispatcher set** - Query dispatcher table to find which setid this Asterisk belongs to
3. **Find domain(s)** - Query domain table to find which domain(s) use this setid
4. **Lookup endpoint in correct domain** - Use domain-specific lookup: `lookup("location", "uri", "sip:username@domain")`

**Why This Works:**
- OpenSIPS `usrloc` module stores contacts with `username@domain` as the key
- `lookup("location", "uri", "sip:401@tenant-a.com")` will **only** find contacts in `tenant-a.com`
- It will **never** find contacts from `tenant-b.com` or `tenant-c.com`
- This is built into OpenSIPS architecture - no wildcard needed!

**Implementation:**
```opensips
# When request comes from Asterisk (source IP = $si)
# 1. Find which dispatcher set this Asterisk belongs to
$var(query) = "SELECT setid FROM dispatcher WHERE destination LIKE '%" + $si + "%' LIMIT 1";
sql_query($var(query), "$avp(asterisk_setid)");
$var(setid) = $(avp(asterisk_setid)[0]);

# 2. Find which domain(s) use this setid
$var(query) = "SELECT domain FROM domain WHERE setid='" + $var(setid) + "' LIMIT 1";
sql_query($var(query), "$avp(domain_name)");
$var(domain) = $(avp(domain_name)[0]);

# 3. Lookup endpoint in correct domain only
if ($var(domain) != "") {
    # Use domain-specific lookup (CORRECT for multi-tenant)
    # OpenSIPS will ONLY find contacts in this domain, never other domains
    if (lookup("location", "uri", "sip:" + $var(username) + "@" + $var(domain))) {
        # Found contact in correct domain - $du is set automatically
        route(RELAY);
    } else {
        sl_send_reply(404, "User Not Found");
    }
} else {
    # Fallback: wildcard lookup (only if domain cannot be determined)
    # This should rarely happen if configuration is correct
    # ⚠️ WARNING: Wildcard lookup may return wrong domain in multi-tenant scenarios
    xlog("L_WARN", "Cannot determine domain from source IP $si, using wildcard lookup (may route to wrong customer)\n");
    if (lookup("location", "uri", "sip:" + $var(username) + "@*")) {
        route(RELAY);
    } else {
        sl_send_reply(404, "User Not Found");
    }
}
```

**Benefits:**
- ✅ Routes to correct customer/domain
- ✅ No privacy violations
- ✅ Correct billing
- ✅ Deterministic behavior

**Challenges:**
- ⚠️ Requires dispatcher → domain mapping
- ⚠️ Requires source IP matching (may need to handle port variations)
- ⚠️ More complex than simple wildcard lookup

---

## ✅ Confirmed Behavior: Duplication Rules

### Username Duplication Rules

**With `use_domain = 1` (enabled) in usrloc module:**

✅ **ALLOWED:** Same username across different domains
- `401@tenant-a.com` ✅
- `401@tenant-b.com` ✅
- `401@tenant-c.com` ✅
- All can exist simultaneously

❌ **NOT ALLOWED:** Same username within the same domain
- `401@tenant-a.com` (first registration) ✅
- `401@tenant-a.com` (second registration) ❌ - Would overwrite or conflict
- Uniqueness is enforced **within each domain only**

**This matches your requirement:**
- ✅ Duplication of username **across domains** (different customers can have same extension)
- ❌ No duplication **within a domain** (same customer can't have duplicate extension)

### Multiple Contacts for Same AoR

**Question:** What if the same user registers from multiple devices?

**Example:**
```
User 401@tenant-a.com registers from:
  - Device 1: sip:401@10.0.1.100:5060
  - Device 2: sip:401@10.0.1.101:5060
```

**OpenSIPS Behavior:**
- OpenSIPS `usrloc` module **supports multiple contacts** for the same AoR
- Each contact is stored as a separate row in `location` table
- `lookup("location")` can return multiple contacts (for load balancing, parallel forking, etc.)
- Typically returns first contact or uses q-value for priority

**For Our Use Case:**
- If `401@tenant-a.com` has multiple contacts, `lookup()` will handle it
- May return first contact, or use q-value for priority
- This is standard SIP behavior (parallel forking, load balancing)

**Key Point:** The domain context solution ensures we only look in the correct domain, but within that domain, OpenSIPS handles multiple contacts normally.

---

## Recommended Approach

### For Multi-Tenant Production Deployment

**Recommendation:** **MUST implement domain context from source IP (Solution above)**

**Rationale:**
1. **Business requirement** - Multi-tenant deployments require correct routing
2. **Security/Privacy** - Wrong routing = privacy violation
3. **Billing** - Wrong routing = billing errors
4. **Service Quality** - Wrong routing = broken service

**Implementation Priority:** **HIGH** - This must be implemented before production deployment.

**Fallback:** Only use wildcard lookup (`@*`) as last resort if domain cannot be determined.

### For Future Enhancement

**If Problem Occurs:** Implement Solution 2 (prefer domain from To header when available)

**If Critical:** Implement Solution 3 (domain priority) or Solution 5 (enforce uniqueness)

---

## Testing Scenarios

### Test Case 1: Multiple Domains, Same Username

**Setup:**
```
Register: 401@example.com → 10.0.1.100:5060
Register: 401@test.com → 10.0.1.200:5060
```

**Test:**
```
Send: INVITE sip:401@192.168.1.138:5060
```

**Expected:**
- Routes to one of the domains (first match)
- Should be consistent (same domain for same request)
- May vary between requests (non-deterministic)

**Verify:**
- Check which domain was selected
- Verify routing is correct
- Check logs for which AoR was found

### Test Case 2: Expired vs Active

**Setup:**
```
Register: 401@example.com → 10.0.1.100:5060 (expired)
Register: 401@test.com → 10.0.1.200:5060 (active)
```

**Test:**
```
Send: INVITE sip:401@192.168.1.138:5060
```

**Expected:**
- Should only return active registration (401@test.com)
- Should NOT return expired registration

**Verify:**
- Only active registration is used
- Expired registration is ignored

### Test Case 3: Domain Priority (if implemented)

**Setup:**
```
Register: 401@example.com → 10.0.1.100:5060 (priority 1)
Register: 401@test.com → 10.0.1.200:5060 (priority 2)
```

**Test:**
```
Send: INVITE sip:401@192.168.1.138:5060
```

**Expected:**
- Should return 401@example.com (higher priority)
- Should be deterministic

---

## Documentation Requirements

### Code Comments

Add comments explaining behavior:

```opensips
# Username-only lookup with wildcard domain
# NOTE: If username exists in multiple domains, first match is returned
# This may be non-deterministic - consider enforcing username uniqueness
if (lookup("location", "uri", "sip:" + $var(username) + "@*")) {
    route(RELAY);
}
```

### Configuration Documentation

Document in deployment guide:
- Username uniqueness across domains
- Expected behavior with duplicate usernames
- How to prevent duplicate usernames

### Logging

Add logging to identify when multiple domains exist:

```opensips
# After lookup, log which domain was selected
xlog("Username-only lookup for $var(username): selected domain=$dst_domain, contact=$du\n");
```

---

## ✅ Confirmed: Duplication Rules

### Answer to Your Question

**Q: "This will give us duplication of username across domains but NOT within a domain. Correct?"**

**A: YES - That is correct!**

**With `use_domain = 1` enabled in usrloc module:**

✅ **ALLOWED:** Same username across different domains
```
401@tenant-a.com  ✅
401@tenant-b.com  ✅
401@tenant-c.com ✅
```
All can exist simultaneously - this is what you need for multi-tenant!

❌ **NOT ALLOWED:** Same username within the same domain
```
401@tenant-a.com (first registration)  ✅
401@tenant-a.com (second registration) ❌ - Would overwrite or conflict
```
Uniqueness is enforced **within each domain only**.

**This matches your business requirement:**
- ✅ Different customers (domains) can have same extension numbers (2XX range)
- ❌ Same customer (domain) cannot have duplicate extension numbers

### Multiple Contacts for Same AoR

**What if same user registers from multiple devices?**

OpenSIPS `usrloc` module **supports multiple contacts** for the same AoR:
- Each device registration creates a separate contact record
- All contacts share the same `username@domain` (AoR)
- `lookup()` can return multiple contacts (for parallel forking, load balancing)
- This is standard SIP behavior

**Example:**
```
User 401@tenant-a.com registers from:
  - Phone 1: sip:401@10.0.1.100:5060
  - Phone 2: sip:401@10.0.1.101:5060

Both stored as separate contacts for AoR: 401@tenant-a.com
lookup("location", "uri", "sip:401@tenant-a.com") handles both
```

**For Our Use Case:**
- Domain context ensures we only look in correct domain
- Within that domain, OpenSIPS handles multiple contacts normally
- This is acceptable and standard SIP behavior

---

## Summary

### ⚠️ CRITICAL ISSUE FOR MULTI-TENANT DEPLOYMENTS

**Business Context:**
- Drop-in solution for customers with multiple Asterisk boxes
- Traditional telephony used repeating extension ranges (2XX most common)
- **Same extension numbers across different customers/domains**
- **Example:** Customer A, B, C all have extension 401

**Current Behavior (UNACCEPTABLE):**

- ❌ Returns **first match** (non-deterministic)
- ❌ May route to **wrong customer** (privacy/security violation)
- ❌ May cause **billing errors** (wrong tenant charged)
- ❌ May cause **service failures** (calls go to wrong place)

**Required Solution:**

- ✅ **MUST determine domain from source IP** (which Asterisk sent request)
- ✅ **MUST lookup endpoint only in correct domain**
- ✅ **MUST NOT use wildcard lookup** (`@*`) as primary method
- ✅ **Wildcard lookup only as fallback** if domain cannot be determined

### Implementation Requirements

1. **Identify source Asterisk** - Use source IP (`$si`) to find dispatcher set
2. **Find domain** - Use dispatcher setid to find domain
3. **Domain-specific lookup** - Lookup endpoint only in that domain
4. **Fallback** - Only use wildcard if domain cannot be determined

### Key Points

- **Current:** `LIMIT 1` returns first match (non-deterministic) - **UNACCEPTABLE**
- **OpenSIPS:** `lookup()` returns first match - **STILL UNACCEPTABLE**
- **Risk:** **CRITICAL** - Wrong customer routing in multi-tenant scenarios
- **Solution:** **MUST implement domain context from source IP**
- **Priority:** **HIGH** - Must be implemented before production

### Migration Impact

**This changes the migration plan:**
- Cannot simply use `lookup("location", "uri", "sip:username@*")` as primary method
- Must implement domain determination logic
- Must test thoroughly with multiple tenants
- Must document domain context requirement

---

**Status:** ✅ Documented  
**Action Required:** Verify exact `lookup()` behavior with multiple domains in OpenSIPS version
