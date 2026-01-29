# SQL Fallback Testing Guide

**Date:** January 2026  
**Purpose:** Document when SQL fallback is triggered and how to test it

---

## When SQL Fallback is Triggered

The SQL fallback is used as a **race condition handler** when the standard `lookup("location")` function doesn't find a contact, even though the contact exists in the database.

### Trigger Conditions

SQL fallback is triggered in these scenarios:

#### 1. **lookup() Returns FALSE** (Contact Not Found in Cache)
- `lookup("location")` returns FALSE
- Contact exists in database but not in memory cache
- **Most common scenario** - happens when location was just saved to DB but cache hasn't updated yet

#### 2. **lookup() Returns TRUE But Contact Not Usable** (Race Condition)
- `lookup("location")` returns TRUE (contact found)
- BUT `$du` is null (no outbound proxy set)
- AND `$ru` was NOT updated by lookup() (still contains lookup URI, not contact)
- This indicates lookup() found something but couldn't extract usable contact info

---

## Test Scenarios

### Test Scenario 1: Registration Immediately Followed by Call (Race Condition)

**Objective:** Test the race condition where a contact is saved to DB but lookup() cache hasn't updated yet.

**Steps:**
1. **Register a phone** (e.g., extension 40004)
   ```bash
   # Phone registers - save() writes to database immediately
   # But usrloc cache may not have updated yet
   ```

2. **Immediately send OPTIONS or INVITE** (within 1-2 seconds of registration)
   ```bash
   # From Asterisk or another SIP client
   # Send OPTIONS or INVITE to the just-registered extension
   ```

3. **Expected Behavior:**
   - `lookup("location")` may return FALSE (cache miss)
   - SQL fallback should find the contact in database
   - Request should route successfully

**Log Messages to Look For:**
```
OPTIONS/NOTIFY: lookup() returned FALSE - no contact found for sip:40004@domain.com
OPTIONS/NOTIFY: Trying SQL fallback for domain-specific lookup (race condition handling)
OPTIONS/NOTIFY: SQL fallback query for user=40004, domain=domain.com
OPTIONS/NOTIFY: SQL fallback found contact: sip:... (race condition resolved)
```

---

### Test Scenario 2: Rapid Registration/Deregistration Cycle

**Objective:** Test race condition during rapid registration changes.

**Steps:**
1. **Register phone** (extension 40004)
2. **Immediately deregister** (unregister or expire)
3. **Immediately re-register** (within 1-2 seconds)
4. **Immediately send OPTIONS/INVITE** (within 1-2 seconds of re-registration)

**Expected Behavior:**
- Cache may be inconsistent during rapid changes
- SQL fallback should find the current state in database

**Log Messages to Look For:**
```
OPTIONS/NOTIFY: lookup() returned FALSE - no contact found
OPTIONS/NOTIFY: Trying SQL fallback for domain-specific lookup (race condition handling)
```

---

### Test Scenario 3: Cache Expiration/Refresh Timing

**Objective:** Test when usrloc cache expires or refreshes.

**Steps:**
1. **Register phone** (extension 40004)
2. **Wait for usrloc timer interval** (default: 10 seconds per `modparam("usrloc", "timer_interval", 10)`)
3. **During cache refresh**, send OPTIONS/INVITE
4. **Or:** Reduce timer interval temporarily to increase chance of cache refresh during request

**Expected Behavior:**
- If cache is refreshing when request arrives, lookup() may miss
- SQL fallback should find contact in database

**Configuration to Test:**
```opensips
# Temporarily reduce timer interval to increase cache refresh frequency
modparam("usrloc", "timer_interval", 2)  # Refresh every 2 seconds
```

---

### Test Scenario 4: Multiple OpenSIPS Instances (If Applicable)

**Objective:** Test race condition in multi-instance scenarios.

**Steps:**
1. **Instance A:** Phone registers (writes to shared database)
2. **Instance B:** Immediately receives OPTIONS/INVITE for that phone
3. **Instance B's cache** may not have the contact yet

**Expected Behavior:**
- Instance B's `lookup()` may return FALSE
- SQL fallback should find contact in shared database

**Note:** This scenario only applies if you have multiple OpenSIPS instances sharing the same database.

---

### Test Scenario 5: lookup() Returns TRUE But Contact Not Usable

**Objective:** Test the edge case where lookup() finds something but can't extract usable contact.

**Steps:**
1. **Create a location record** with malformed or unusual contact format
2. **Send OPTIONS/INVITE** to that extension
3. **Observe** if lookup() returns TRUE but `$du` is null and `$ru` unchanged

**Expected Behavior:**
- `lookup()` may return TRUE but contact not usable
- SQL fallback should extract contact directly from database

**Log Messages to Look For:**
```
OPTIONS/NOTIFY: lookup() returned TRUE - contact found
OPTIONS/NOTIFY: $du is null - checking if $ru was updated by lookup()
OPTIONS/NOTIFY: $ru was not updated by lookup() (still sip:user@domain) - will use SQL fallback
OPTIONS/NOTIFY: Trying SQL fallback for domain-specific lookup (race condition handling)
```

---

## How to Monitor SQL Fallback Usage

### 1. **Enable Detailed Logging**

Look for these log messages:
- `"Trying SQL fallback for domain-specific lookup (race condition handling)"`
- `"SQL fallback query for user=..., domain=..."`
- `"SQL fallback found contact: ... (race condition resolved)"`
- `"SQL fallback query returned no results"`
- `"SQL fallback query failed"`

### 2. **Check OpenSIPS Logs**

```bash
# Watch for SQL fallback messages
tail -f /var/log/opensips.log | grep "SQL fallback"

# Or watch for race condition messages
tail -f /var/log/opensips.log | grep "race condition"
```

### 3. **Monitor Database Queries**

If you have MySQL query logging enabled:
```sql
-- Check for location table queries
-- SQL fallback uses: SELECT COALESCE(received, contact) FROM location WHERE...
```

### 4. **Check usrloc Cache Status**

Use OpenSIPS MI (Management Interface) to check cache:
```bash
# Check registered contacts in cache
opensipsctl fifo ul_show

# Check if specific contact is in cache
opensipsctl fifo ul_show_contact <username> <domain>
```

---

## Expected Frequency

**SQL fallback should be rare** because:
- `lookup("location")` uses usrloc memory cache (very fast)
- Cache is updated frequently (default: every 10 seconds)
- Most requests happen after cache has been populated

**When it's more likely:**
- Immediately after registration (within 1-2 seconds)
- During rapid registration/deregistration cycles
- During usrloc cache refresh intervals
- In multi-instance deployments with shared database

---

## Testing Commands

### Test OPTIONS Fallback
```bash
# From Asterisk or SIP client, send OPTIONS to registered extension
# Immediately after registration completes
sip show peers  # Check if registered
sip show peer 40004  # Check registration details
# Then send OPTIONS
```

### Test INVITE Fallback
```bash
# From Asterisk, make a call immediately after registration
# Or use SIP client to send INVITE
# Timing is critical - must be within 1-2 seconds of registration
```

### Simulate Race Condition
```bash
# Register phone
# Immediately (within 1 second) send request
# Or reduce usrloc timer_interval to increase cache refresh frequency
```

---

## Verification

**Success Indicators:**
- SQL fallback finds contact in database
- Request routes successfully despite cache miss
- Log shows "race condition resolved" message

**Failure Indicators:**
- SQL fallback also returns no results (contact truly doesn't exist)
- SQL fallback query fails (database issue)
- Request fails to route (both lookup() and SQL fallback failed)

---

## Notes

- SQL fallback is a **safety mechanism** for race conditions
- It should be **rare** in normal operation
- If you see it frequently, investigate:
  - usrloc cache refresh timing
  - Database write/read timing
  - Multi-instance cache synchronization (if applicable)

---

**Last Updated:** January 2026  
**Status:** Testing guide complete
