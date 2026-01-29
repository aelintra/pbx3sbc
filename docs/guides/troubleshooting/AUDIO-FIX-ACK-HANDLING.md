# Audio Issue Fix: ACK Handling and NAT Extraction

## Issue Summary

After a fresh install, calls were established successfully but **no audio was flowing between endpoints**. SIP signaling was working correctly (INVITE, 200 OK, etc.), but RTP packets were not being exchanged properly.

## Initial Symptoms

1. **SIP signaling worked**: INVITE, 200 OK, ACK messages were exchanged successfully
2. **RTP trace showed one-way audio**: 
   - Snom (192.168.1.138) → Asterisk (192.168.1.109): ✅ Packets flowing
   - Asterisk (192.168.1.109) → Yealink (192.168.1.232): ✅ Packets flowing
   - **Missing**: Yealink → Asterisk and Asterisk → Snom (reverse direction)
3. **Yealink kept retransmitting 200 OK**: Indicated it never received the ACK from Asterisk

## Erroneous Initial Suspicions

### Why Asterisk Was Suspected

1. **RTP trace pattern**: The RTP trace showed packets flowing FROM endpoints TO Asterisk, but not FROM Asterisk TO endpoints. This pattern suggested Asterisk might not be sending RTP back.

2. **Asterisk configuration changes**: The user mentioned trying various Asterisk NAT settings (`rtp_symmetric`, `force_rport`, `direct_media`) which didn't fix the issue, suggesting Asterisk configuration might be the problem.

3. **SDP in responses**: The SIP trace showed Asterisk sending SDP with its own IP address in 200 OK responses, which is correct for `direct_media=no`, but we initially thought OpenSIPS might be incorrectly modifying this SDP.

4. **NAT handling assumptions**: We initially thought OpenSIPS's NAT fixing functions (`fix_nated_sdp()`) might be incorrectly modifying Asterisk's SDP, even though all devices were on the same LAN.

### Why This Was Wrong

1. **Asterisk hadn't changed**: The user confirmed Asterisk was working yesterday with the same configuration, and only OpenSIPS implementation had changed.

2. **ACK retransmission loop**: The real issue was revealed when examining the SIP trace from Asterisk's perspective - Asterisk was sending ACKs to OpenSIPS, but OpenSIPS was **not forwarding them** to the Yealink endpoint.

3. **OpenSIPS logs revealed the truth**: The logs showed:
   - ACKs from Asterisk were being received by OpenSIPS
   - OpenSIPS was attempting to forward them but failing with `bad host in uri` errors
   - The destination URI was being corrupted to `sip:1001@:` (invalid format)

## Root Cause Analysis

### The Real Problem

The issue was **not** with RTP or Asterisk, but with **SIP ACK handling in OpenSIPS**:

1. **ACK forwarding failure**: When Asterisk sent ACKs to OpenSIPS (following the Record-Route header), OpenSIPS attempted to forward them to the Yealink endpoint but failed.

2. **NAT extraction corruption**: The NAT IP extraction code in `route[RELAY]` was running for ACKs from Asterisk and corrupting the destination URI:
   - Original Request-URI: `sip:1001@192.168.1.232:5060` ✅ (correct)
   - After NAT extraction: `sip:1001@:` ❌ (invalid - missing host/IP)

3. **Why NAT extraction ran**: The code checked if ACK had a username in Request-URI (`sip:[^@]+@`) but didn't exclude ACKs from Asterisk, which already had correct IPs.

4. **Why it corrupted**: The NAT extraction regex patterns failed to extract a valid IP from the location table contact field, resulting in an empty IP but still constructing a URI with `sip:user@:` format.

### Impact

- **Yealink never received ACK**: Without the ACK, Yealink kept retransmitting 200 OK
- **Call appeared established**: SIP signaling completed, but endpoints didn't know the call was fully established
- **RTP didn't start properly**: Endpoints may have been waiting for proper call establishment before starting RTP

## The Fix

### Changes Made

1. **Prevented NAT extraction for ACKs from Asterisk** (`config/opensips.cfg.template`):
   ```opensips
   # For ACK/PRACK, require username in Request-URI (ACKs to Asterisk have no username)
   # CRITICAL: Do NOT run NAT extraction for ACKs from Asterisk - Request-URI already has correct IP
   # NAT extraction can corrupt $du and create invalid URIs like sip:1001@:
   if (is_method("ACK|PRACK")) {
       # Only run NAT extraction for ACKs from endpoints (not from Asterisk)
       # ACKs from Asterisk already have correct IP in Request-URI and should use it directly
       if ($ru =~ "^sip:[^@]+@" && $si !~ "^192\\.168\\.1\\.109") {
           $var(needs_nat_fix) = 1;
       }
   }
   ```

2. **Added validation to NAT extraction**:
   - Validates extracted IP is not empty
   - Validates IP format matches IPv4 pattern
   - Only sets `$du` if extraction succeeds
   - Logs warnings if extraction fails instead of corrupting `$du`

3. **Fixed database query error**:
   - Removed `enabled=1` check from domain query (column doesn't exist)
   - Query: `SELECT domain FROM domain WHERE setid='...' LIMIT 1`

4. **Added explicit exit after ACK handling**:
   - Ensures ACK forwarding completes before any other processing
   - Prevents further code execution that might interfere

### Why This Fixed It

1. **ACKs now reach endpoints**: By skipping NAT extraction for ACKs from Asterisk, the original Request-URI (`sip:1001@192.168.1.232:5060`) is preserved and used directly.

2. **Stateless forwarding works**: ACKs from Asterisk use `forward()` (stateless) instead of `t_relay()` (transaction-based), ensuring delivery even if transaction matching fails.

3. **No URI corruption**: Validation prevents invalid URIs from being created, and skipping NAT extraction for ACKs from Asterisk eliminates the corruption path entirely.

## Lessons Learned

1. **ALWAYS check logs first**: The OpenSIPS logs immediately showed the problem (`bad host in uri`, `ACK from Asterisk - forward() failed`). This should have been the first step before suspecting Asterisk or making configuration changes.

2. **Don't assume the obvious**: RTP one-way audio pattern suggested Asterisk, but the real issue was SIP ACK handling preventing proper call establishment.

3. **Check the full SIP flow**: Examining the trace from Asterisk's perspective revealed ACKs weren't being forwarded, which was the root cause.

4. **Logs are critical**: OpenSIPS logs showing `bad host in uri` errors pointed directly to the URI corruption issue. The logs contained all the information needed to diagnose the problem.

5. **NAT extraction should be selective**: Not all requests need NAT extraction - ACKs from Asterisk already have correct IPs in Request-URI.

6. **Validate before setting**: Always validate extracted values before using them to construct URIs or set variables.

## Testing

After the fix:
- ✅ ACKs are forwarded correctly from Asterisk to endpoints
- ✅ Endpoints receive ACKs and stop retransmitting 200 OK
- ✅ RTP flows bidirectionally
- ✅ Audio works in both directions

## Related Files

- `config/opensips.cfg.template`: Main OpenSIPS configuration
  - `route[WITHINDLG]`: ACK handling with `loose_route()`
  - `route[RELAY]`: ACK forwarding and NAT extraction logic

## Date

Fixed: January 21, 2026
