# Asterisk NAT Configuration with OpenSIPS Proxy

## Problem
- `nat=no` works for local network testing but won't work in real-world deployments with phones behind NAT
- With `nat=yes` or `nat=force_rport,comedia`, we get one-way audio issues
- The issue is that Asterisk is rewriting SDP incorrectly when OpenSIPS is in the path

## Root Cause
When OpenSIPS acts as a proxy:
- OpenSIPS handles routing and NAT traversal to endpoints
- Asterisk sees OpenSIPS as the source, not the actual endpoints
- With aggressive NAT settings, Asterisk rewrites SDP using OpenSIPS's IP or its own IP
- This breaks RTP routing because endpoints expect their own IPs in SDP

## Recommended Solutions

### Option 1: Use `nat=force_rport` (Recommended)
**Location:** `sip.conf` or `pjsip.conf` in `[general]` section

```ini
[general]
nat=force_rport
externip=your.public.ip.address  # Only if Asterisk is behind NAT
localnet=192.168.1.0/255.255.255.0  # Your local network
```

**Why this works:**
- `force_rport` handles SIP NAT (responds to source IP/port)
- Does NOT rewrite RTP addresses in SDP (no `comedia`)
- Lets OpenSIPS handle RTP routing correctly
- Works with endpoints behind NAT

**What it does:**
- Forces Asterisk to respond to the source IP/port (handles SIP NAT)
- Does NOT modify SDP connection addresses (preserves endpoint IPs)
- OpenSIPS can then route RTP correctly

### Option 2: Use `nat=route`
**Location:** `sip.conf` or `pjsip.conf` in `[general]` section

```ini
[general]
nat=route
externip=your.public.ip.address
localnet=192.168.1.0/255.255.255.0
```

**Why this works:**
- Assumes NAT is present but doesn't send rport parameter
- Less aggressive than `nat=yes`
- May work better with some proxy configurations

### Option 3: Per-Peer NAT Settings
**Location:** Individual peer/endpoint definitions

Instead of global `nat=yes`, set NAT per peer:

```ini
[peer]
type=peer
host=dynamic
nat=force_rport  # Per-peer setting
directmedia=no
```

**Why this works:**
- More granular control
- Can have different settings for different scenarios
- Global setting can be `nat=no`, with peers that need it set individually

### Option 4: Configure `localnet` Properly
**Location:** `sip.conf` or `pjsip.conf` in `[general]` section

```ini
[general]
nat=force_rport
localnet=192.168.1.0/255.255.255.0  # Your local network
localnet=10.0.0.0/255.0.0.0         # Additional local networks if needed
```

**Why this works:**
- Helps Asterisk identify which IPs are local vs remote
- Prevents incorrect SDP rewriting for local endpoints
- Important when OpenSIPS and endpoints are on same network

## What NOT to Use

### ❌ `nat=yes`
- Too aggressive - rewrites SDP connection addresses
- Breaks RTP routing when proxy is in path
- Causes one-way audio issues

### ❌ `nat=force_rport,comedia`
- `comedia` rewrites RTP addresses in SDP
- Breaks when proxy handles RTP routing
- Causes same issues as `nat=yes`

### ❌ `nat=no` (for production)
- Only works when no NAT is involved
- Won't work with phones behind NAT
- Not suitable for real-world deployments

## Testing Steps

1. **Start with `nat=force_rport`:**
   ```ini
   [general]
   nat=force_rport
   localnet=192.168.1.0/255.255.255.0
   ```

2. **Test both directions:**
   - Snom → Yealink
   - Yealink → Snom

3. **If issues persist, try `nat=route`:**
   ```ini
   [general]
   nat=route
   localnet=192.168.1.0/255.255.255.0
   ```

4. **Check Asterisk logs:**
   - Look for SDP rewriting
   - Verify RTP is being routed correctly

5. **Monitor with Wireshark:**
   - Check SDP in INVITE and 200 OK
   - Verify RTP source/destination IPs

## Additional Configuration

### Set `externip` Only If Needed
```ini
[general]
externip=203.0.113.1  # Only if Asterisk is behind NAT
```

**When to use:**
- Asterisk is behind NAT
- Asterisk needs to advertise its public IP
- Not needed if Asterisk has public IP or is on same network as OpenSIPS

### Configure `localnet` Correctly
```ini
[general]
localnet=192.168.1.0/255.255.255.0
localnet=10.0.0.0/255.0.0.0
```

**Why important:**
- Helps Asterisk identify local vs remote traffic
- Prevents incorrect NAT handling for local endpoints
- Should include all local network ranges

### Keep `directmedia=no`
```ini
[peer]
directmedia=no
```

**Why:**
- Forces RTP through Asterisk
- Works better with proxy in path
- Already configured correctly

## OpenSIPS Considerations

With OpenSIPS as proxy:
- OpenSIPS handles endpoint routing
- OpenSIPS tracks endpoint locations
- OpenSIPS routes RTP between endpoints
- Asterisk should NOT rewrite SDP addresses

**Key principle:** Let OpenSIPS handle routing, Asterisk should just handle SIP signaling and media relay.

## Recommended Production Configuration

```ini
[general]
; NAT handling - force_rport for SIP NAT, but don't rewrite RTP
nat=force_rport

; Local network definition
localnet=192.168.1.0/255.255.255.0

; External IP (only if Asterisk is behind NAT)
; externip=your.public.ip.address

; RTP settings
rtpstart=10000
rtpend=20000

[peer-template]
type=peer
host=dynamic
directmedia=no
qualify=yes
```

## Troubleshooting

### If `nat=force_rport` doesn't work:
1. Check `localnet` is configured correctly
2. Verify OpenSIPS is routing correctly
3. Try `nat=route` as alternative
4. Check if `externip` is needed

### If still getting one-way audio:
1. Verify `directmedia=no` is set
2. Check OpenSIPS logs for routing issues
3. Use Wireshark to see actual SDP content
4. Verify RTP ports are open in firewall

### If phones behind NAT can't register:
1. Ensure `nat=force_rport` is set (not `nat=no`)
2. Check `qualify=yes` on peers
3. Verify firewall allows SIP and RTP
4. Check OpenSIPS is handling NAT correctly

## Summary

**Best practice for Asterisk behind OpenSIPS proxy:**
- Use `nat=force_rport` (handles SIP NAT, doesn't rewrite RTP)
- Configure `localnet` properly
- Keep `directmedia=no`
- Let OpenSIPS handle endpoint routing and RTP

This configuration:
- ✅ Works with endpoints behind NAT
- ✅ Works with local network endpoints
- ✅ Doesn't break RTP routing through proxy
- ✅ Suitable for production deployments

