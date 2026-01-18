# Session Summary: Accounting/CDR Implementation

## Date
2026-01-17

## Overview
Implemented CDR (Call Detail Records) mode accounting in OpenSIPS to capture billable call information including duration, timestamps, and SIP URIs for billing purposes.

## Current Status
- ✅ CDR mode enabled with dialog module
- ✅ Duration calculation working (row 12 shows duration=6, ms_duration=5070)
- ✅ Created timestamp populated correctly
- ⏳ From/To SIP URIs - implementation in progress (needs testing)
- ⏳ Dialog table empty (expected with db_mode=2, but should populate)

## Branch
`accounting` (created from `main` after merging `476fix`)

## Implementation Steps

### 1. Added Dialog Module (Required for CDR Mode)
**File:** `config/opensips.cfg.template`

- **Line 54:** Added `loadmodule "dialog.so"` (must be loaded before acc module)
- **Lines 74-77:** Configured dialog module:
  ```opensips
  modparam("dialog", "db_url", "mysql://opensips:your-password@localhost/opensips")
  modparam("dialog", "db_mode", 2)  # Changed from 0 to 2 (cached DB) for better CDR correlation
  ```

### 2. Enabled CDR Mode in Accounting
**File:** `config/opensips.cfg.template`

- **Line 414:** Changed `do_accounting("db")` to `do_accounting("db", "cdr")` for INVITE requests
- **Lines 413-414:** Added `$acc_extra()` calls to capture From/To URIs:
  ```opensips
  $acc_extra(from_uri) = $fu;
  $acc_extra(to_uri) = $tu;
  ```
- **Removed:** BYE accounting call (CDR mode handles correlation automatically)

### 3. Database Schema Updates
**File:** `scripts/init-database.sh`

- **Line 35:** Added `dialog-create.sql` to schema files list
- **Lines 64-72:** Added dialog schema loading (idempotent - checks if table exists)
- **Lines 161-189:** Added code to create `from_uri` and `to_uri` columns in acc table:
  - Idempotent: checks if columns exist before adding
  - Columns: `VARCHAR(255) DEFAULT NULL`
  - Positioned after `to_tag` column

### 4. Made init-database.sh Fully Idempotent
**File:** `scripts/init-database.sh`

- **Lines 59-65:** Added table existence check for acc table before loading schema
- **Lines 75-81:** Added table existence check for dialog table before loading schema
- **Lines 90-96:** Added table existence check for dispatcher table (preserves existing entries)
- **Lines 98-107:** Added table existence check for domain table (preserves existing entries)

## Issues Encountered and Fixed

### Issue 1: Parse Error - Unknown Function `dlg_manage()`
**Error:**
```
parse error in /etc/opensips/opensips.cfg:409:20-21: unknown command <dlg_manage>, missing loadmodule?
```

**Root Cause:** `dlg_manage()` function doesn't exist in OpenSIPS. Dialog tracking is automatic with CDR mode.

**Fix:** Removed all `dlg_manage()` calls. CDR mode with dialog module handles dialog tracking automatically.

**Files Changed:**
- `config/opensips.cfg.template` - Removed `dlg_manage()` calls from INVITE and BYE handling

### Issue 2: Missing From/To SIP URIs in CDR
**Problem:** Standard acc table only has:
- `from_tag` - SIP tag (e.g., "3954390938"), not the URI
- `to_tag` - SIP tag (e.g., "f76d0c25-5af0-40bd-aad2-d3e97280a5e0"), not the URI
- `callid` - Call-ID header, not the URI

**For billing, we need actual SIP URIs** (e.g., "sip:1001@example.com")

**Solution Implemented:**
1. Added `from_uri` and `to_uri` columns to acc table
2. Set values using `$acc_extra()` in script:
   ```opensips
   $acc_extra(from_uri) = $fu;
   $acc_extra(to_uri) = $tu;
   ```

**Note:** Initially added `modparam("acc", "extra_fields", "db:from_uri->from_uri;to_uri->to_uri")` but removed it to simplify. Testing needed to confirm if modparam is required or if `$acc_extra()` works without it.

## Current CDR Output

### Working (Row 12 - after CDR mode enabled):
```
| id | method | from_tag | to_tag | callid | sip_code | time | duration | ms_duration | setuptime | created |
| 12 | INVITE | 3976936221 | 9d688bf9-... | 2_3977016247@192.168.1.232 | 200 | 2026-01-17 22:18:30 | 6 | 5070 | 2 | 2026-01-17 22:18:28 |
```

**Good:**
- ✅ `duration=6` seconds (calculated correctly)
- ✅ `ms_duration=5070` milliseconds (precise)
- ✅ `created=2026-01-17 22:18:28` (correct timestamp)
- ✅ `setuptime=2` seconds (time to answer)

**Missing:**
- ⏳ `from_uri` - needs testing after column addition
- ⏳ `to_uri` - needs testing after column addition

### Old Records (Rows 9-11 - before CDR mode):
- `duration=0` (not calculated)
- `created=1969-12-31 19:00:00` (epoch 0 - not populated)
- Separate INVITE and BYE rows (not correlated)

## Configuration Details

### ACC Module Parameters
```opensips
modparam("acc", "db_url", "mysql://opensips:your-password@localhost/opensips")
modparam("acc", "early_media", 0)
modparam("acc", "report_cancels", 1)
modparam("acc", "detect_direction", 1)
# Note: extra_fields modparam removed - testing if $acc_extra() works without it
```

### Dialog Module Parameters
```opensips
modparam("dialog", "db_url", "mysql://opensips:your-password@localhost/opensips")
modparam("dialog", "db_mode", 2)  # Cached DB mode for better CDR correlation
```

### Script Usage
```opensips
if (is_method("INVITE")) {
    # Set extra fields for billing
    $acc_extra(from_uri) = $fu;
    $acc_extra(to_uri) = $tu;
    # Enable CDR mode accounting
    do_accounting("db", "cdr");
}
```

## Database Schema Changes

### Acc Table Columns Added
- `from_uri VARCHAR(255) DEFAULT NULL` - Full From SIP URI
- `to_uri VARCHAR(255) DEFAULT NULL` - Full To SIP URI

### Dialog Table
- Created via `dialog-create.sql` (idempotent)
- Currently empty (expected with db_mode=2, but should populate after calls)

## Open Questions / Testing Needed

1. **Is `extra_fields` modparam required?**
   - Currently removed from config
   - Need to test if `$acc_extra()` works without it
   - If not, add back: `modparam("acc", "extra_fields", "db:from_uri->from_uri;to_uri->to_uri")`

2. **Are From/To URIs being captured?**
   - After adding columns and restarting, test a call
   - Check: `SELECT from_uri, to_uri FROM acc WHERE callid = '...';`

3. **Dialog table population:**
   - With `db_mode=2`, dialog table should populate
   - Check: `SELECT * FROM dialog;` after a call

4. **Single CDR record per call:**
   - CDR mode should produce one record per call (not separate INVITE/BYE)
   - Verify: Check if BYE rows are still being created separately

## Files Modified

1. `config/opensips.cfg.template`
   - Added dialog module loading
   - Added dialog module configuration
   - Changed `do_accounting("db")` to `do_accounting("db", "cdr")`
   - Added `$acc_extra()` calls for From/To URIs
   - Removed `dlg_manage()` calls (function doesn't exist)
   - Removed BYE accounting call (CDR mode handles it)

2. `scripts/init-database.sh`
   - Added dialog-create.sql to schema files
   - Added dialog schema loading (idempotent)
   - Added from_uri and to_uri columns to acc table (idempotent)
   - Made all schema loading idempotent (checks table existence)

## Commits

- `1f5b362` - Add CDR mode accounting with dialog module
- (Current changes not yet committed - from_uri/to_uri addition)

## Next Steps

1. **Test From/To URI capture:**
   - Run `init-database.sh` to add columns (or manually add them)
   - Restart OpenSIPS
   - Make test call
   - Verify: `SELECT from_uri, to_uri, duration, created FROM acc WHERE callid = '...';`

2. **If URIs not captured:**
   - Add back `modparam("acc", "extra_fields", "db:from_uri->from_uri;to_uri->to_uri")`
   - Test again

3. **Verify single CDR per call:**
   - Check if separate BYE rows are still created
   - CDR mode should correlate INVITE and BYE into single record

4. **Check dialog table:**
   - Verify dialog table populates with `db_mode=2`
   - May need to adjust dialog configuration if needed

## Key Learnings

1. **CDR mode requires dialog module** - Must be loaded before acc module
2. **`dlg_manage()` doesn't exist** - Dialog tracking is automatic with CDR mode
3. **Standard acc table lacks From/To URIs** - Need to add columns for billing
4. **`$acc_extra()` sets extra field values** - Used in script before `do_accounting()`
5. **`extra_fields` modparam may be optional** - Testing needed to confirm
6. **CDR mode produces single record** - Should correlate INVITE and BYE automatically
7. **Dialog db_mode=2** - Cached DB mode better for CDR correlation than in-memory

## References

- OpenSIPS acc module docs: https://opensips.org/docs/modules/3.6.x/acc.html
- OpenSIPS dialog module docs: https://opensips.org/docs/modules/3.6.x/dialog.html
- Standard acc table schema: `dbsource/opensips-3.6.3-sqlite3.sql` lines 33-46
