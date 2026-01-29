# Domain Attributes Migration Plan

**Date:** January 2026  
**Status:** 📋 **PLANNING**  
**Purpose:** Migrate from custom `setid` column queries to standard OpenSIPS `attrs` column approach

---

## Executive Summary

Migrate domain-to-dispatcher linking from custom SQL queries on `setid` column to standard OpenSIPS domain module `attrs` column approach using `is_domain_local()` function and `{param.value}` transformation.

---

## Current State

### Database Schema
```sql
domain table:
- id (int, PK)
- domain (char(64), UNIQUE)
- attrs (char(255), NULL) ✅ Already exists!
- accept_subdomain (int)
- last_modified (datetime)
- setid (int, indexed) ← Custom column we added
```

### Current Implementation

**Location 1: Forward Lookup (domain → setid)**  
**File:** `config/opensips.cfg.template` line ~926  
**Purpose:** Get dispatcher setid for routing

```opensips
$var(query) = "SELECT setid FROM domain WHERE domain='" + $var(domain) + "'";
sql_query($var(query), "$avp(domain_setid)");
$var(setid) = $(avp(domain_setid)[0]);
```

**Location 2: Reverse Lookup (setid → domain)**  
**File:** `config/opensips.cfg.template` line ~1221  
**Purpose:** Find domain from source IP (GET_DOMAIN_FROM_SOURCE_IP route)

```opensips
$var(query) = "SELECT domain FROM domain WHERE setid='" + $var(setid) + "' LIMIT 1";
sql_query($var(query), "$avp(source_domain)");
```

**Scripts:**
- `scripts/add-domain.sh` - Inserts domains with setid
- `scripts/init-database.sh` - Creates setid column

---

## Target State

### Standard OpenSIPS Approach

**Forward Lookup (domain → setid):**
```opensips
# Use domain module function to get attributes
if (is_domain_local($var(domain), $var(attrs))) {
    # Extract setid from attributes string using standard transformation
    # Format: attrs = "setid=10" or "setid=10;feature=enabled"
    $var(setid) = $(var(attrs){param.value,setid});
    
    # Validate setid was found
    if ($var(setid) == "" || $var(setid) == "<null>") {
        # Error handling...
    }
} else {
    # Domain not found
    # Error handling...
}
```

**Reverse Lookup (setid → domain):**
- **Option A:** Keep SQL query (acceptable - different use case)
- **Option B:** Query all domains and check attrs (inefficient, not recommended)

**Recommendation:** Keep SQL query for reverse lookup since it's a different use case (IP → setid → domain), not domain validation.

---

## Migration Steps

### Step 1: Database Migration Script

**File:** `scripts/migrate-domain-attrs.sh` (new)

**Purpose:** Populate `attrs` column from existing `setid` values

```sql
-- Migrate setid values to attrs format: "setid=10"
UPDATE domain 
SET attrs = CONCAT('setid=', setid) 
WHERE setid IS NOT NULL 
  AND setid != 0 
  AND (attrs IS NULL OR attrs = '');

-- Verify migration
SELECT domain, setid, attrs FROM domain LIMIT 10;
```

### Step 2: Update OpenSIPS Configuration

**File:** `config/opensips.cfg.template`

**Changes:**
1. Replace forward lookup SQL query (line ~926) with `is_domain_local()` + `{param.value}` transformation
2. Keep reverse lookup SQL query (line ~1221) - acceptable for this use case
3. Update comments to reflect standard approach

### Step 3: Update Scripts

**File:** `scripts/add-domain.sh`

**Changes:**
- Update to populate both `setid` AND `attrs` columns
- Format: `attrs = "setid=10"`

**File:** `scripts/init-database.sh`

**Changes:**
- Update migration to also populate `attrs` column when creating `setid` column

### Step 4: Configuration Verification

**File:** `config/opensips.cfg.template`

**Verify:**
- `modparam("domain", "attrs_col", "attrs")` is set (or defaults to "attrs")
- Domain module is configured correctly

---

## Benefits

✅ **Standard OpenSIPS Approach**
- Uses official domain module functions
- Aligns with OpenSIPS best practices
- Better maintainability

✅ **Performance**
- Leverages domain module caching (`db_mode=2`)
- Attributes cached in memory
- No SQL query overhead

✅ **Flexibility**
- Can store multiple attributes: `"setid=10;feature=enabled;timeout=30"`
- Easy to extend with additional attributes
- Standard transformation syntax

✅ **Code Quality**
- Removes custom SQL query
- Uses standard transformations
- Cleaner, more maintainable code

---

## Backward Compatibility

**Keep `setid` column:**
- ✅ Maintains backward compatibility
- ✅ Required for reverse lookup (setid → domain)
- ✅ Scripts can continue using setid
- ✅ Can be removed later if desired

**Migration Strategy:**
- Phase 1: Populate `attrs` column, keep `setid` column
- Phase 2: Update code to use `attrs` approach
- Phase 3: (Optional) Remove `setid` column after verification

---

## Testing Plan

### 1. Database Migration Test
```bash
# Run migration script
sudo ./scripts/migrate-domain-attrs.sh

# Verify data
mysql -u opensips -p opensips -e "SELECT domain, setid, attrs FROM domain LIMIT 10;"
```

### 2. Configuration Test
```bash
# Test OpenSIPS config syntax
sudo opensipsctl cfg_check

# Reload configuration
sudo opensipsctl fifo cfg_reload
```

### 3. Functional Test
- Test domain validation (door-knock protection)
- Test routing to dispatcher (forward lookup)
- Test reverse lookup (GET_DOMAIN_FROM_SOURCE_IP)
- Verify logs show correct setid extraction

### 4. Performance Test
- Compare SQL query vs domain module caching
- Verify no performance regression

---

## Rollback Plan

If migration fails:

1. **Database Rollback:**
   ```sql
   -- Clear attrs column (setid column still exists)
   UPDATE domain SET attrs = NULL;
   ```

2. **Code Rollback:**
   - Revert `opensips.cfg.template` changes
   - Restore SQL query approach

3. **Configuration Reload:**
   ```bash
   sudo opensipsctl fifo cfg_reload
   ```

---

## Implementation Checklist

- [ ] Create `scripts/migrate-domain-attrs.sh` migration script
- [ ] Test migration script on non-production database
- [ ] Update `config/opensips.cfg.template` forward lookup
- [ ] Update `scripts/add-domain.sh` to populate attrs
- [ ] Update `scripts/init-database.sh` to populate attrs
- [ ] Update documentation comments in code
- [ ] Test configuration syntax (`opensipsctl cfg_check`)
- [ ] Test functional routing (forward lookup)
- [ ] Test reverse lookup (GET_DOMAIN_FROM_SOURCE_IP)
- [ ] Verify domain module caching works
- [ ] Update `docs/DOMAIN-MODULE-RESEARCH.md` with findings
- [ ] Update `docs/PROJECT-CONTEXT.md` with new approach

---

## Related Documentation

- `docs/DOMAIN-MODULE-RESEARCH.md` - Original research (needs update)
- `docs/PROJECT-CONTEXT.md` - Project overview
- `workingdocs/OpenSIPS-link-domains-with-dispatcher.md` - Historical context
- OpenSIPS Domain Module: https://opensips.org/docs/modules/3.6.x/domain.html

---

## Notes

### Why Keep Reverse Lookup SQL Query?

The reverse lookup (`GET_DOMAIN_FROM_SOURCE_IP`) is a different use case:
- **Forward lookup:** Domain name → setid (domain validation + attribute retrieval)
- **Reverse lookup:** Source IP → setid → domain (multi-tenant detection)

For reverse lookup, we need to find domain by setid value, which is not a domain validation operation. Using `is_domain_local()` would require iterating through all domains checking attrs, which is inefficient.

**Recommendation:** Keep SQL query for reverse lookup - it's acceptable and appropriate for this use case.

### Attribute Format

**Format:** `"setid=10"` or `"setid=10;feature=enabled;timeout=30"`

**Parsing:** Use `$(var(attrs){param.value,setid})` transformation

**Example:**
```opensips
$var(attrs) = "setid=10;feature=enabled";
$var(setid) = $(var(attrs){param.value,setid});  # Returns "10"
$var(feature) = $(var(attrs){param.value,feature});  # Returns "enabled"
```

---

**Last Updated:** January 2026  
**Status:** Planning phase - ready for implementation
