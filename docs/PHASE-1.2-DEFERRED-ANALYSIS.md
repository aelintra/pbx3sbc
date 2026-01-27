# Phase 1.2 Deferred: Registration Status Tracking - Value Analysis

**Date:** January 2026  
**Status:** ❌ **DEFERRED** - Decision made to skip this phase  
**Decision:** Skip Phase 1.2 - Information already available in existing tables

---

## Executive Summary

**Phase 1.2 (Registration Status Tracking) has been deferred** because the information it would provide is already available in existing tables (`location` and `failed_registrations`). Creating a separate `registration_status` table would add maintenance overhead without providing significant new value.

---

## What Phase 1.2 Would Provide

A `registration_status` table tracking:
- **Status:** `pending`, `registered`, `failed`, `expired`
- **Last response code/reason:** From most recent registration attempt
- **Timestamps:** `registered_at`, `failed_at`, `last_attempt_time`

**Intended Use Cases:**
- Quick lookup: "Is user X registered or failed?"
- Historical tracking: "When did they last register/fail?"
- Status summary: Count registered vs failed users

---

## What We Already Have

### 1. `location` Table (OpenSIPS usrloc module)

**Shows registered users:**
- ✅ Record exists = user is registered
- ✅ `expires > UNIX_TIMESTAMP()` = registration is active
- ✅ `last_modified` = when they registered
- ✅ `user_agent`, `callid`, `contact`, `received` fields
- ✅ Automatically cleaned up when expired

**Query Examples:**
```sql
-- Is user registered?
SELECT * FROM location 
WHERE username='40001' AND domain='example.com' 
  AND expires > UNIX_TIMESTAMP();

-- When did they register?
SELECT last_modified FROM location 
WHERE username='40001' AND domain='example.com';
```

### 2. `failed_registrations` Table

**Shows failed registration attempts:**
- ✅ `attempt_time` = when failure occurred
- ✅ `response_code`, `response_reason` = why it failed
- ✅ `username`, `domain`, `source_ip`, `user_agent`
- ✅ Only logs 403 and other failures (excludes 401)

**Query Examples:**
```sql
-- Has user failed recently?
SELECT * FROM failed_registrations 
WHERE username='40001' AND domain='example.com' 
  AND attempt_time > DATE_SUB(NOW(), INTERVAL 1 HOUR);

-- Last failure time
SELECT MAX(attempt_time) FROM failed_registrations 
WHERE username='40001' AND domain='example.com';
```

---

## Value Analysis

### ❌ Low Value Reasons

1. **Duplicate Information:**
   - **Registered status?** → Check `location` table (if record exists and `expires > NOW()`)
   - **Failed status?** → Check `failed_registrations` table
   - **Last attempt time?** → Query `location.last_modified` or `failed_registrations.attempt_time`

2. **Maintenance Overhead:**
   - Must keep in sync with `location` and `failed_registrations` tables
   - Risk of stale data if updates fail
   - Additional SQL queries on every registration (performance impact)
   - More code to maintain

3. **Can Be Replaced with SQL View:**
   - If needed later, create a view instead of maintaining a separate table
   - No maintenance overhead
   - Always reflects current state from source tables
   - No performance impact on registration process

### ✅ Potential Value (But Not Critical)

1. **Quick Lookup:**
   - Single table query instead of checking multiple tables
   - **But:** Simple JOIN query is fast enough

2. **Historical Tracking:**
   - When they last registered/failed
   - **But:** `location.last_modified` and `failed_registrations.attempt_time` already provide this

3. **Status Summary:**
   - Count registered vs failed users
   - **But:** Can be done with queries on existing tables

---

## Alternative: SQL View (If Needed Later)

If a quick status lookup is needed in the future, create a view instead of maintaining a separate table:

```sql
-- Example view (if needed later)
CREATE VIEW user_registration_status AS
SELECT 
    COALESCE(l.username, f.username) as username,
    COALESCE(l.domain, f.domain) as domain,
    CASE 
        WHEN l.contact_id IS NOT NULL AND l.expires > UNIX_TIMESTAMP() THEN 'registered'
        WHEN f.id IS NOT NULL THEN 'failed'
        ELSE 'unknown'
    END as status,
    l.last_modified as registered_at,
    MAX(f.attempt_time) as last_failed_at
FROM location l
LEFT JOIN failed_registrations f 
    ON l.username = f.username AND l.domain = f.domain
WHERE l.expires > UNIX_TIMESTAMP() OR f.id IS NOT NULL
GROUP BY username, domain;
```

**Benefits of View:**
- ✅ No maintenance overhead (always reflects current state)
- ✅ No performance impact on registration process
- ✅ Can be created/dropped as needed
- ✅ Always accurate (derived from source tables)

---

## Decision

**Skip Phase 1.2** - Focus on higher-value features:

### ✅ Higher Priority Features:
- **Phase 2.2:** Brute Force Detection (uses data we're already collecting)
- **Phase 2.3:** Flood Detection (already implemented with Pike)
- **Phase 3:** Monitoring & Alerting (actionable security features)

### Rationale:
1. Information already available in existing tables
2. Reduces maintenance overhead
3. Can add SQL view later if needed
4. Better to focus on actionable security features

---

## Impact on Project Timeline

**Original Plan:**
- Phase 1.1: Failed Registration Tracking (Week 2) ✅ **COMPLETE**
- Phase 1.2: Registration Status Tracking (Week 2-3) ❌ **DEFERRED**
- Phase 1.3: Response-Based Cleanup (Week 3) ⚠️ **REVIEW NEEDED**

**Updated Plan:**
- Phase 1.1: Failed Registration Tracking ✅ **COMPLETE**
- Phase 1.2: Registration Status Tracking ❌ **SKIPPED**
- **Next:** Phase 2.2: Brute Force Detection (can start immediately)

**Time Saved:** ~1 week (can be used for Phase 2.2 or other priorities)

---

## Related Tables

### Current Security Tracking Tables:

1. **`failed_registrations`** ✅ **ACTIVE**
   - Tracks failed registration attempts (403 and other failures)
   - Used for brute force detection

2. **`door_knock_attempts`** ✅ **ACTIVE**
   - Tracks door-knock attempts (unknown domains, scanners, etc.)
   - Used for attack pattern analysis

3. **`location`** ✅ **ACTIVE** (OpenSIPS usrloc module)
   - Tracks successful registrations
   - Used for routing and endpoint lookup

4. **`registration_status`** ❌ **NOT CREATED**
   - Would have tracked status summary
   - Deferred due to low value

---

## Future Considerations

If registration status tracking becomes valuable later:

1. **Create SQL View** (recommended)
   - No maintenance overhead
   - Always accurate
   - Can be created/dropped as needed

2. **Add to Management Interface**
   - Show status in admin panel
   - Query existing tables directly
   - No need for separate table

3. **Re-evaluate Phase 1.2**
   - If specific use case emerges
   - If performance becomes an issue
   - If reporting requirements change

---

## Conclusion

**Phase 1.2 is deferred** because:
- ✅ Information already available in `location` and `failed_registrations` tables
- ✅ SQL view can provide summary if needed
- ✅ Reduces maintenance overhead
- ✅ Allows focus on higher-value security features

**Next Steps:**
- Proceed to Phase 2.2 (Brute Force Detection)
- Use existing tables for any status queries needed
- Create SQL view later if quick lookup becomes important

---

**Last Updated:** January 2026  
**Status:** Decision documented, Phase 1.2 deferred
