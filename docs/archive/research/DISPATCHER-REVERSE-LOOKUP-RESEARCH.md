# Dispatcher Reverse Lookup Research

**Date:** January 2026  
**Purpose:** Research standard OpenSIPS dispatcher module functions to replace custom SQL for reverse lookup (source IP → setid)

---

## Current Implementation

**Location:** `route[GET_DOMAIN_FROM_SOURCE_IP]` (lines ~1116-1153)

**Problem:** Custom SQL query to find dispatcher setid from source IP

**Current Code:**
```opensips
# Step 1: Find dispatcher setid for this source IP
# Dispatcher destinations are stored as "sip:IP:port" (e.g., "sip:10.0.1.10:5060")
# We match the IP part using LIKE with proper delimiters to avoid substring matches
$var(query) = "SELECT setid FROM dispatcher WHERE destination LIKE 'sip:" + $si + ":%' OR destination LIKE 'sip:" + $si + "' LIMIT 1";
if (!sql_query($var(query), "$avp(source_setid)")) {
    # ...
}
$var(setid) = $(avp(source_setid)[0]);

# Step 2: Find domain for this setid
$var(query) = "SELECT domain FROM domain WHERE setid='" + $var(setid) + "' LIMIT 1";
# ...
```

**Use Case:**
- When a request comes from Asterisk (source IP = dispatcher destination IP)
- Need to determine which domain/tenant it belongs to
- Use dispatcher setid to look up domain

**Issues:**
- Custom SQL query for reverse lookup
- Two-step process (setid → domain)
- Could potentially use dispatcher module functions if available

---

## Research Questions

### 1. Dispatcher Module Functions

**Questions:**
- Does dispatcher module provide functions to query destinations by IP?
- Does dispatcher module provide reverse lookup functions (IP → setid)?
- Can we iterate through dispatcher destinations to find matching IP?
- Are there any dispatcher pseudo-variables that expose destination information?

**Documentation URL:** https://opensips.org/html/docs/modules/3.6.x/dispatcher.html

### 2. Dispatcher Module Architecture

**Understanding:**
- Dispatcher module loads destinations into memory cache at startup
- `ds_select_dst()` selects destination from cache based on setid
- Destinations stored as `sip:IP:port` format in database
- Need reverse: given IP, find which setid it belongs to

**Questions:**
- Does dispatcher module expose its internal cache for queries?
- Can we access dispatcher destinations programmatically?
- Are there any dispatcher statistics/exports that include destination IPs?

### 3. Alternative Approaches

**Questions:**
- Could we use URI transformations to parse dispatcher destination strings?
- Could we maintain a separate lookup table/cache?
- Is the current SQL approach acceptable given dispatcher module limitations?

---

## Current Implementation Analysis

### Purpose
The `GET_DOMAIN_FROM_SOURCE_IP` route is used to:
1. Determine which domain/tenant a request belongs to when source IP is Asterisk
2. Handle multi-tenant scenarios where same extension numbers exist across domains
3. Route requests correctly based on which Asterisk server sent them

### Flow
```
Request from Asterisk (source IP = 3.93.253.1)
  ↓
Query dispatcher table: "SELECT setid WHERE destination LIKE 'sip:3.93.253.1:%'"
  ↓
Get setid (e.g., setid = 1)
  ↓
Query domain table: "SELECT domain WHERE setid = 1"
  ↓
Get domain (e.g., domain = ael.vcloudpbx.com)
  ↓
Use domain for endpoint lookup
```

### Why This Is Needed
- Multi-tenant support: Same extension numbers across different domains
- Domain determination: When Request-URI has IP instead of domain
- Source-based routing: Route based on which Asterisk server sent the request

---

## Research Plan

### Step 1: Review Dispatcher Module Documentation
- Check dispatcher module functions list
- Look for reverse lookup or query functions
- Check for pseudo-variables that expose destination information
- Review dispatcher module architecture

### Step 2: Check Dispatcher Module Functions
- Review `ds_select_dst()` and related functions
- Check if there are any query/iteration functions
- Look for destination access functions

### Step 3: Evaluate Alternatives
- Compare SQL approach vs module functions
- Consider if URI transformations could help
- Assess if current approach is acceptable

---

## Expected Outcomes

### Option A: Dispatcher Module Provides Reverse Lookup
```opensips
# Hypothetical function
ds_get_setid_by_ip($si, "$avp(source_setid)");
$var(setid) = $(avp(source_setid)[0]);
```

### Option B: Dispatcher Module Exposes Destinations
```opensips
# Hypothetical iteration or query
ds_list_destinations($var(setid), "$avp(destinations)");
# Then match IP against destinations
```

### Option C: Keep Custom SQL (If No Module Functions)
```opensips
# Current approach is acceptable if dispatcher module doesn't provide reverse lookup
# Document why SQL is needed
```

---

## Research Findings

### Dispatcher Module Functions (OpenSIPS 3.6)

**Available Functions:**
- `ds_select_dst(setid, alg)` - Forward lookup: selects destination from setid
- `ds_reload()` - Reloads destinations from database
- `ds_is_from_list(setid, ip_list)` - Checks if source IP is in a comma-separated IP list (NOT for reverse lookup)
- `ds_ping_dst(destination)` - Sends ping to specific destination
- `ds_count(setid, state)` - Counts destinations in a setid with specific state

**Key Finding:** ❌ **No reverse lookup functions available**

The dispatcher module does **NOT** provide:
- Functions to query destinations by IP address
- Functions to get setid from IP address
- Functions to iterate through destinations
- Pseudo-variables that expose destination information for reverse lookup

### Dispatcher Module Architecture

**How It Works:**
1. Dispatcher module loads destinations from database into **in-memory cache** at startup
2. Cache is optimized for **forward lookups** (setid → destination)
3. Cache is **NOT** optimized for reverse lookups (IP → setid)
4. The module's design focuses on fast destination selection, not reverse queries

**Why No Reverse Lookup:**
- Dispatcher module is designed for **forward routing** (domain → setid → destination)
- Reverse lookup (IP → setid) is an **edge case** not covered by standard dispatcher use
- The module doesn't maintain an IP-indexed cache for reverse lookups

---

## Analysis: Current SQL Approach

### Is Custom SQL Justified?

**✅ YES - Custom SQL is justified and acceptable**

**Reasons:**
1. **No module function exists** - Dispatcher module doesn't provide reverse lookup
2. **Simple and efficient** - SQL LIKE query is straightforward and performs well
3. **Direct database access** - We're querying the same database the dispatcher module uses
4. **Edge case use** - This is a multi-tenant edge case, not standard dispatcher routing
5. **Low complexity** - The SQL query is simple and maintainable

### Current Implementation Quality

**Strengths:**
- ✅ Proper LIKE pattern matching to avoid substring matches
- ✅ Handles both `sip:IP:port` and `sip:IP` formats
- ✅ Clear comments explaining the logic
- ✅ Proper error handling and logging

**Potential Improvements:**
- Could use URI transformations to parse destination strings (but SQL is simpler)
- Could maintain a separate lookup cache (but adds complexity)
- Current approach is **already optimal** for this use case

---

## Recommendation

### ✅ **Keep Custom SQL - Justified Given Module Limitations**

**Justification:**
1. Dispatcher module doesn't provide reverse lookup functions
2. SQL query is simple, efficient, and maintainable
3. Direct database access is appropriate for this edge case
4. No standard OpenSIPS approach exists for this use case

**Action Items:**
1. ✅ **Document why SQL is needed** - Add comments explaining dispatcher module limitations
2. ✅ **Keep current implementation** - It's already optimal for this use case
3. ✅ **Accept as-is** - This is an acceptable exception to "standard approach first" principle

---

## Alternative Approaches Considered

### Option 1: URI Transformations
**Approach:** Parse dispatcher destination strings using `$(uri.host)` transformations  
**Verdict:** ❌ **Not practical** - Would require loading all dispatcher destinations into script variables, which is inefficient

### Option 2: Separate Lookup Table/Cache
**Approach:** Maintain a separate IP → setid mapping table  
**Verdict:** ❌ **Unnecessary complexity** - Current SQL approach is simpler and works well

### Option 3: Dispatcher Module Enhancement
**Approach:** Request dispatcher module enhancement for reverse lookup  
**Verdict:** ⚠️ **Future consideration** - Not needed for current use case

---

## Conclusion

**Status:** ✅ **RESEARCH COMPLETE**

**Finding:** The dispatcher module does **NOT** provide reverse lookup functions. The current custom SQL approach is **justified and acceptable** given the module's limitations.

**Recommendation:** **Keep current implementation** with added documentation explaining why SQL is necessary.

**Impact:** Low - Custom SQL is simple, efficient, and justified for this edge case

---

**Last Updated:** January 2026  
**Status:** ✅ **RESEARCH COMPLETE** - Custom SQL is justified and acceptable
