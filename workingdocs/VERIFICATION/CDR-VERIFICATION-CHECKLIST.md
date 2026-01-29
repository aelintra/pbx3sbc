# CDR Verification Testing Checklist

**Date:** 2026-01-18  
**Status:** Ready for Testing  
**Branch:** `main` (accounting merged)

## Overview

This checklist verifies that CDR (Call Detail Record) accounting is working correctly after the implementation. The CDR system should:
- Capture billing information (From/To SIP URIs)
- Create single CDR record per call (not separate INVITE/BYE rows)
- Calculate duration correctly
- Populate timestamps correctly
- Work for both domain routing and endpoint routing paths

## Prerequisites

- [ ] OpenSIPS is running with updated configuration
- [ ] Database schema is up to date (run `init-database.sh` if needed)
- [ ] `acc` table has `from_uri` and `to_uri` columns
- [ ] `dialog` table exists
- [ ] Test endpoints are registered and working

## Pre-Test Verification

### 1. Database Schema Check

Run the verification script:
```bash
sudo scripts/verify-cdr.sh
```

Or manually verify:
```sql
-- Check acc table structure
DESCRIBE acc;

-- Verify columns exist
SELECT COLUMN_NAME 
FROM INFORMATION_SCHEMA.COLUMNS 
WHERE TABLE_SCHEMA = 'opensips' 
  AND TABLE_NAME = 'acc' 
  AND COLUMN_NAME IN ('from_uri', 'to_uri');

-- Check dialog table exists
SHOW TABLES LIKE 'dialog';
```

**Expected Results:**
- ✓ `acc` table exists
- ✓ `dialog` table exists
- ✓ `from_uri` column exists in `acc` table
- ✓ `to_uri` column exists in `acc` table

### 2. OpenSIPS Configuration Check

Verify configuration is correct:
```bash
# Check OpenSIPS config syntax
sudo opensips -C

# Check if modules are loaded (should see dialog and acc)
sudo opensipsctl fifo which modules | grep -E "(dialog|acc)"
```

**Expected Results:**
- ✓ Config syntax is valid
- ✓ `dialog` module is loaded
- ✓ `acc` module is loaded

### 3. Check OpenSIPS Logs

Before making test calls, check for any errors:
```bash
sudo journalctl -u opensips -n 50 --no-pager | grep -iE "(error|critical|acc|dialog)"
```

**Expected Results:**
- ✓ No database connection errors
- ✓ No module loading errors
- ✓ No accounting-related errors

## Test Scenarios

### Test 1: Domain Routing - Basic Call

**Objective:** Verify CDR works for domain-based routing (through dispatcher)

**Steps:**
1. Make a call using domain routing (e.g., `sip:1001@example.com` to `sip:1000@example.com`)
2. Let the call connect and talk for 10-15 seconds
3. Hang up the call
4. Wait 2-3 seconds for CDR to be written

**Verification:**
```sql
-- Get the most recent CDR record
SELECT 
    id,
    method,
    callid,
    sip_code,
    from_uri,
    to_uri,
    duration,
    ms_duration,
    created,
    time
FROM acc 
ORDER BY id DESC 
LIMIT 1;
```

**Expected Results:**
- ✓ Single CDR record created (not multiple rows)
- ✓ `method` = 'INVITE'
- ✓ `sip_code` = '200' (or appropriate success code)
- ✓ `from_uri` is populated with full SIP URI (e.g., `sip:1001@example.com`)
- ✓ `to_uri` is populated with full SIP URI (e.g., `sip:1000@example.com`)
- ✓ `duration` > 0 (matches call duration)
- ✓ `ms_duration` > 0 (matches call duration in milliseconds)
- ✓ `created` timestamp is valid (not NULL, not '0000-00-00 00:00:00')
- ✓ `time` timestamp is valid

### Test 2: Endpoint Routing - Basic Call

**Objective:** Verify CDR works for IP-based endpoint routing

**Steps:**
1. Make a call using endpoint routing (e.g., `sip:402@192.168.1.232:5060` to `sip:400@192.168.1.100:5060`)
2. Let the call connect and talk for 10-15 seconds
3. Hang up the call
4. Wait 2-3 seconds for CDR to be written

**Verification:**
```sql
-- Get the most recent CDR record
SELECT 
    id,
    method,
    callid,
    from_uri,
    to_uri,
    duration,
    ms_duration
FROM acc 
ORDER BY id DESC 
LIMIT 1;
```

**Expected Results:**
- ✓ Single CDR record created
- ✓ `from_uri` contains full SIP URI with IP address
- ✓ `to_uri` contains full SIP URI with IP address
- ✓ Duration is calculated correctly

### Test 3: Multiple Calls - No Duplicates

**Objective:** Verify each call creates exactly one CDR record

**Steps:**
1. Make 3-5 test calls (mix of domain and endpoint routing)
2. Let each call complete (connect and hang up)
3. Wait a few seconds after each call

**Verification:**
```sql
-- Check for duplicate Call-IDs
SELECT callid, COUNT(*) as count
FROM acc
GROUP BY callid
HAVING count > 1;
```

**Expected Results:**
- ✓ No duplicate Call-IDs found
- ✓ Each call has exactly one CDR record
- ✓ CDR mode is correlating INVITE and BYE correctly

### Test 4: Call Duration Accuracy

**Objective:** Verify duration calculation is accurate

**Steps:**
1. Make a call and note the exact duration (use phone display or timer)
2. Hang up after exactly 30 seconds
3. Check CDR record

**Verification:**
```sql
SELECT 
    callid,
    duration,
    ms_duration,
    created,
    time,
    TIMESTAMPDIFF(SECOND, created, time) as calculated_duration
FROM acc 
ORDER BY id DESC 
LIMIT 1;
```

**Expected Results:**
- ✓ `duration` matches actual call duration (±1 second tolerance)
- ✓ `ms_duration` matches actual call duration in milliseconds
- ✓ Duration is calculated from `created` to `time` timestamps

### Test 5: Failed Call (No Answer)

**Objective:** Verify CDR is created for failed calls

**Steps:**
1. Make a call to an unregistered endpoint or busy number
2. Let it ring until timeout or busy signal
3. Check CDR record

**Verification:**
```sql
SELECT 
    callid,
    sip_code,
    sip_reason,
    from_uri,
    to_uri,
    duration,
    created
FROM acc 
WHERE sip_code != '200'
ORDER BY id DESC 
LIMIT 1;
```

**Expected Results:**
- ✓ CDR record created for failed call
- ✓ `sip_code` reflects failure code (e.g., '404', '408', '486')
- ✓ `sip_reason` contains failure reason
- ✓ `from_uri` and `to_uri` are populated
- ✓ `duration` may be 0 or very small for failed calls

### Test 6: Dialog Table Population

**Objective:** Verify dialog table is populated (with db_mode=2)

**Steps:**
1. Make a successful call
2. Check dialog table

**Verification:**
```sql
-- Check dialog table
SELECT 
    dlg_id,
    callid,
    from_uri,
    to_uri,
    state,
    created,
    modified
FROM dialog 
ORDER BY created DESC 
LIMIT 1;
```

**Expected Results:**
- ✓ Dialog record created (may be cached, but should appear in DB)
- ✓ `callid` matches CDR record
- ✓ `from_uri` and `to_uri` populated
- ✓ `state` reflects dialog state
- ✓ Timestamps are valid

**Note:** With `db_mode=2` (cached DB), dialogs are primarily in memory but should still be written to the database.

## Post-Test Verification

### 1. Run Verification Script

```bash
sudo scripts/verify-cdr.sh
```

**Expected Output:**
- ✓ All schema checks pass
- ✓ CDR records found
- ✓ From/To URIs populated
- ✓ Durations calculated
- ✓ No duplicate Call-IDs

### 2. Check OpenSIPS Logs

```bash
sudo journalctl -u opensips -n 100 --no-pager | grep -iE "(acc|accounting|cdr)"
```

**Expected Results:**
- ✓ No accounting errors
- ✓ No database errors
- ✓ Accounting calls logged successfully

### 3. Verify Data Quality

```sql
-- Summary statistics
SELECT 
    COUNT(*) as total_records,
    COUNT(DISTINCT callid) as unique_calls,
    COUNT(CASE WHEN from_uri IS NOT NULL AND from_uri != '' THEN 1 END) as records_with_from_uri,
    COUNT(CASE WHEN to_uri IS NOT NULL AND to_uri != '' THEN 1 END) as records_with_to_uri,
    COUNT(CASE WHEN duration > 0 THEN 1 END) as records_with_duration,
    AVG(duration) as avg_duration,
    MAX(duration) as max_duration
FROM acc;
```

**Expected Results:**
- ✓ `total_records` = `unique_calls` (no duplicates)
- ✓ All records have `from_uri` populated
- ✓ All records have `to_uri` populated
- ✓ Most successful calls have `duration > 0`

## Troubleshooting

### Issue: No CDR Records Created

**Check:**
1. OpenSIPS is running: `sudo systemctl status opensips`
2. Database connection: Check OpenSIPS logs for DB errors
3. Accounting is enabled: Verify `do_accounting("db", "cdr")` is called
4. Database permissions: Ensure OpenSIPS user can INSERT into `acc` table

**Fix:**
- Restart OpenSIPS: `sudo systemctl restart opensips`
- Check config syntax: `sudo opensips -C`
- Verify database credentials in config

### Issue: from_uri/to_uri are NULL

**Check:**
1. Columns exist: `DESCRIBE acc;`
2. `extra_fields` modparam is set: `grep extra_fields config/opensips.cfg.template`
3. `$acc_extra()` is called before `do_accounting()`

**Fix:**
- Add columns: Run `init-database.sh` or `add-acc-columns.sql`
- Verify `extra_fields` modparam is present
- Check that `$acc_extra()` is set before `do_accounting()` call

### Issue: Multiple Rows Per Call

**Check:**
- Verify CDR mode is enabled: `grep "do_accounting.*cdr" config/opensips.cfg.template`
- Check for BYE accounting calls (should NOT exist)

**Fix:**
- Ensure using `do_accounting("db", "cdr")` not `do_accounting("db")`
- Remove any BYE accounting calls (CDR mode handles it automatically)

### Issue: Duration is 0

**Check:**
- Dialog module is loaded: `sudo opensipsctl fifo which modules | grep dialog`
- CDR mode is enabled
- Call completed normally (not failed immediately)

**Fix:**
- Ensure dialog module is loaded before acc module
- Verify `db_mode=2` for dialog module
- Check that call actually connected (not failed)

### Issue: Created Timestamp is Invalid

**Check:**
- Database column type: `DESCRIBE acc;` (should be DATETIME)
- CDR mode is enabled (required for `created` timestamp)

**Fix:**
- Ensure CDR mode is enabled: `do_accounting("db", "cdr")`
- Verify dialog module is loaded and configured

## Success Criteria

CDR verification is complete when:

- [x] All schema checks pass
- [x] Test 1 (Domain Routing) passes ✓ (Rows 20, 21 - pjsipsbc.vcloudpbx.com)
- [x] Test 2 (Endpoint Routing) passes ✓ (Rows 17, 18, 19, 22 - IP addresses)
- [x] Test 3 (No Duplicates) passes ✓ (Each callid appears once)
- [x] Test 4 (Duration Accuracy) passes ✓ (Durations 6-72 seconds, ms_duration accurate)
- [ ] Test 5 (Failed Calls) passes (Not tested yet)
- [ ] Test 6 (Dialog Table) passes (Not verified yet)
- [x] Verification script shows all checks passing
- [x] No errors in OpenSIPS logs

## Next Steps After Verification

Once CDR verification is complete:

1. **Document Results:** Update this checklist with test results
2. **Production Deployment:** CDR is ready for production use
3. **Monitoring:** Set up monitoring/alerting for CDR data
4. **Billing Integration:** Integrate CDR data with billing system
5. **Reporting:** Create reports/dashboards using CDR data

## References

- OpenSIPS acc module: https://opensips.org/docs/modules/3.6.x/acc.html
- OpenSIPS dialog module: https://opensips.org/docs/modules/3.6.x/dialog.html
- Advanced Accounting Tutorial: https://www.opensips.org/Documentation/Tutorials-Advanced-Accounting
- Session Summary: `workingdocs/SESSION-SUMMARY-ACCOUNTING-CDR.md`
