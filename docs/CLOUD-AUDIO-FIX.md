# Cloud Environment Audio Fix - Snom to Yealink

## Problem
When calling from Snom (40004) to Yealink (40005), there is no audio in either direction.
When calling from Yealink (40005) to Snom (40004), audio works correctly.

## Root Cause Analysis

Comparing the two call traces reveals the issue:

### Failing Call (Snom→Yealink):
1. **Snom sends correct SDP:**
   - `c=IN IP4 74.83.23.44` (Snom's NAT public IP)
   - `m=audio 60010`

2. **Asterisk rewrites SDP incorrectly:**
   - To Yealink: `c=IN IP4 3.93.253.1` (Asterisk's public IP) ❌
   - To Snom (200 OK): `c=IN IP4 3.93.253.1` (Asterisk's public IP) ❌

3. **Yealink sends correct SDP:**
   - `c=IN IP4 74.83.23.44` (Yealink's NAT public IP)
   - `m=audio 12262`

4. **Result:**
   - Both phones send RTP to `3.93.253.1` (Asterisk)
   - Asterisk doesn't relay RTP
   - No audio flows: Snom sent 61 packets, received 0

### Working Call (Yealink→Snom):
1. **Yealink sends correct SDP:**
   - `c=IN IP4 74.83.23.44` (Yealink's NAT public IP)
   - `m=audio 12264`

2. **Asterisk rewrites SDP (same issue):**
   - To Snom: `c=IN IP4 3.93.253.1` (Asterisk's public IP) ❌
   - To Yealink (200 OK): `c=IN IP4 3.93.253.1` (Asterisk's public IP) ❌

3. **Snom sends correct SDP:**
   - `c=IN IP4 74.83.23.44` (Snom's NAT public IP)
   - `m=audio 53726`

4. **Result:**
   - **BUT audio works!** Snom received 191 packets, sent 183 packets ✅

### Key Difference:
Both calls have the same SDP rewriting issue, but **Yealink→Snom works while Snom→Yealink doesn't**. This suggests:
- The phones handle the incorrect SDP differently
- Yealink may be more tolerant of Asterisk's IP in SDP
- Snom may strictly follow the SDP and fail when it doesn't match
- There may be a codec negotiation difference

## Solution

### ✅ Confirmed Working Solution: Use `nat=route`

**Asterisk Configuration:**

In `sip.conf` or `pjsip.conf`:

```ini
[general]
nat=route
localnet=172.31.0.0/255.255.0.0
```

**Why this works:**
- `nat=route` is less aggressive than `nat=force_rport`
- Preserves endpoint IPs in SDP better
- Allows direct RTP between phones behind NAT
- Works with OpenSIPS proxy in the path

**Result:**
- Audio flows correctly in both directions
- SDP contains correct endpoint IPs (`74.83.23.44`)
- Direct RTP established between phones

## Verification

After changing Asterisk configuration:

1. Restart Asterisk: `systemctl restart asterisk`
2. Make test call from Snom to Yealink
3. Check RTP statistics in BYE message:
   - Should show packets received: `RTP-RxStat: Total_Rx_Pkts>0`
   - Should show packets sent: `RTP-TxStat: Total_Tx_Pkts>0`

## Expected SDP After Fix

**With `directmedia=yes`, Asterisk should:**
1. Initially send SDP with its own IP (for negotiation)
2. After call setup, update SDP with endpoint IPs via re-INVITE
3. Or preserve endpoint IPs from the start if configured correctly

**Ideal SDP:**
- To Yealink: `c=IN IP4 74.83.23.44` (Snom's IP) ✅
- To Snom: `c=IN IP4 74.83.23.44` (Yealink's IP) ✅

This allows direct RTP between phones through NAT.

## Why One Direction Works

The fact that **Yealink→Snom works** but **Snom→Yealink doesn't** suggests:
- **Yealink is more tolerant** of incorrect SDP and may use Contact header or other information
- **Snom strictly follows SDP** and fails when SDP points to wrong IP
- There may be a **codec negotiation difference** (Yealink offers G722, Snom doesn't in initial INVITE)
- **RTP port handling** may differ between phones

The root cause is still Asterisk rewriting SDP, but the phones handle it differently.

## Additional Issue: 32-Second Call Termination (Resolved)

### Problem
Calls were terminating at exactly 32 seconds due to a missed ACK that the Snom phone was expecting.

### Root Cause
- Snom sends 200 OK response and expects ACK
- If ACK doesn't arrive, Snom retransmits 200 OK
- After 32 seconds (SIP transaction timeout = 64 * T1), Snom gives up and terminates the call
- This was likely caused by ACK not being properly forwarded by OpenSIPS

### Resolution
**The `nat=route` configuration change appears to have resolved this issue.** The ACK handling is now working correctly with the new NAT setting.

**Note:** If this issue returns during further testing, explicit ACK handling may need to be added to the `route[WITHINDLG]` section in OpenSIPS configuration.

## Network Considerations

Since both phones are behind the same NAT (`74.83.23.44`), they should be able to establish direct RTP. The NAT should handle hairpinning (internal-to-internal traffic).

If direct RTP still fails due to NAT, consider:
- Enabling SIP ALG on NAT router
- Using STUN on phones
- Configuring Asterisk to relay RTP (not ideal for performance)

