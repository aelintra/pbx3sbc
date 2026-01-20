# Usrloc Migration - Quick Reference for Next Session

**Last Updated:** January 20, 2026  
**Status:** save() working ✅ | lookup() working ✅ | INVITE routing working ✅

## What's Done ✅

1. **Location table created** with `BIGINT UNSIGNED` contact_id
2. **Modules loaded:** usrloc, registrar, domain, signaling
3. **save() function working** - registrations saving to location table
4. **Proxy-registrar pattern implemented** in `onreply_route[handle_reply_reg]`

## Critical Fix Applied

**Problem:** UUID-based Call-IDs (from Snom phones) caused hash overflow
- Hash values exceeded `INT UNSIGNED` max (4,294,967,295)
- Actual value: `3617797875662073346`

**Solution:** Changed `contact_id` to `BIGINT UNSIGNED`
```sql
ALTER TABLE location MODIFY COLUMN contact_id BIGINT UNSIGNED AUTO_INCREMENT NOT NULL;
```

## Current Configuration

### Modules Loaded
```opensips
loadmodule "usrloc.so"
loadmodule "signaling.so"
loadmodule "registrar.so"
loadmodule "domain.so"
```

### usrloc Parameters
```opensips
modparam("usrloc", "db_url", "mysql://opensips:your-password@localhost/opensips")
modparam("usrloc", "db_mode", 2)  # Cached DB mode
modparam("usrloc", "use_domain", 1)  # Domain-aware (required!)
modparam("usrloc", "nat_bflag", "NAT")
modparam("usrloc", "timer_interval", 10)
modparam("usrloc", "regen_broken_contactid", 1)
```

### save() Implementation
**Location:** `config/opensips.cfg.template` lines ~1027-1080

```opensips
onreply_route[handle_reply_reg] {
    if (is_method("REGISTER")) {
        if (t_check_status("2[0-9][0-9]")) {
            # Exit early if reply Contact is missing
            if ($hdr(Contact) == "") {
                xlog("REGISTER: ERROR: Reply Contact header is empty/null\n");
                exit;
            }
            
            # Save location (extracts Contact from reply)
            if (save("location")) {
                xlog("REGISTER: Successfully saved location\n");
            }
        }
    }
    exit;
}
```

## ✅ Completed: lookup() Implementation

**Status:** OPTIONS/NOTIFY/INVITE routing now uses `lookup("location")` function

**Implementation:**
- OPTIONS/NOTIFY routing: Uses `lookup("location")` for domain-specific lookups, SQL fallback for wildcard
- INVITE routing: Uses SQL query to `location` table (wildcard lookup for username-only)
- Both working correctly - routing to endpoints successfully

**Key Points:**
- `lookup("location")` sets `$du` automatically when contact found
- Domain-specific lookup: Set Request-URI to `sip:user@domain`, then call `lookup("location")`
- Wildcard lookup: SQL query to `location` table for username-only searches
- Returns true if contact found, false otherwise

## Files Modified Today

1. `scripts/create-location-table.sql` - Changed contact_id to BIGINT UNSIGNED
2. `config/opensips.cfg.template` - Added modules, parameters, save() implementation
3. Database - ALTER TABLE to fix contact_id type

## Key Learnings

1. **OpenSIPS computes contact_id** from hash (includes Call-ID)
2. **UUID Call-IDs** produce large hash values → need BIGINT
3. **save() extracts Contact from REPLY**, not request
4. **No flags needed** for save() in onreply_route
5. **Failed registrations** correctly don't create records

## Test Verification

```sql
-- Check location table
SELECT * FROM location;

-- Should show:
-- contact_id: BIGINT value (e.g., 3617797875662073346)
-- username: extension number
-- domain: domain name
-- contact: full Contact URI
-- expires: Unix timestamp
-- callid: UUID format
```

## Documentation

- **Full session notes:** `workingdocs/SESSION-SUMMARY-USRLOC-SAVE-FIX.md`
- **Migration plan:** `docs/USRLOC-MIGRATION-PLAN.md`
- **Table schema:** `scripts/create-location-table.sql`

## Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| `contact_id` overflow | Use `BIGINT UNSIGNED` |
| `save()` not found | Load `registrar.so` module |
| `registrar` dependency error | Load `signaling.so` module |
| Reply Contact `<null>` | Exit early (can't save) |
| No data in table | Check `db_mode` and `timer_interval` |

## Quick Commands

```bash
# Check OpenSIPS status
sudo systemctl status opensips

# Restart OpenSIPS
sudo systemctl restart opensips

# Check config syntax
sudo opensips -C

# Check location table
mysql -u opensips -p opensips -e "SELECT * FROM location;"
```
