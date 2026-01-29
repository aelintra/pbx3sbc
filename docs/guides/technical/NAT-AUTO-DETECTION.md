# NAT Environment Auto-Detection

## Overview

OpenSIPS configuration now automatically detects whether endpoints are behind NAT and enables NAT fixing functions accordingly. This eliminates the need for manual configuration when deploying in different network environments (LAN vs NAT).

## How It Works

### Runtime Detection

The system uses runtime detection based on the actual IP addresses endpoints send in their SIP requests:

1. **Private IP Detection**: When OpenSIPS receives a request from an endpoint, it checks if the source IP (`$si`) is a private IP address (RFC 1918).

2. **Asterisk Exclusion**: The detection excludes Asterisk backends (dispatcher destinations) since they're not behind NAT.

3. **Automatic NAT Fixes**: If an endpoint is detected as being behind NAT (sending private IPs), NAT fixing functions are automatically enabled for that request.

### Detection Logic

The `route[CHECK_NAT_ENVIRONMENT]` route:
- Checks if source IP is private using `route[CHECK_PRIVATE_IP]`
- Excludes Asterisk backends using `route[CHECK_IS_FROM_ASTERISK]`
- Sets `$var(enable_nat_fixes) = 1` if endpoint is behind NAT

### NAT Fixes Enabled

When NAT is detected, the following functions are automatically enabled:

1. **INVITE SDP Fixing** (`fix_nated_sdp("rewrite-media-ip")`):
   - Fixes private IPs in SDP `c=` line to public NAT IPs
   - Ensures Asterisk receives correct IP for RTP

2. **Response SDP Fixing** (`fix_nated_sdp("rewrite-media-ip")`):
   - Fixes private IPs in response SDP
   - Ensures Asterisk receives public NAT IPs from endpoints

3. **Response Contact Fixing** (`fix_nated_contact()`):
   - Fixes Contact headers in responses
   - Excludes REGISTER responses (preserved for `save()`)

4. **REGISTER NAT Fixing** (`fix_nated_register()`):
   - Always enabled (needed for proper Contact header handling)
   - Updates Contact header with public IP if behind NAT

## Benefits

### Automatic Adaptation
- **No Manual Configuration**: Works automatically in both LAN and NAT environments
- **Per-Request Detection**: Adapts to each endpoint's individual situation
- **Zero Configuration**: No need to manually enable/disable NAT fixes

### Environment Support

#### LAN Environment
- Endpoints send public IPs (same network)
- NAT fixes automatically disabled
- No performance overhead
- Works exactly as before

#### NAT Environment
- Endpoints send private IPs (behind NAT)
- NAT fixes automatically enabled
- SDP and Contact headers fixed automatically
- RTP works correctly

### Reliability
- **Runtime Detection**: Based on actual IPs endpoints send, not configuration
- **More Accurate**: Detects NAT per-endpoint, not globally
- **Handles Mixed Environments**: Some endpoints on LAN, some behind NAT

## Implementation Details

### Code Changes

1. **New Route**: `route[CHECK_NAT_ENVIRONMENT]`
   - Detects if endpoint is behind NAT
   - Sets `$var(enable_nat_fixes)` flag

2. **Conditional NAT Fixes**:
   - INVITE SDP fixing: Enabled if `$var(enable_nat_fixes) == 1`
   - Response SDP/Contact fixing: Enabled if `$var(enable_nat_fixes) == 1`
   - REGISTER NAT fixing: Always enabled (unconditional)

3. **Helper Routes**:
   - `route[CHECK_PRIVATE_IP]`: Checks if IP is RFC 1918 private
   - `route[CHECK_IS_FROM_ASTERISK]`: Checks if source is Asterisk backend

### Detection Flow

```
Request arrives from endpoint
    ↓
Check if source IP is private (RFC 1918)
    ↓
Check if source is Asterisk (dispatcher destination)
    ↓
If private IP AND not Asterisk:
    → Enable NAT fixes for this request
Else:
    → Disable NAT fixes (LAN environment)
```

## Testing

### LAN Environment Test
1. Deploy OpenSIPS on same network as endpoints
2. Endpoints send public IPs in SIP requests
3. Verify NAT fixes are NOT applied
4. Verify audio works correctly

### NAT Environment Test
1. Deploy OpenSIPS with endpoints behind NAT
2. Endpoints send private IPs in SIP requests
3. Verify NAT fixes ARE applied (check logs)
4. Verify SDP contains public IPs after fixing
5. Verify audio works correctly

### Mixed Environment Test
1. Some endpoints on LAN, some behind NAT
2. Verify NAT fixes applied only to NAT endpoints
3. Verify all endpoints can make calls successfully

## Logging

The system logs NAT detection and fixing:

```
NAT environment detected: endpoint 192.168.1.138 is behind NAT, enabling NAT fixes
RELAY: Fixed NAT in SDP for INVITE from 192.168.1.138 to sip:192.168.1.109...
Fixed NAT in SDP for response 200 from endpoint 192.168.1.138
```

## Configuration

No configuration needed! The system auto-detects the environment.

### Manual Override (if needed)

If you need to force NAT fixes on/off, you can modify `route[CHECK_NAT_ENVIRONMENT]`:

```opensips
route[CHECK_NAT_ENVIRONMENT] {
    # Force enable NAT fixes (uncomment to enable):
    # $var(enable_nat_fixes) = 1;
    # return;
    
    # Force disable NAT fixes (uncomment to disable):
    # $var(enable_nat_fixes) = 0;
    # return;
    
    # ... existing auto-detection code ...
}
```

## Related Files

- `config/opensips.cfg.template`: Main configuration file
  - `route[CHECK_NAT_ENVIRONMENT]`: NAT detection logic
  - `route[CHECK_PRIVATE_IP]`: Private IP detection
  - `route[CHECK_IS_FROM_ASTERISK]`: Asterisk detection
  - `route[RELAY]`: INVITE SDP fixing
  - `onreply_route`: Response SDP/Contact fixing

## Date

Implemented: January 21, 2026
