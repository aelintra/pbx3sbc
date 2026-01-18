# Dialog State Explanation and Troubleshooting

## Understanding Dialog States

In OpenSIPS, the `dialog` table tracks the state of active SIP dialogs. The `state` column uses numeric codes to represent different stages of a call.

**Source:** [OpenSIPS Dialog Module Documentation (3.0.x)](https://opensips.org/docs/modules/3.0.x/dialog.html)

### Dialog State Values

The dialog module uses 5 states (as of OpenSIPS 3.0.x). **Note:** Some older documentation or earlier versions may reference only 4 states.

| State | Name | Description | When It Occurs |
|-------|------|-------------|----------------|
| 1 | Unconfirmed | Dialog created, no reply yet | Initial INVITE sent, waiting for response |
| 2 | Early | Provisional reply (1xx) received | Ringing, 180 Ringing, etc. |
| 3 | Confirmed | Final reply (2xx) received, ACK not yet matched | 200 OK received, waiting for ACK |
| **4** | **Established** | **Final reply (2xx) received AND ACK confirmed** | **Call is active and established** |
| 5 | Ended | Dialog terminated | BYE received and processed |

**Reference:** These values correspond to the `$DLG_status` pseudo-variable documented in the [OpenSIPS Dialog Module](https://opensips.org/docs/modules/3.0.x/dialog.html).

## Is State 4 Correct for Running Calls?

**YES!** State 4 (Established) is the **correct** state for active/running calls. This means:
- ✅ INVITE was sent
- ✅ 200 OK response was received
- ✅ ACK was received and matched
- ✅ Call is fully established and active

**State 4 is NOT an error** - it indicates the call is successfully established.

## When State 4 Might Be a Problem

State 4 becomes a problem only if:

1. **Calls have ended but still show state 4** - Should transition to state 5 (Ended) after BYE
2. **State 4 appears but call never actually established** - Indicates ACK matching issue
3. **State 4 persists indefinitely after call ends** - BYE not being processed correctly

## Common Issues and Solutions

### Issue 1: State 4 Persists After Call Ends

**Symptom:** Dialog shows state 4 even after call has ended (should be state 5)

**Root Cause:** BYE request is not being properly processed by the dialog module

**Possible Causes:**
- BYE is forwarded statelessly (`forward()`) instead of transactionally (`t_relay()`)
- BYE doesn't match the dialog (tag mismatch, routing issues)
- Dialog module doesn't see the BYE due to routing bypass

**Solution:** Ensure BYE requests create transactions so dialog module can track them:

```opensips
# In route[RELAY] or route[WITHINDLG]
if (is_method("BYE")) {
    # Try to create transaction first (allows dialog module to process BYE)
    if (!t_relay()) {
        # Only use stateless forward as last resort
        # Note: Stateless forward may not update dialog state properly
        if (!forward()) {
            sl_send_reply(500, "Internal Server Error");
            exit;
        }
    }
}
```

### Issue 2: State Never Reaches 4 (Stuck at 3)

**Symptom:** Dialog stays at state 3 (Confirmed) even though call is active

**Root Cause:** ACK is not being received or matched by OpenSIPS

**Possible Causes:**
- ACK is not routed through OpenSIPS (missing Record-Route)
- ACK tags don't match (From-tag/To-tag mismatch)
- ACK is lost in network (NAT issues, routing problems)

**Solution:** Ensure Record-Route is added for INVITE:

```opensips
if (is_method("INVITE") && !has_totag()) {
    record_route();  # Ensures ACK comes back through OpenSIPS
    create_dialog();
    t_relay();
}
```

### Issue 3: State 4 Appears But Call Never Established

**Symptom:** Dialog shows state 4 but audio doesn't flow or call fails

**Root Cause:** ACK matching logic may be incorrectly identifying ACK as matched

**Solution:** Check ACK routing and verify actual call establishment

## Current Configuration Analysis

### Your Current Setup

Looking at your `opensips.cfg.template`:

1. **Dialog Creation:** ✅ Correct
   - `create_dialog()` is called for initial INVITE (line 411)
   - Called before `t_relay()` (correct order)

2. **Record-Route:** ✅ Present
   - `record_route()` is called for INVITE (line 399, 769)
   - Ensures ACK and BYE come back through OpenSIPS

3. **BYE Handling:** ⚠️ Potential Issue
   - BYE tries `t_relay()` first (good)
   - Falls back to `forward()` if transaction expired (may not update dialog state)

### Potential Fix for BYE State Transition

The issue might be that when `t_relay()` fails for BYE (transaction expired), the fallback to `forward()` is stateless and may not properly update dialog state.

**Recommended Fix:** Ensure BYE always creates a transaction when possible:

```opensips
# In route[RELAY]
} else if (is_method("BYE")) {
    # Validate destination URI
    if ($du == "" || $du == "0" || $du !~ "^sip:") {
        $du = $ru;
    } else {
        $var(dest_domain) = $(du{uri.domain});
        if ($var(dest_domain) != "" && $var(dest_domain) !~ "^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}" && $rd =~ "^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}") {
            $du = $ru;
        }
    }
    
    # For BYE, always try t_relay() to create transaction
    # This ensures dialog module can properly track BYE and update state to 5
    if (!t_relay()) {
        # If t_relay() fails, try to create new transaction explicitly
        # This is better than stateless forward for dialog state tracking
        if (!t_newtran()) {
            # Last resort: stateless forward (may not update dialog state)
            if (!forward()) {
                sl_send_reply(500, "Internal Server Error");
                exit;
            }
        } else {
            # New transaction created, now relay
            if (!t_relay()) {
                sl_send_reply(500, "Internal Server Error");
                exit;
            }
        }
    }
}
```

**Note:** `t_newtran()` may not be the right approach. The better solution is to ensure BYE requests always match existing dialogs through `loose_route()`.

## Verification Steps

### 1. Check Current Dialog States

```sql
SELECT 
    state,
    COUNT(*) as count,
    CASE state
        WHEN 1 THEN 'Unconfirmed'
        WHEN 2 THEN 'Early'
        WHEN 3 THEN 'Confirmed'
        WHEN 4 THEN 'Established'
        WHEN 5 THEN 'Ended'
        ELSE 'Unknown'
    END as state_name
FROM dialog
GROUP BY state
ORDER BY state;
```

### 2. Check for Stuck Dialogs (State 4 but Old)

```sql
SELECT 
    dlg_id,
    callid,
    from_uri,
    to_uri,
    state,
    start_time,
    FROM_UNIXTIME(start_time) as start_datetime,
    TIMESTAMPDIFF(SECOND, FROM_UNIXTIME(start_time), NOW()) as age_seconds
FROM dialog
WHERE state = 4
  AND start_time < UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 HOUR))
ORDER BY start_time DESC;
```

This shows dialogs that have been in state 4 for more than 1 hour (likely ended calls that didn't transition to state 5).

### 3. Monitor Dialog State Transitions

Enable verbose logging to see state transitions:

```bash
# In opensips.cfg, add logging around dialog operations
xlog("L_INFO", "Dialog state for Call-ID=$hdr(Call-ID): $dlg_status\n");
```

Or check OpenSIPS logs:

```bash
sudo journalctl -u opensips -f | grep -iE "(dialog|bye|state)"
```

### 4. Use OpenSIPS MI to Check Active Dialogs

```bash
opensipsctl fifo dlg_list
# OR
opensips-cli -x mi dlg_list
```

This shows in-memory dialog state (may differ from database if using `db_mode=2`).

## Database Sync Considerations

Your configuration uses `db_mode=2` (cached DB mode):

```opensips
modparam("dialog", "db_mode", 2)
modparam("dialog", "db_update_period", 10)
```

**What this means:**
- Dialogs are primarily stored in memory
- Database is updated every 10 seconds (`db_update_period`)
- State in database may lag behind actual state by up to 10 seconds

**Implications:**
- If a call ends, state may take up to 10 seconds to update in database
- For real-time monitoring, check in-memory state via MI commands
- Database state is eventually consistent

## Recommendations

1. **If State 4 is correct for running calls:** ✅ No action needed
   - State 4 = Established is the expected state for active calls

2. **If State 4 persists after calls end:**
   - Verify BYE requests are being received and processed
   - Ensure BYE goes through `t_relay()` when possible (not just `forward()`)
   - Check that `loose_route()` works correctly for BYE
   - Monitor dialog state transitions in logs

3. **For better state tracking:**
   - Consider reducing `db_update_period` if you need more real-time database updates
   - Use MI commands for real-time dialog state monitoring
   - Add explicit logging around BYE processing

## Testing

To verify dialog state transitions work correctly:

1. **Make a test call:**
   ```bash
   # Monitor dialog state during call
   watch -n 1 'mysql -u opensips -p opensips -e "SELECT dlg_id, callid, state, FROM_UNIXTIME(start_time) as start FROM dialog ORDER BY start_time DESC LIMIT 5;"'
   ```

2. **Check state progression:**
   - Initial INVITE: Should see state 1 or 2
   - Call answered: Should see state 3, then 4
   - Call active: Should remain at state 4
   - Call ends: Should transition to state 5

3. **Verify BYE processing:**
   ```bash
   # Check OpenSIPS logs for BYE
   sudo journalctl -u opensips -f | grep -i bye
   ```

## Related Documentation

- [OpenSIPS Dialog Module Documentation](https://opensips.org/docs/modules/3.4.x/dialog.html)
- [CDR Verification Checklist](../workingdocs/CDR-VERIFICATION-CHECKLIST.md)
- [BYE Fix Documentation](../workingdocs/SESSION-SUMMARY-BYE-FIX.md)
