# Endpoint Location Record Creation

## Overview

This document explains when `endpoint_locations` records are created, the current behavior, implications, and future security considerations.

## Current Behavior

### When Records Are Created

Endpoint location records are created **immediately** when a REGISTER request passes through OpenSIPS, **before** the request is forwarded to Asterisk.

**Location in code:** `config/opensips.cfg.template` lines 284-306

```opensips
# ---- Handle REGISTER to track endpoint locations ----
if (is_method("REGISTER")) {
    if ($hdr(Contact) != "") {
        # Extract endpoint information
        $var(endpoint_aor) = $tU + "@" + $(tu{uri.domain});
        $var(endpoint_ip) = $si;
        $var(endpoint_port) = $sp;
        
        # ... calculate expiration ...
        
        # INSERT happens HERE - immediately, before forwarding
        $var(query) = "INSERT INTO endpoint_locations ...";
        sql_query($var(query), "$avp(reg_result)");
    }
}

route(DOMAIN_CHECK);  # Then validate domain and forward to Asterisk
```

### Request Flow

```
1. REGISTER request arrives at OpenSIPS
   ↓
2. Extract endpoint info (AoR, IP, port, expires)
   ↓
3. INSERT into endpoint_locations table ← RECORD CREATED HERE
   ↓
4. Validate domain (DOMAIN_CHECK)
   ↓
5. Forward to Asterisk via dispatcher
   ↓
6. Asterisk processes registration
   ↓
7. Response returned (200 OK, 401 Unauthorized, etc.)
```

**Key Point:** The record exists in the database **before** we know if Asterisk will accept or reject the registration.

## Implications

### 1. Failed Registrations Still Create Records

**Scenario:** Endpoint sends REGISTER, Asterisk rejects with 401 Unauthorized

**Current Behavior:**
- ✅ Endpoint location record is created
- ✅ Record has expiration timestamp
- ❌ Record is NOT deleted on failure
- ✅ Record expires naturally based on `expires` column

**Example:**
```sql
-- Failed registration at 10:00:00
-- Record created with expires = 10:00:00 + 3600 seconds = 11:00:00
-- Asterisk rejects at 10:00:01 with 401 Unauthorized
-- Record remains in database until 11:00:00
-- Cleanup script removes it after expiration
```

### 2. De-Registrations (Expires: 0)

**Scenario:** Endpoint sends REGISTER with `Expires: 0` to de-register

**Current Behavior:**
- ✅ Record is updated (ON DUPLICATE KEY UPDATE)
- ✅ Expiration set to NOW() + 0 seconds = immediate expiration
- ✅ Record filtered out immediately in queries (`expires > NOW()`)
- ✅ Cleanup script removes it quickly

**This works correctly** - de-registrations are handled properly.

### 3. No Response-Based Cleanup

**Current State:**
- `onreply_route` (line 915) does not check for REGISTER failures
- `failure_route[1]` (line 988) does not clean up endpoint_location records
- Failed registrations rely on natural expiration

### 4. Query Filtering

**Protection:** All queries include `expires > NOW()` filter:

```sql
SELECT contact_ip FROM endpoint_locations 
WHERE aor='...' AND expires > NOW();
```

**Result:** Expired entries (including failed registrations) are automatically filtered out of lookups, even if they haven't been deleted yet.

## Why This Is Acceptable (Current State)

### 1. Natural Expiration

- Failed registrations typically have short expiration times
- Records expire based on SIP Expires header
- Cleanup script removes expired entries daily

### 2. Query Filtering

- All lookups filter by `expires > NOW()`
- Expired entries don't affect routing decisions
- Database size impact is minimal

### 3. Most Registrations Succeed

- In normal operation, most REGISTER requests succeed
- Failed registrations are the exception, not the rule
- Impact is limited

### 4. Cleanup Script

- Daily cleanup removes expired entries
- Prevents database bloat
- Maintains performance

## Potential Issues

### 1. Failed Registration Records Persist

**Issue:** Failed registration records remain in database until expiration

**Impact:**
- Minor database bloat
- Could confuse monitoring/debugging
- Not a security issue (expired entries filtered out)

**Mitigation:**
- Cleanup script runs daily
- Queries filter expired entries
- Acceptable for current use case

### 2. No Immediate Cleanup on Failure

**Issue:** No response-based cleanup for failed registrations

**Impact:**
- Failed registrations remain until expiration
- Could accumulate if many failures occur

**Mitigation:**
- Natural expiration handles this
- Cleanup script provides backup
- Acceptable for current use case

### 3. Threat Detection Gap

**Issue:** No differentiation between successful and failed registrations

**Impact:**
- Cannot detect registration attacks (brute force, enumeration)
- Cannot track failed registration attempts
- No visibility into registration failures

**Future Consideration:** See "Future Security Enhancements" below

## Future Security Enhancements

When implementing threat detection and handling, consider the following improvements:

### 1. Response-Based Cleanup

**Enhancement:** Delete endpoint_location records on registration failure

```opensips
onreply_route {
    if (is_method("REGISTER")) {
        if ($rs >= 400) {
            # Registration failed - delete endpoint_location record
            $var(endpoint_aor) = $tU + "@" + $(tu{uri.domain});
            sql_query("DELETE FROM endpoint_locations WHERE aor='$var(endpoint_aor)'");
            xlog("L_NOTICE", "Registration failed ($rs), deleted endpoint_location for $var(endpoint_aor)\n");
        }
    }
}
```

**Benefits:**
- Immediate cleanup of failed registrations
- Cleaner database
- Better for monitoring

**Considerations:**
- Only delete on final failure responses (4xx, 5xx)
- Don't delete on provisional responses (1xx)
- Handle de-registration (Expires: 0) separately

### 2. Registration Status Tracking

**Enhancement:** Add status column to track registration state

```sql
ALTER TABLE endpoint_locations ADD COLUMN status VARCHAR(20) DEFAULT 'pending';
-- Values: 'pending', 'registered', 'failed', 'expired'
```

**Update on response:**
```opensips
onreply_route {
    if (is_method("REGISTER")) {
        if ($rs == 200) {
            sql_query("UPDATE endpoint_locations SET status='registered' WHERE aor='...'");
        } else if ($rs >= 400) {
            sql_query("UPDATE endpoint_locations SET status='failed' WHERE aor='...'");
        }
    }
}
```

**Benefits:**
- Track registration success/failure
- Enable threat detection
- Better monitoring and debugging

### 3. Failed Registration Tracking

**Enhancement:** Create separate table for failed registration attempts

```sql
CREATE TABLE failed_registrations (
    id INT AUTO_INCREMENT PRIMARY KEY,
    aor VARCHAR(255) NOT NULL,
    source_ip VARCHAR(45) NOT NULL,
    source_port VARCHAR(10) NOT NULL,
    response_code INT NOT NULL,
    response_reason VARCHAR(255),
    attempt_time DATETIME NOT NULL,
    INDEX idx_aor_time (aor, attempt_time),
    INDEX idx_source_ip_time (source_ip, attempt_time)
);
```

**Benefits:**
- Track failed registration attempts
- Detect brute force attacks
- Identify suspicious patterns
- Enable rate limiting

### 4. Rate Limiting

**Enhancement:** Implement rate limiting for REGISTER requests

```opensips
# Track registration attempts per IP
# Block IPs with too many failed attempts
# Use ipban module or custom logic
```

**Benefits:**
- Prevent brute force attacks
- Reduce database bloat from failed attempts
- Improve security

### 5. Registration Validation

**Enhancement:** Validate registration before creating record

**Options:**
- Pre-validate with Asterisk (OPTIONS check)
- Validate domain exists before creating record
- Validate user exists before creating record

**Trade-offs:**
- Adds latency to registration
- Requires additional logic
- May not be necessary if Asterisk handles validation

## Recommendations

### Short Term (Current State)

✅ **Keep current behavior** - It works correctly for normal operations

✅ **Monitor database size** - Ensure cleanup script is working

✅ **Review logs** - Watch for unusual registration patterns

### Medium Term (When Adding Monitoring)

1. **Add response-based cleanup** for failed registrations
2. **Add status tracking** to endpoint_locations table
3. **Implement logging** for registration failures

### Long Term (Threat Detection)

1. **Create failed_registrations table** for tracking
2. **Implement rate limiting** for REGISTER requests
3. **Add threat detection logic** for suspicious patterns
4. **Consider registration validation** before record creation

## Testing

### Verify Current Behavior

```sql
-- Check for expired entries (should be minimal)
SELECT COUNT(*) FROM endpoint_locations WHERE expires < NOW();

-- Check for active registrations
SELECT COUNT(*) FROM endpoint_locations WHERE expires > NOW();

-- Check registration patterns
SELECT aor, contact_ip, expires, 
       TIMESTAMPDIFF(SECOND, NOW(), expires) as seconds_until_expiry
FROM endpoint_locations
ORDER BY expires DESC
LIMIT 10;
```

### Monitor Registration Failures

```bash
# Check OpenSIPS logs for registration failures
sudo journalctl -u opensips -f | grep -i "register.*40[0-9]"

# Check for failed registrations in database (if tracking added)
mysql -u opensips -p opensips -e "SELECT * FROM failed_registrations ORDER BY attempt_time DESC LIMIT 10;"
```

## Related Documentation

- [Endpoint Cleanup Documentation](ENDPOINT-CLEANUP.md)
- [OpenSIPS Routing Logic](opensips-routing-logic.md)
- [Database Schema](../scripts/init-database.sh)

## Summary

**Current State:**
- ✅ Endpoint location records created immediately on REGISTER
- ✅ Records persist even if registration fails
- ✅ Natural expiration handles cleanup
- ✅ Query filtering prevents expired entries from affecting routing
- ✅ Acceptable for current use case

**Future Considerations:**
- ⚠️ Add response-based cleanup for failed registrations
- ⚠️ Implement registration status tracking
- ⚠️ Add failed registration tracking for threat detection
- ⚠️ Consider rate limiting for REGISTER requests
- ⚠️ Evaluate registration validation before record creation

The current implementation is **acceptable for normal operations** but will need **enhancements for threat detection and security hardening** in the future.
