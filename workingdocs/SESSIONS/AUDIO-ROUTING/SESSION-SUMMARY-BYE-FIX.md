# Session Summary: BYE Request Fix & Accounting Implementation

## Current Status

**Branch:** `main` (working branch)  
**Issue:** BYE requests returning 476 "Unresolvable destination" errors  
**Status:** In progress - fix applied but needs testing

## What We Discovered

1. **Pre-existing BYE Issue**: The 476 error on BYE requests existed in `main` branch before accounting was added. It's not caused by accounting changes.

2. **Root Cause**: When BYE requests come in with Route headers, `loose_route()` succeeds and routes to `RELAY`, but `t_relay()` fails because the transaction doesn't exist or has expired.

3. **Accounting Implementation**: We implemented accounting (CDR) on `phase2` branch, but it exposed the pre-existing BYE issue. We reverted accounting changes to focus on fixing BYE first.

## Fix Applied (main branch)

**File:** `config/opensips.cfg.template`  
**Location:** `route[RELAY]` section (around line 819-850)

**Changes:**
- Added special handling for BYE requests
- When `t_relay()` fails for BYE, fall back to stateless `forward()`
- Ensures BYE can be routed even if INVITE transaction has expired
- Added logging to debug routing issues

**Key Code:**
```opensips
if (is_method("BYE")) {
    if ($du == "") {
        $du = $ru;
    }
    if (!t_relay()) {
        # Fallback to stateless forward
        if (!forward()) {
            sl_send_reply(500, "Internal Server Error");
            exit;
        }
    }
}
```

**Commits:**
- `25c8dd0` - Initial BYE fix with stateless forward fallback
- `1bd49b4` - Attempted improvement (had syntax errors)
- `18c45fc` - Fixed syntax errors, simplified approach

## Testing Status

**Needs Testing:** The fix has been applied to `main` branch but needs verification that BYE requests now work correctly.

**Test Case:**
1. Make a call (INVITE)
2. Wait for call to establish
3. Hang up (BYE)
4. Verify BYE routes correctly without 476 errors

## Next Steps

1. **Test BYE Fix**: Verify the fix works on test host
2. **If BYE Works**: Re-implement accounting more carefully
3. **If BYE Still Fails**: Investigate what `loose_route()` is setting `$du` to and handle that case

## Accounting Implementation (Phase 2 Branch)

**Status:** Paused - waiting for BYE fix confirmation

**What Was Done:**
- Added `acc` module loading
- Configured `acc` module parameters
- Added `do_accounting("db")` for INVITE requests
- Created database tables (`acc`, `missed_calls`)
- Updated `init-database.sh` to load `acc-create.sql`

**What Was Removed:**
- BYE accounting calls (removed to avoid interfering with routing)
- Will be re-added after BYE fix is confirmed

## Database Changes

**File:** `scripts/init-database.sh`

**Changes:**
- Now loads `acc-create.sql` for accounting tables
- Made idempotent (checks for existing tables before loading)
- Reads credentials from `/etc/opensips/.mysql_credentials`

**Tables Created:**
- `acc` - Call Detail Records
- `missed_calls` - Missed call logging
- `version` - Schema version tracking
- `dispatcher` - Load balancing
- `domain` - Domain management
- `endpoint_locations` - Custom endpoint tracking

## Key Files Modified

1. `config/opensips.cfg.template` - BYE handling fix
2. `scripts/init-database.sh` - Accounting table creation, idempotency, credential reading

## Important Notes

- The BYE issue is **pre-existing** - not caused by accounting
- Accounting implementation is on `phase2` branch (paused)
- Main branch has BYE fix but needs testing
- All changes are committed and pushed to origin

## To Resume Work

1. Test the BYE fix on main branch
2. If successful, cherry-pick accounting changes from phase2 to main
3. Re-add BYE accounting carefully (after routing is confirmed working)
4. Test full accounting implementation
