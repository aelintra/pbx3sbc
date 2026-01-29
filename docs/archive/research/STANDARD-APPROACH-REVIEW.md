# Standard OpenSIPS Approach Review

**Date:** January 2026  
**Purpose:** Review existing implementation against "standard approach first" principle

---

## Executive Summary

**Overall Grade: B+ (Good, with room for improvement)**

The implementation **mostly follows** standard OpenSIPS approaches, but there are several areas where custom SQL queries are used instead of standard module functions. Most custom queries appear to be fallbacks or workarounds for edge cases, which is acceptable, but some could potentially be replaced with standard module functions.

---

## ✅ What We're Doing Well

### 1. **Using Standard Modules Throughout**
- ✅ All loaded modules are standard OpenSIPS modules
- ✅ Using `lookup("location")` and `save("location")` from registrar/usrloc modules (primary approach)
- ✅ Using `ds_select_dst()` from dispatcher module for load balancing
- ✅ Using `nathelper` module for NAT traversal
- ✅ Using `dialog` and `acc` modules for CDR/accounting
- ✅ Using `domain` module for domain management

### 2. **Proper Module Configuration**
- ✅ All modules properly configured with `modparam()`
- ✅ Using standard module parameters (received_avp, mcontact_avp, etc.)
- ✅ Following OpenSIPS best practices for module setup

### 3. **Standard Functions Where Appropriate**
- ✅ Using `lookup("location")` as primary method for endpoint lookups
- ✅ Using `save("location")` for registration persistence
- ✅ Using `force_rport()` for NAT traversal (standard core function)
- ✅ Using `fix_nated_register()` from nathelper module

---

## ⚠️ Areas for Improvement

### 1. **Domain Lookups - Custom SQL Instead of Domain Module Functions**

**Current Implementation:**
```opensips
# Line ~938: Custom SQL query for domain lookup
$var(query) = "SELECT setid FROM domain WHERE domain='" + $var(domain) + "'";
if (!sql_query($var(query), "$avp(domain_setid)")) {
    # ...
}
```

**Standard Approach Available:**
- Domain module provides `is_domain()` function
- Domain module can be queried via `domain_db_load()` or similar
- Check if `domain` module has functions to get setid directly

**Research Completed:** ✅ See `docs/DOMAIN-MODULE-RESEARCH.md`

**Findings:**
- Domain module only provides `is_domain()` for validation (returns TRUE/FALSE)
- Domain module does NOT provide functions to retrieve domain attributes (setid)
- OpenSIPS no longer favors the `setid` approach for domain-destination linking
- However, for our user base, the simpler `setid` approach is justified

**Recommendation:**
- ✅ **Keep custom SQL** - Justified given domain module limitations and our requirements
- ✅ **Add code comments** - Document why custom SQL is needed
- ✅ **Acceptable approach** - Simpler setid approach is appropriate for our user base

**Impact:** Low - Custom SQL is justified and acceptable for our use case

---

### 2. **Location Lookups - SQL Fallback (Acceptable)**

**Current Implementation:**
```opensips
# Line ~410: Primary uses standard lookup()
if (lookup("location")) {
    # Standard approach - GOOD!
}

# Line ~474: SQL fallback for race conditions
$var(query) = "SELECT COALESCE(received, contact) FROM location WHERE username='...'";
if (sql_query($var(query), "$avp(fallback_contact)")) {
    # Custom SQL fallback
}
```

**Analysis:**
- ✅ Primary approach uses standard `lookup("location")` function
- ⚠️ SQL fallback is used for race condition handling
- This is **acceptable** as a fallback/workaround

**Recommendation:**
- ✅ **Keep as-is** - SQL fallback is justified for race condition handling
- Consider documenting why SQL fallback is needed (race conditions)

**Impact:** Low - Fallback is acceptable, primary uses standard approach

---

### 3. **NAT Traversal - Custom Regex/SQL for IP Extraction**

**Current Implementation:**
```opensips
# Lines ~1407-1439: Custom regex/SQL to extract IP:port from received field
# Multiple sql_query() calls to parse SIP URIs
if (sql_query($var(query_remove_prefix), "$avp(nat_no_prefix)")) {
    if (sql_query($var(query_ip), "$avp(nat_ip_extracted)")) {
        # Extract IP
    }
    if (sql_query($var(query_port_part), "$avp(nat_port_part)")) {
        if (sql_query($var(query_port), "$avp(nat_port_extracted)")) {
            # Extract port
        }
    }
}
```

**Standard Approach Available:**
- `nathelper` module provides `fix_nated_contact()` and `fix_nated_sdp()`
- `sipmsgops` module may have URI parsing functions
- Check if there are standard functions to extract IP:port from SIP URIs

**Recommendation:**
- 🔍 **Research:** Check `sipmsgops` module for URI parsing functions
- Check if `nathelper` module has functions to extract IP:port
- If available, replace custom regex/SQL with standard functions
- If not available, consider creating a helper route (still better than inline SQL)

**Impact:** Medium - Custom regex/SQL is complex and error-prone

---

### 4. **Dispatcher Lookups - Custom SQL for Source IP Matching**

**Current Implementation:**
```opensips
# Line ~1125: Custom SQL to find dispatcher setid from source IP
$var(query) = "SELECT setid FROM dispatcher WHERE destination LIKE 'sip:" + $si + ":%' OR destination LIKE 'sip:" + $si + "' LIMIT 1";
if (!sql_query($var(query), "$avp(source_setid)")) {
    # ...
}
```

**Standard Approach Available:**
- Dispatcher module provides `ds_select_dst()` for forward lookup (setid → destination)
- Dispatcher module does NOT provide reverse lookup functions (IP → setid)

**Research Completed:** ✅ See `docs/DISPATCHER-REVERSE-LOOKUP-RESEARCH.md`

**Findings:**
- Dispatcher module has no reverse lookup functions
- Module is designed for forward routing, not reverse queries
- Custom SQL is necessary for multi-tenant edge case (determining domain from Asterisk source IP)

**Recommendation:**
- ✅ **Keep custom SQL** - Justified given dispatcher module limitations
- ✅ **Add code comments** - Document why SQL is needed
- ✅ **Acceptable approach** - Simple, efficient, and appropriate for this use case

**Impact:** Low - Custom SQL is simple, efficient, and justified

---

### 5. **Scanner Detection - Custom Pattern Matching (Acceptable)**

**Current Implementation:**
```opensips
# Line ~263: Custom User-Agent pattern matching
if ($ua =~ "sipvicious|friendly-scanner|sipcli|nmap") {
    exit;
}
```

**Analysis:**
- This is a simple, effective approach
- No standard module exists for this specific use case
- Could potentially use `permissions` module with database-backed rules, but pattern matching is simpler

**Recommendation:**
- ✅ **Keep as-is** - Simple and effective
- Consider enhancing with `pike` module (planned in Phase 2.3) for automatic blocking

**Impact:** None - This is appropriate

---

## 📊 Summary by Category

### ✅ Excellent (Using Standard Approaches)
- Location lookups (primary): `lookup("location")` ✅
- Registration persistence: `save("location")` ✅
- Load balancing: `ds_select_dst()` ✅
- NAT traversal: `fix_nated_register()`, `force_rport()` ✅
- CDR/Accounting: `dialog` and `acc` modules ✅

### ⚠️ Good (Standard with Custom Fallbacks)
- Location lookups (fallback): SQL fallback for race conditions ✅ (justified)
- Scanner detection: Custom pattern matching ✅ (no standard module exists)

### 🔍 Needs Research (Could Use Standard Functions)
- ~~Domain lookups: Custom SQL~~ ✅ **RESOLVED** - Keep custom SQL (justified)
- ~~NAT IP extraction: Custom regex/SQL~~ ✅ **RESOLVED** - Refactored to standard transformations
- ~~Dispatcher reverse lookup: Custom SQL~~ ✅ **RESOLVED** - Keep custom SQL (justified)

---

## Recommendations

### Priority 1: Research Standard Functions
1. **Domain Module:** Check if `is_domain()` or other functions can return setid
2. **SIPmsgops Module:** Check for URI parsing functions (extract IP:port)
3. **Dispatcher Module:** Check for reverse lookup functions

### Priority 2: Document Custom Implementations
- Add comments explaining why custom SQL is used (if standard functions don't exist)
- Document race condition handling rationale for SQL fallbacks

### Priority 3: Consider Refactoring (If Standard Functions Found)
- Replace custom domain SQL with standard function
- Replace custom NAT IP extraction with standard function
- Replace custom dispatcher SQL with standard function

---

## Conclusion

**Overall Assessment:** The implementation follows standard OpenSIPS approaches for **core functionality** (location lookups, registration, load balancing). Custom SQL queries are primarily used for:
1. **Edge cases** (race condition fallbacks)
2. **Data extraction** (IP:port parsing)
3. **Reverse lookups** (source IP → dispatcher setid)

Most custom implementations appear justified, but **research is needed** to confirm whether standard module functions could replace them. The codebase is in good shape and follows the "standard approach first" principle for the majority of functionality.

**Next Steps:**
1. Research domain, sipmsgops, and dispatcher module documentation
2. Document findings in this review
3. Refactor if standard functions are available
4. Document why custom implementations are needed if standard functions don't exist

---

**Last Updated:** January 2026  
**Status:** Review complete, recommendations provided
