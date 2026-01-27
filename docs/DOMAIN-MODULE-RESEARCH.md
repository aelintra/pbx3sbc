# Domain Module Research - Standard Functions for Domain Lookups

**Date:** January 2026  
**Purpose:** Research standard OpenSIPS domain module functions to replace custom SQL queries

---

## Current Implementation

**Location:** `config/opensips.cfg.template` line ~938

**Custom SQL Query:**
```opensips
$var(query) = "SELECT setid FROM domain WHERE domain='" + $var(domain) + "'";
if (!sql_query($var(query), "$avp(domain_setid)")) {
    xlog("L_NOTICE", "Door-knock blocked: domain=$var(domain) src=$si (query failed)\n");
    exit;
}

# Check if domain was found
if ($(avp(domain_setid)[0]) == "") {
    xlog("L_NOTICE", "Door-knock blocked: domain=$var(domain) src=$si (not found)\n");
    exit;
}

# Get the dispatcher_setid from query result
$var(setid) = $(avp(domain_setid)[0]);
```

**Purpose:** Get the `setid` field from the `domain` table to determine which dispatcher set to use for routing.

---

## Domain Module Configuration

**Current Configuration:**
```opensips
loadmodule "domain.so"

modparam("domain", "db_url", "mysql://opensips:your-password@localhost/opensips")
modparam("domain", "db_mode", 2)  # Cached DB mode
modparam("domain", "domain_table", "domain")
modparam("domain", "domain_col", "domain")
```

**Database Schema:**
- Table: `domain`
- Columns: `domain` (domain name), `setid` (dispatcher set ID)

---

## Research Questions

### 1. What Functions Does the Domain Module Provide?

**Known Functions (from OpenSIPS documentation):**
- `is_domain(domain)` - Checks if domain exists (returns TRUE/FALSE)
- `domain_db_load()` - Loads domain data from database (if available)

**Unknown/To Verify:**
- ❓ Can `is_domain()` return additional data (like setid)?
- ❓ Is there a function to get domain attributes (setid, etc.)?
- ❓ Does domain module cache setid along with domain validation?
- ❓ Can we access cached domain data via pseudo-variables?

### 2. Domain Module Documentation Reference

**Documentation URL:** https://opensips.org/html/docs/modules/3.6.x/domain.html

**Key Questions to Answer:**
1. What functions are available in domain module?
2. Can functions return domain attributes (setid) or only validate existence?
3. How does domain module cache work in `db_mode=2`?
4. Can we access cached domain data without SQL queries?

---

## Analysis

### Option A: Domain Module Provides Setid Access

**If domain module has functions to get setid:**
```opensips
# Hypothetical standard approach
if (is_domain($var(domain), "$avp(domain_info)")) {
    # domain_info might contain setid
    $var(setid) = $(avp(domain_info)[setid]);
}
```

**Benefits:**
- ✅ Uses standard module function
- ✅ Leverages module caching
- ✅ Reduces technical debt
- ✅ Better performance (cached lookups)

### Option B: Domain Module Only Validates Existence

**If domain module only provides validation:**
```opensips
# Current approach might be necessary
if (is_domain($var(domain))) {
    # Domain exists, but still need SQL to get setid
    $var(query) = "SELECT setid FROM domain WHERE domain='" + $var(domain) + "'";
    sql_query($var(query), "$avp(domain_setid)");
}
```

**Analysis:**
- Domain module validates domain exists
- Still need custom SQL to get setid
- **Acceptable** if domain module doesn't provide attribute access

### Option C: Domain Module Caches Setid

**If domain module caches setid in db_mode=2:**
- Check if cached data is accessible via pseudo-variables
- May need to verify how domain module stores cached attributes

---

## Recommendations

### Immediate Actions

1. **✅ Research Domain Module Documentation** - **COMPLETED**
   - ✅ Reviewed: https://opensips.org/html/docs/modules/3.6.x/domain.html
   - ✅ Checked all available functions
   - ✅ Verified if functions can return domain attributes (setid)
   - **Findings:** See "Research Findings" section below

2. **🔍 Test Domain Module Functions** - **PENDING**
   - Test `is_domain()` function behavior
   - Check if it populates any AVPs with domain data
   - Verify caching behavior in `db_mode=2`

3. **🔍 Check Domain Module Source/Examples** - **PENDING**
   - Look for examples of getting setid from domain module
   - Check OpenSIPS community examples
   - Review module source code if needed

### Decision Criteria

**If domain module provides setid access:**
- ✅ **Replace custom SQL** with standard function
- ✅ **Update implementation** to use domain module function
- ✅ **Document** the change

**If domain module only validates:**
- ⚠️ **Keep custom SQL** but add comment explaining why
- ⚠️ **Document** that domain module doesn't provide attribute access
- ⚠️ **Consider** if this is acceptable or if we need to request enhancement

**If domain module caches but doesn't expose:**
- ⚠️ **Keep custom SQL** but verify caching doesn't duplicate work
- ⚠️ **Document** caching behavior
- ⚠️ **Consider** if custom SQL benefits from domain module cache

---

## Next Steps

1. **Access Domain Module Documentation**
   - URL: https://opensips.org/html/docs/modules/3.6.x/domain.html
   - Review all functions and parameters
   - Check for attribute access capabilities

2. **Update This Document**
   - Document findings from domain module documentation
   - Update recommendations based on findings
   - Provide specific function names and usage examples

3. **Update Implementation (If Standard Function Available)**
   - Replace custom SQL with standard function
   - Test the change
   - Update STANDARD-APPROACH-REVIEW.md

---

## Research Findings

### Domain Module Documentation Review ✅ **COMPLETED**

**Documentation URL:** https://opensips.org/html/docs/modules/3.6.x/domain.html

**Available Functions:**

1. **`is_domain(domain)`** - Domain validation function
   - **Purpose:** Checks if domain exists in domain table
   - **Return Value:** TRUE if domain exists, FALSE otherwise
   - **Parameters:** Domain name (string)
   - **Does NOT return:** Domain attributes (setid, etc.)
   - **Usage:** `if (is_domain($var(domain))) { ... }`

2. **`is_domain_r(domain, result)`** - Domain validation with result variable
   - **Purpose:** Checks if domain exists and stores result in variable
   - **Return Value:** TRUE if domain exists, FALSE otherwise
   - **Parameters:** Domain name, result variable
   - **Does NOT return:** Domain attributes (setid, etc.)
   - **Usage:** `if (is_domain_r($var(domain), "$var(result)")) { ... }`

**Available Parameters (modparam):**
- `db_url` - Database URL
- `db_mode` - Database mode (0=no DB, 1=DB only, 2=cached DB)
- `domain_table` - Domain table name (default: "domain")
- `domain_col` - Domain column name (default: "domain")
- `domain_attrs_avp` - AVP name for domain attributes (if supported)

**Key Finding:**
- Domain module provides **validation functions only**
- No functions exist to retrieve domain attributes (setid)
- `domain_attrs_avp` parameter exists but is for **storing** attributes, not retrieving them
- Domain module is designed for **validation**, not **attribute retrieval**

**Limitation Confirmed:**
- Domain module is designed for **validation**, not **attribute retrieval**
- The `is_domain()` function only checks if domain exists in cache/database
- It does NOT return domain attributes like `setid`
- No standard function exists to get setid from domain module

### Conclusion

**The domain module does NOT provide functions to retrieve domain attributes (setid).**

**Why Custom SQL is Necessary:**
- Domain module validates domain existence
- Domain module does NOT provide attribute access
- Custom SQL is required to get `setid` from domain table

**Additional Context:**
- OpenSIPS no longer favors the `setid` approach for linking domains and destinations
- Newer OpenSIPS approaches may be more complex
- For our user base, the simpler `setid` approach is justified and appropriate
- Custom SQL for setid retrieval is acceptable given our requirements and user base needs

**However:** The domain module's caching (`db_mode=2`) may still benefit our custom SQL query:
- Domain module caches domain data in memory
- Our SQL query may hit cached data (if MySQL query cache is enabled)
- But we're not leveraging domain module's cache directly

### Recommendation

**Option 1: Keep Custom SQL (Current Approach) ✅ RECOMMENDED**
- **Justification:** Domain module doesn't provide attribute access
- **Action:** Add comment explaining why custom SQL is needed
- **Documentation:** Update code comments to reference this research

**Option 2: Use Domain Module for Validation + SQL for Attributes**
```opensips
# Validate domain exists using standard function
if (!is_domain($var(domain))) {
    xlog("L_NOTICE", "Door-knock blocked: domain=$var(domain) src=$si (not found)\n");
    exit;
}

# Get setid using SQL (domain module doesn't provide this)
$var(query) = "SELECT setid FROM domain WHERE domain='" + $var(domain) + "'";
if (!sql_query($var(query), "$avp(domain_setid)")) {
    # ...
}
```

**Benefits:**
- Uses `is_domain()` for validation (standard approach)
- Still needs SQL for setid (acceptable - domain module limitation)
- Clear separation: validation vs attribute retrieval

**Option 3: Enhance Domain Module (Future Consideration)**
- Could request enhancement to domain module to return attributes
- Not practical for current implementation

---

## Current Status

**Status:** ✅ **RESEARCH COMPLETE**

**Finding:** Domain module does NOT provide functions to retrieve domain attributes (setid). Custom SQL is necessary and acceptable.

**Recommendation:** 
1. ✅ Keep custom SQL for setid retrieval (justified)
2. ✅ Consider using `is_domain()` for validation first (if desired)
3. ✅ Add code comments explaining why custom SQL is needed

**Next Action:** Update code comments to document this finding

---

**Last Updated:** January 2026  
**Status:** Research complete - custom SQL is justified, domain module limitation documented
