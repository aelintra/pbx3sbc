# Why Rport Matters: Understanding RFC 3581 and NAT Traversal

## Problem Summary

When phone 40005 had Rport **disabled**, it failed to register. When Rport was **enabled** (like phone 40004), registration succeeded. This document explains why.

## What is Rport?

**Rport** (Return Port) is a SIP extension defined in **RFC 3581** that solves a critical NAT traversal problem:

- **Without Rport**: The phone advertises a port in the Via header, but NAT may map it to a different external port. Responses sent to the advertised port don't reach the phone.
- **With Rport**: The phone includes `rport` in the Via header, telling the server "send responses to the IP:port you actually received this request from" (the NAT public IP:port).

## How OpenSIPS Uses Rport

### 1. `fix_nated_register()` Function

When OpenSIPS calls `fix_nated_register()` during REGISTER processing:

```opensips
fix_nated_register();
```

This function:
1. **Reads the Via header** to extract source IP:port information
2. **Checks for `rport` parameter** - if present, uses the actual source IP:port from where OpenSIPS received the request
3. **Populates `$avp(reg_received)`** with the NAT public IP:port (e.g., `74.83.23.44:5060`)
4. **Fixes the Contact header** with the public IP if behind NAT

### 2. What Happens Without Rport

**Scenario: Phone 40005 (Rport disabled)**

1. Phone sends REGISTER from internal port `5060` (private IP `192.168.1.100`)
2. NAT router maps it to external port `52341` (public IP `74.83.23.44`)
3. Via header shows: `Via: SIP/2.0/UDP 192.168.1.100:5060` (no `rport` parameter)
4. OpenSIPS receives request from `74.83.23.44:52341` (actual source)
5. **Problem**: `fix_nated_register()` may try to use the port from Via header (`5060`) instead of actual source port (`52341`)
6. OpenSIPS sends 401 challenge to `74.83.23.44:5060` (wrong port!)
7. NAT router doesn't have a mapping for port `5060` → **401 response is lost**
8. Phone never receives 401 → **registration fails**

**Scenario: Phone 40004 (Rport enabled)**

1. Phone sends REGISTER from internal port `5060` (private IP `192.168.1.99`)
2. NAT router maps it to external port `52340` (public IP `74.83.23.44`)
3. Via header shows: `Via: SIP/2.0/UDP 192.168.1.99:5060;rport` (with `rport` parameter)
4. OpenSIPS receives request from `74.83.23.44:52340` (actual source)
5. **Solution**: `fix_nated_register()` sees `rport` parameter → uses actual source IP:port (`74.83.23.44:52340`)
6. OpenSIPS sends 401 challenge to `74.83.23.44:52340` (correct port!)
7. NAT router forwards response to phone → **401 response reaches phone**
8. Phone retries with Authorization header → **registration succeeds**

## Technical Details

### How `fix_nated_register()` Works

The OpenSIPS `nathelper` module's `fix_nated_register()` function:

1. **Checks Via header** for `received` and `rport` parameters
2. **If `rport` is present**: Uses the actual source IP:port from the socket (`$si:$sp`)
3. **If `rport` is missing**: May fall back to port from Via header (which may be wrong for NAT)
4. **Populates `received_avp`**: Stores the correct NAT public IP:port for later use

### Configuration in Your Setup

Your configuration uses:

```opensips
# nathelper module
modparam("nathelper", "received_avp", "$avp(reg_received)")

# REGISTER handling
fix_nated_register();
```

This populates `$avp(reg_received)` with the NAT public IP:port, which is then:
- Converted to SIP URI format: `sip:74.83.23.44:52340;transport=udp`
- Stored in the `received` field of the `location` table
- Used for routing responses back to the phone (OPTIONS, NOTIFY, INVITE)

### Why Both Phones Need Rport

Both phones are behind the same NAT router, so both need Rport enabled because:

1. **NAT port mapping is dynamic** - Each phone gets a different external port
2. **Responses must use correct port** - The 401 challenge and subsequent responses must go to the actual NAT-mapped port
3. **Consistent behavior** - With Rport enabled, OpenSIPS always uses the actual source IP:port, ensuring reliable NAT traversal

## Impact on Registration Flow

### Registration Flow WITH Rport (Working)

```
Phone (192.168.1.100:5060)
  ↓ REGISTER (Via: ...;rport)
NAT Router
  ↓ Maps to 74.83.23.44:52341
OpenSIPS
  ↓ Receives from 74.83.23.44:52341
  ↓ fix_nated_register() sees rport → uses 74.83.23.44:52341
  ↓ Forwards to Asterisk
Asterisk
  ↓ Sends 401 Unauthorized
OpenSIPS
  ↓ Routes 401 to 74.83.23.44:52341 (correct port!)
NAT Router
  ↓ Forwards to 192.168.1.100:5060
Phone
  ↓ Receives 401, retries with Authorization
  ↓ Registration succeeds ✅
```

### Registration Flow WITHOUT Rport (Failing)

```
Phone (192.168.1.100:5060)
  ↓ REGISTER (Via: ...5060, no rport)
NAT Router
  ↓ Maps to 74.83.23.44:52341
OpenSIPS
  ↓ Receives from 74.83.23.44:52341
  ↓ fix_nated_register() doesn't see rport → may use Via port (5060)
  ↓ Forwards to Asterisk
Asterisk
  ↓ Sends 401 Unauthorized
OpenSIPS
  ↓ Routes 401 to 74.83.23.44:5060 (WRONG PORT!)
NAT Router
  ↓ No mapping for port 5060 → DROPS packet
Phone
  ↓ Never receives 401
  ↓ Registration fails ❌
```

## Best Practice Recommendation

**Enable Rport on all phones behind NAT**:

1. **RFC 3581 Compliance**: Rport is the standard way to handle NAT traversal
2. **Reliability**: Ensures responses always reach the phone
3. **Consistency**: Works the same way for all phones regardless of NAT port mapping
4. **Future-proof**: Required for proper SIP operation in NAT environments

## Configuration

### Yealink Phone Settings

**Location**: Account > Register settings

- **Rport**: Enable (or set to `rport=1` or `rport=2` depending on model)
- **NAT**: Enable (if available)

### OpenSIPS Configuration

Your current configuration already handles Rport correctly:

- `fix_nated_register()` automatically detects and uses `rport` parameter
- `received_avp` stores the correct NAT IP:port
- Responses are routed using the `received` field from location table

**No changes needed** - OpenSIPS already supports Rport correctly!

## Related Documentation

- **RFC 3581**: "An Extension to the Session Initiation Protocol (SIP) for Symmetric Response Routing"
- **OpenSIPS nathelper module**: Handles NAT traversal including Rport support
- **NAT-AUTO-DETECTION.md**: Your NAT environment auto-detection implementation
- **docs/ASTERISK-NAT-WITH-PROXY.md**: NAT configuration for Asterisk with OpenSIPS proxy

## Summary

**Rport enables RFC 3581 compliance**, ensuring that:
- OpenSIPS sends responses to the **actual source IP:port** (NAT public IP:port)
- Responses traverse NAT correctly and reach the phone
- Registration authentication challenges (401) are delivered reliably
- Subsequent SIP messages (OPTIONS, NOTIFY, INVITE) are routed correctly

**Without Rport**, OpenSIPS may send responses to the wrong port, causing:
- Registration failures (401 challenges lost)
- One-way audio (responses don't reach phone)
- Call setup failures (INVITE responses lost)

**Solution**: Enable Rport on all phones behind NAT - it's the standard, reliable way to handle NAT traversal in SIP.
