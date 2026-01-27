# Session Summary: REGISTER Authentication Issue - Authorization Header Not Reaching Asterisk

## Current Status: IN PROGRESS - Investigating Why 40005 Fails While 40004 Succeeds

**Date**: 2026-01-27  
**Issue**: Endpoint 40005 cannot register - Asterisk never receives REGISTER requests with Authorization headers, even though OpenSIPS detects them.

## Problem Statement

1. **40004 Successfully Registers**: Has location record, can receive OPTIONS/NOTIFY from Asterisk
2. **40005 Fails to Register**: No location record, consistently gets 401 from Asterisk
3. **Key Observation**: SIP trace shows Asterisk receives REGISTER requests **WITHOUT Authorization headers**, even though OpenSIPS logs show "Authorization header present"

## Root Cause Analysis

### Evidence from SIP Trace
- OpenSIPS logs show: `"REGISTER: Authorization header present - retry with credentials detected"`
- Asterisk trace shows: REGISTER requests arrive **WITHOUT Authorization header**
- Conclusion: OpenSIPS is detecting the Authorization header but **not forwarding it** to Asterisk

### Hypothesis
When `t_newtran()` fails (transaction exists), `t_relay()` matches the old transaction and uses the **cached original request** (without Authorization) instead of the **current request** (with Authorization).

**The difference between 40004 and 40005:**
- **40004**: `t_newtran()` succeeds → new transaction → `t_relay()` uses current request (with Authorization) → works ✅
- **40005**: `t_newtran()` fails → transaction exists → `t_relay()` matches old transaction → uses cached request (without Authorization) → fails ❌

## What We've Done

### 1. Removed Stateless Forward() Special Case
- **Location**: `config/opensips.cfg.template` lines ~1032-1053
- **Change**: Removed stateless `forward()` for REGISTER with Authorization headers
- **Reason**: Stateless forwarding breaks reply handling - can't save location records on 200 OK
- **Result**: All REGISTER requests now use `t_relay()` (transactional relay)

### 2. Added Transaction Existence Detection
- **Location**: `config/opensips.cfg.template` lines ~1095-1105
- **Change**: Added logging to detect when transaction exists for REGISTER with Authorization
- **Purpose**: Identify when `t_relay()` might use cached request instead of current request

### 3. Added Authorization Header Logging
- **Location**: `config/opensips.cfg.template` lines ~1081-1092
- **Change**: Added detailed logging of Authorization header when forwarding to Asterisk
- **Purpose**: Verify Authorization header is present before `t_relay()` call

### 4. Enhanced Transaction Creation Logging
- **Location**: `config/opensips.cfg.template` lines ~628-647
- **Change**: Added detailed logging when `t_newtran()` fails and transaction exists
- **Purpose**: Track when transaction reuse might occur

## Current Code State

### REGISTER Handling (lines ~613-706)
- Calls `t_newtran()` early to force new transaction creation
- Detects Authorization header presence
- Logs warnings when transaction exists but Authorization header present
- Sets up `t_on_reply("handle_reply_reg")` for location record saving

### TO_DISPATCHER Route (lines ~1016-1105)
- Stores Authorization header in AVP (attempted workaround - may not help)
- Logs Authorization header details before `t_relay()`
- Checks if transaction exists for REGISTER with Authorization
- Logs critical error if transaction exists (indicates `t_relay()` will use cached request)
- Calls `t_relay()` for all REGISTER requests

## Next Steps

1. **Verify Hypothesis**: Check logs to confirm:
   - Does 40004 show "Forced new transaction creation"?
   - Does 40005 show "t_newtran() failed" or "Transaction exists for REGISTER with Authorization"?
   - Does 40005 show "CRITICAL - Transaction exists for REGISTER with Authorization"?

2. **If Hypothesis Confirmed**: Need to find a way to force `t_relay()` to use current request instead of cached request when:
   - Transaction exists (from previous REGISTER attempt)
   - Current request has Authorization header
   - Cached request doesn't have Authorization header

3. **Potential Solutions** (to investigate):
   - Check if OpenSIPS has a way to update/refresh transaction with new request
   - Check if we can modify the request before `t_relay()` to ensure Authorization is preserved
   - Check if we can force transaction expiration or deletion before `t_relay()`
   - Check if there's a way to prevent transaction matching when Authorization header is present

## Key Files Modified

- `config/opensips.cfg.template`: REGISTER handling and transaction management

## Key Learnings

1. **Transaction Reuse Issue**: When `t_newtran()` fails, `t_relay()` may match old transaction and use cached request
2. **Stateless Forwarding Trade-off**: Stateless `forward()` bypasses transaction matching but breaks reply handling
3. **Authorization Header Preservation**: OpenSIPS may not preserve Authorization header when reusing cached transaction
4. **Timing Matters**: Success/failure may depend on transaction expiration timing

## Questions to Answer

1. Why does `t_newtran()` succeed for 40004 but fail for 40005?
2. Is there a timing difference (transaction expiration)?
3. Is there a Call-ID/CSeq difference that affects transaction matching?
4. Can we force `t_relay()` to use current request even when transaction exists?
5. Is there an OpenSIPS parameter or function to prevent transaction reuse for REGISTER with Authorization?

## Related Documentation

- `workingdocs/SESSION-SUMMARY-RECEIVED-URI-FORMAT.md`: Previous session on `received` field format
- OpenSIPS transaction module documentation: https://opensips.org/html/docs/modules/3.6.x/tm.html
