# Domain Attributes Migration - Complete

**Date:** January 2026  
**Status:** ✅ **COMPLETE**  
**Decision:** Migrated forward lookup to standard OpenSIPS `attrs` approach, kept `setid` column for reverse lookup

---

## Executive Summary

Successfully migrated domain-to-dispatcher linking from custom SQL queries to standard OpenSIPS domain module `attrs` column approach for **forward lookup** (domain → setid). **Reverse lookup** (setid → domain) continues to use `setid` column for performance and simplicity.

---

## What Changed

### ✅ Forward Lookup (Domain → Setid) - **MIGRATED**

**Before:**
```opensips
# Custom SQL query
$var(query) = "SELECT setid FROM domain WHERE domain='" + $var(domain) + "'";
sql_query($var(query), "$avp(domain_setid)");
$var(setid) = $(avp(domain_setid)[0]);
```

**After:**
```opensips
# Standard OpenSIPS domain module approach
if (is_domain_local($var(domain), $var(attrs))) {
    # Extract setid from attributes string
    $var(setid_str) = $(var(attrs){param.value,setid});
    # Convert string to integer for ds_select_dst()
    $var(setid) = $(var(setid_str){s.int});
}
```

**Benefits:**
- ✅ Uses standard OpenSIPS domain module functions
- ✅ Leverages domain module caching (`db_mode=2`)
- ✅ No SQL query overhead for forward lookup
- ✅ Supports multiple attributes per domain
- ✅ Aligns with OpenSIPS best practices

### ✅ Reverse Lookup (Setid → Domain) - **KEPT AS-IS**

**Current Implementation:**
```opensips
# Query domain table by setid (unchanged)
$var(query) = "SELECT domain FROM domain WHERE setid='" + $var(setid) + "' LIMIT 1";
sql_query($var(query), "$avp(source_domain)");
```

**Decision:** Keep `setid` column and SQL query for reverse lookup

**Rationale:**
- ✅ Direct indexed lookup (fast, efficient)
- ✅ Simple and maintainable
- ✅ Different use case than forward lookup (not domain validation)
- ✅ Domain module doesn't provide "find domain by attribute value" function
- ✅ Reverse lookup is less frequent than forward lookup

---

## Database Schema

**Current State:**
```sql
domain table:
- id (int, PK)
- domain (char(64), UNIQUE)
- attrs (char(255), NULL) ✅ Used for forward lookup
- accept_subdomain (int)
- last_modified (datetime)
- setid (int, indexed) ✅ Used for reverse lookup
```

**Both columns maintained:**
- `attrs` column: `"setid=1"` - Used for forward lookup via domain module
- `setid` column: `1` - Used for reverse lookup via SQL query

---

## Use Cases

### Forward Lookup (Domain → Setid)
**When:** Every inbound request from endpoints  
**Frequency:** High (primary routing path)  
**Method:** `is_domain_local()` + `{param.value}` transformation  
**Column Used:** `attrs`

**Example:**
```
Request: INVITE sip:401@ael.vcloudpbx.com
→ Validate domain: ael.vcloudpbx.com
→ Extract setid from attrs: "setid=1"
→ Route to dispatcher set 1
```

### Reverse Lookup (Setid → Domain)
**When:** Requests from Asterisk with IP addresses instead of domain names  
**Frequency:** Low (only when Asterisk sends IPs)  
**Method:** SQL query on `setid` column  
**Column Used:** `setid`

**Scenarios:**
1. **OPTIONS/NOTIFY requests** - To header has IP address
2. **INVITE requests** - Request-URI has IP address  
3. **NAT handling** - In-dialog requests with IP addresses

**Example:**
```
Request: INVITE sip:401@192.168.1.100:5060 from Asterisk (10.0.1.10)
→ Find setid for source IP: 10.0.1.10 → Setid 1
→ Find domain for setid: Setid 1 → ael.vcloudpbx.com
→ Use domain-specific lookup: sip:401@ael.vcloudpbx.com
```

**Why Critical:**
- Multi-tenant deployments with shared extension numbers
- Ensures routing to correct customer's endpoint
- Prevents privacy/security violations
- Prevents billing errors

---

## Decision Rationale

### Why Keep `setid` Column?

1. **Performance**
   - Direct indexed lookup: `WHERE setid = '1'` (fast)
   - Pattern matching on `attrs`: `WHERE attrs LIKE 'setid=1%'` (slower, no index)

2. **Simplicity**
   - Simple SQL query vs complex pattern matching
   - Clear and maintainable code

3. **Use Case Difference**
   - Forward lookup: Domain validation + attribute retrieval (domain module function)
   - Reverse lookup: Find domain by numeric value (not domain validation)

4. **Frequency**
   - Forward lookup: High frequency (every request)
   - Reverse lookup: Low frequency (only when Asterisk sends IPs)
   - Optimize the common path, keep the rare path simple

5. **Domain Module Limitation**
   - Domain module doesn't provide "find domain by attribute value" function
   - SQL query is necessary either way
   - Direct lookup on `setid` is more efficient than pattern matching

### Why Migrate Forward Lookup?

1. **Standard Approach**
   - Uses official OpenSIPS domain module functions
   - Aligns with OpenSIPS best practices
   - Better maintainability

2. **Performance**
   - Domain module caching (`db_mode=2`)
   - Attributes cached in memory
   - No SQL query overhead

3. **Flexibility**
   - Can store multiple attributes: `"setid=1;feature=enabled;timeout=30"`
   - Easy to extend with additional attributes
   - Standard transformation syntax

---

## Implementation Details

### Configuration Changes

**Added:**
```opensips
modparam("domain", "attrs_col", "attrs")  # Explicit (default is "attrs")
```

### Code Changes

**File:** `config/opensips.cfg.template`
- Lines ~925-945: Forward lookup using `is_domain_local()` + `{param.value}` + `{s.int}`
- Lines ~1225: Reverse lookup unchanged (SQL query on `setid`)

### Script Changes

**File:** `scripts/add-domain.sh`
- Updated to populate both `setid` and `attrs` columns
- Format: `attrs = "setid=10"`

**File:** `scripts/init-database.sh`
- Updated to populate `attrs` when creating `setid` column

### Database Migration

**Single row update:**
```sql
UPDATE domain SET attrs = CONCAT('setid=', setid) WHERE attrs IS NULL OR attrs = '';
```

---

## Testing Results

✅ **Configuration syntax:** Valid  
✅ **Domain validation:** Working  
✅ **Setid extraction:** Working (`setid=1` extracted from `attrs`)  
✅ **Routing:** Calls routing correctly to dispatcher  
✅ **Reverse lookup:** Still working (unchanged)

---

## Trade-offs

### What We Gained
- ✅ Standard OpenSIPS approach for forward lookup
- ✅ Domain module caching for forward lookup
- ✅ Flexibility for multiple attributes
- ✅ Better code quality

### What We Kept
- ✅ `setid` column (for reverse lookup)
- ✅ SQL query for reverse lookup
- ✅ Both columns maintained

### Why This Is Acceptable
- Forward lookup (high frequency) uses standard approach + caching
- Reverse lookup (low frequency) uses simple, efficient SQL query
- Both columns serve different purposes
- Overall net positive: optimize common path, keep rare path simple

---

## Future Considerations

### Option 1: Keep Current Approach (Recommended)
- Maintain both `setid` and `attrs` columns
- Forward lookup: Standard approach + caching
- Reverse lookup: Simple SQL query
- **Status:** ✅ Current approach

### Option 2: Eliminate `setid` Column
- Use `attrs` pattern matching for reverse lookup
- More complex SQL: `WHERE attrs LIKE 'setid=1%'`
- Less efficient (no index on pattern)
- **Status:** ⏸️ Not recommended

### Option 3: Enhance Domain Module (Future)
- Request OpenSIPS enhancement for "find domain by attribute value"
- Would enable standard approach for reverse lookup
- **Status:** 🔮 Future consideration

---

## Related Documentation

- `docs/DOMAIN-ATTRS-MIGRATION-PLAN.md` - Original migration plan
- `docs/DOMAIN-MODULE-RESEARCH.md` - Domain module research
- `docs/DISPATCHER-REVERSE-LOOKUP-RESEARCH.md` - Reverse lookup research
- `docs/MULTIPLE-DOMAINS-SAME-USERNAME.md` - Multi-tenant requirements
- OpenSIPS Domain Module: https://opensips.org/docs/modules/3.6.x/domain.html

---

## Conclusion

**Decision:** ✅ **COMPLETE**

Successfully migrated forward lookup to standard OpenSIPS `attrs` approach while keeping `setid` column for efficient reverse lookup. This optimizes the common path (forward lookup) while maintaining simplicity for the less frequent path (reverse lookup).

**Status:** Production ready

---

**Last Updated:** January 2026  
**Decision Date:** January 2026  
**Status:** ✅ Migration complete, decision documented
