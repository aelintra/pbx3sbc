# Snom Phone Audio Troubleshooting Guide

## Issue
One-way audio when Snom (401) calls Yealink (402) through OpenSIPS and Asterisk.
- Yealink → Snom: Works with bi-directional audio ✓
- Snom → Yealink: No audio in either direction ✗

## Snom Phone Settings to Check

### 1. RTP Encryption (SRTP)
**Location:** Setup → Identity 1 → RTP → RTP Encryption
- **Setting:** Set to **OFF**
- **Why:** SRTP can cause compatibility issues with Asterisk/OpenSIPS
- **Note:** This is often enabled by default on Snom phones

### 2. RTP Port Range
**Location:** Setup → Identity 1 → RTP → RTP Port Range
- **Setting:** Ensure it matches Asterisk's RTP port range (typically 10000-20000)
- **Why:** Mismatched port ranges can cause RTP to be blocked or misrouted

### 3. SIP Parameters
**Location:** Setup → Identity 1 → SIP
- **Call Completion:** Set to **OFF**
- **Challenge Response on Phone:** Set to **OFF**
- **Use user=phone:** Set to **OFF**
- **Filter packets from Registrar:** Set to **OFF**
- **Why:** These can interfere with proxy/SBC routing

### 4. ICE (Interactive Connectivity Establishment)
**Location:** Setup → Identity 1 → RTP → ICE
- **Setting:** Try disabling ICE
- **Why:** ICE can interfere with direct RTP when going through a proxy
- **Note:** Some users report this fixes audio issues after hold/transfer

### 5. STUN Settings
**Location:** Setup → Identity 1 → RTP → STUN
- **Setting:** May need to disable if causing issues
- **Why:** STUN can interfere with local network RTP routing

### 6. NAT Settings
**Location:** Setup → Identity 1 → SIP → NAT
- **Setting:** Check NAT mode settings
- **Options:** 
  - **auto** (let phone detect)
  - **off** (for local network)
  - **on** (force NAT mode)
- **Why:** Incorrect NAT settings can cause RTP routing issues

### 7. RTP Mode / Direct RTP
**Location:** Setup → Identity 1 → RTP
- **Setting:** Check if there's a "Direct RTP" or "RTP Mode" setting
- **Why:** May need to force RTP through proxy instead of direct

### 8. SDP Mode
**Location:** Setup → Identity 1 → RTP → SDP Mode (if available)
- **Setting:** Check available options
- **Why:** Some phones have SDP handling modes that affect how they process SDP

### 9. Contact Header Settings
**Location:** Setup → Identity 1 → SIP → Contact
- **Setting:** Check how Contact header is constructed
- **Why:** Contact header affects how RTP is routed

### 10. Firmware Version
**Location:** Setup → System → Firmware
- **Action:** Ensure latest firmware is installed
- **Why:** Firmware updates often fix RTP/SDP handling bugs

## Asterisk Settings to Verify

### 1. Direct Media
**Location:** `sip.conf` or `pjsip.conf` peer/endpoint settings
- **Setting:** `directmedia=no` (already set)
- **Why:** Forces RTP through Asterisk instead of direct between endpoints

### 2. NAT Settings
**Location:** `sip.conf` or `pjsip.conf` peer/endpoint settings
- **Setting:** `nat=force_rport,comedia`
- **Why:** Helps with RTP routing when going through proxy

### 3. RTP Settings
**Location:** `rtp.conf`
- **Setting:** Ensure `rtpstart` and `rtpend` are configured
- **Why:** Defines RTP port range for Asterisk

## Network Considerations

1. **Firewall:** Ensure RTP ports (10000-20000 UDP) are open
2. **VLANs:** If using VLANs, ensure RTP can traverse between them
3. **QoS:** Check if QoS policies are affecting RTP traffic
4. **SIP ALG:** Disable SIP ALG on router if present

## Testing Steps

1. **Check Current Settings:**
   - Access Snom web interface (usually http://phone-ip)
   - Navigate to Setup → Identity 1
   - Document current RTP and SIP settings

2. **Make Changes:**
   - Start with RTP Encryption = OFF
   - Disable ICE if enabled
   - Verify SIP parameters are set as recommended

3. **Test:**
   - Reboot Snom phone after changes
   - Test call from Snom (401) to Yealink (402)
   - Check OpenSIPS logs for SDP details
   - Check Asterisk logs for RTP issues

4. **Monitor:**
   - Use Wireshark to capture RTP traffic
   - Verify RTP is being sent to correct IP addresses
   - Check if RTP is reaching both endpoints

## Key Differences: Why Yealink Works But Snom Doesn't

Possible reasons:
1. **Default Settings:** Snom may have different default RTP/SDP settings
2. **SDP Handling:** Snom may handle SDP differently when receiving INVITE from Asterisk
3. **RTP Behavior:** Snom may be more strict about RTP source IP matching SDP
4. **Firmware:** Snom firmware version may have specific behavior

## References

- Snom Asterisk Configuration Guide: https://service.snom.com/spaces/wiki/pages/234333759/Basic+Information+-+Asterisk+PBX
- Snom RTP Configuration: Setup → Identity 1 → RTP in web interface
- Asterisk RTP Configuration: `rtp.conf` and peer settings

## Next Steps

1. Check Snom web interface for current settings
2. Compare with recommended settings above
3. Make changes one at a time and test
4. Document which setting fixes the issue

