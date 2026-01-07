# usrloc lookup() Function Update

**Date:** January 2026  
**Correction:** Updated to use `lookup("location")` function

## Key Finding

The `lookup("location")` function **IS available** for proxy nodes, not just registrar nodes. This was confirmed by the user's information about usrloc usage in non-registrar scenarios.

## What Changed

### Endpoint Lookup Route (`route[ENDPOINT_LOOKUP]`)

**Before:** Direct SQL queries to `location` table  
**After:** Use `lookup("location")` function for exact AoR matches, SQL fallback for username-only lookups

### How It Works

1. **Exact AoR Lookup (if AoR provided):**
   - Set Request-URI to `sip:user@domain`
   - Call `lookup("location")`
   - If found, `$du` is set with contact URI (e.g., `sip:user@192.168.1.100:5060`)
   - Extract IP and port from `$du` using regex

2. **Username-Only Lookup (fallback):**
   - `lookup()` requires full Request-URI, so we use SQL fallback
   - Query `location` table directly for username match
   - Extract IP/port from contact URI

3. **Legacy Table Fallback:**
   - If location table lookup fails, try legacy `endpoint_locations` table

## Benefits

1. **Uses Standard Function:** `lookup()` is the proper way to query usrloc
2. **Automatic Expiration:** usrloc handles expired entries automatically
3. **Better Performance:** usrloc may cache lookups in memory
4. **Standard Approach:** Uses OpenSIPS standard lookup mechanism

## Storage (Still Using SQL)

We continue to use SQL INSERT for storing endpoint locations because:
- We're not using registrar module's `save()` function
- We manually track endpoints for routing OPTIONS/NOTIFY
- SQL gives us direct control over what gets stored

## Configuration

The usrloc module is configured with:
- `db_mode = 2` (write-back mode)
- `db_table = "location"`
- `timer_interval = 60` (sync interval)

This allows usrloc to manage the location table structure while we populate it via SQL.

## Testing

1. **Register endpoint:**
   - Data stored via SQL INSERT to `location` table

2. **Lookup endpoint:**
   - Use `lookup("location")` with full AoR
   - Should find contact and set `$du`
   - Extract IP/port from `$du`

3. **Verify:**
   - Check logs for "usrloc lookup() found contact"
   - Verify `$du` contains correct contact URI
   - Verify IP/port extraction works

## References

- OpenSIPS usrloc module can be used by proxy nodes via `lookup()` function
- Real-time mirroring, shared NoSQL backends, or federated metadata can sync data
- `lookup()` works even if node is not the registrar

