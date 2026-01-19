# Snom "Support Broken Registrar" Issue - Complete Troubleshooting Guide

**Date:** January 2026  
**Status:** ✅ Resolved  
**Issue:** Snom endpoints require "Support broken registrar" to be enabled to receive calls

## Problem Description

Snom endpoints require "Support broken registrar" to be enabled to receive calls. According to [Snom documentation](https://service.snom.com/spaces/wiki/pages/234342279/user_sipusername_as_line), this happens when:

> "incoming INVITEs from your VoIP provider do not contain the contact URI which was previously registered by your phone as its contact."

The phone cannot safely identify the target line when the Request-URI in the INVITE doesn't match the Contact URI from the REGISTER request.

## Root Cause

Currently, OpenSIPS:
1. Stores `contact_ip` and `contact_port` from REGISTER requests
2. Constructs the Request-URI using `BUILD_ENDPOINT_URI` route with fallback logic:
   - First tries to use AoR (user@domain)
   - Falls back to extracted domain
   - Last resort: uses IP:port format
3. This reconstructed Request-URI may not match the original Contact header format that the endpoint registered with

When the endpoint receives an INVITE with a Request-URI that doesn't match its registered Contact URI, it cannot identify which line the call is for.

## Solution Implemented

We implemented **Option 1: Store and Use Original Contact URI Format** (recommended approach).

### Implementation Details

#### Database Schema Change

Added `contact_uri` column to `endpoint_locations` table:

```sql
ALTER TABLE endpoint_locations 
ADD COLUMN contact_uri VARCHAR(255) AFTER contact_port;

-- Migration: Populate contact_uri from existing data
UPDATE endpoint_locations 
SET contact_uri = CONCAT('sip:', aor) 
WHERE contact_uri IS NULL OR contact_uri = '';
```

#### REGISTER Processing

Extract and store the actual Contact URI format from REGISTER headers:

```opensips
# Extract Contact URI from Contact header
# Format: <sip:user@domain:port> or sip:user@domain:port
# Remove angle brackets and extract URI (before semicolon if parameters exist)

$var(contact_uri_raw) = $hdr(Contact);

# Remove angle brackets if present
if ($var(contact_uri_raw) =~ "^<(.+)>$") {
    $var(contact_uri_raw) = $re;
}

# Extract URI part (before semicolon/parameters)
if ($var(contact_uri_raw) =~ "^([^;]+)") {
    $var(contact_uri) = $re;
} else {
    $var(contact_uri) = $var(contact_uri_raw);
}

# If extraction failed, fallback to constructed format
if ($var(contact_uri) == "") {
    $var(contact_uri) = "sip:" + $var(endpoint_aor);
}
```

The `contact_uri` is stored in the database during REGISTER processing.

#### INVITE Routing

Use stored `contact_uri` for Request-URI:

```opensips
# In BUILD_ENDPOINT_URI or endpoint routing:
if ($var(contact_uri) != "") {
    $ru = $var(contact_uri);  # Use stored Contact URI format
} else {
    # Fallback to current logic
    $ru = "sip:" + $var(endpoint_aor);
}
```

## Debugging Steps

### Step 1: Check Current Database Entry

```bash
mysql -u opensips -p'your-password' opensips -e "SELECT aor, contact_ip, contact_port, contact_uri FROM endpoint_locations WHERE aor LIKE '1000@%';"
```

This shows what's currently stored. If `contact_uri` is `sip:1000@pjsipsbc.vcloudpbx.com` (constructed format), it was created before the fix.

### Step 2: Check REGISTER Logs

Find the actual Contact header from the Snom's REGISTER:

```bash
journalctl -u opensips | grep -i "REGISTER.*1000" -A 5
```

Or look for:
```
REGISTER received from 192.168.1.138, Contact: ...
```

This shows what Contact header the Snom actually sent.

### Step 3: Apply Updated Config (if not done)

If the config hasn't been applied yet:

```bash
sudo ./scripts/apply-snom-fix.sh
```

Or manually:
1. Backup current config
2. Copy updated template
3. Update database password
4. Restart OpenSIPS

### Step 4: Force Snom Re-registration

After applying the config, the Snom needs to re-register. You can:
- Wait for its next registration refresh (usually every 60 minutes)
- Manually unregister/re-register from the phone
- Reboot the phone

### Step 5: Verify New Registration

After re-registration, check logs for:
```
REGISTER: Extracted Contact URI from header: ...
```

And verify database:
```bash
mysql -u opensips -p'your-password' opensips -e "SELECT aor, contact_uri FROM endpoint_locations WHERE aor LIKE '1000@%';"
```

The `contact_uri` should now match the actual Contact header format from the REGISTER.

### Step 6: Test Call

Try calling the Snom endpoint again and check if it works without "support broken registrar".

## Expected Contact URI Formats

Common formats from Snom endpoints:
- `sip:1000@pjsipsbc.vcloudpbx.com:5060` (with port)
- `sip:1000@192.168.1.138:49554` (with IP and port)
- `sip:1000@pjsipsbc.vcloudpbx.com` (domain only, no port)

The fix should extract and store whichever format the Snom actually used.

## Testing Checklist

After implementing the fix:
1. ✅ Register a Snom endpoint
2. ✅ Check that `contact_uri` is stored correctly in database
3. ✅ Make a call to the Snom endpoint
4. ✅ Verify Request-URI in INVITE matches the Contact URI from REGISTER
5. ✅ Verify that "Support broken registrar" is no longer required

## Alternative Solutions (Not Implemented)

### Option 2: Use AoR Consistently (Simpler, but may not work for all endpoints)

Ensure we always use the AoR (user@domain) format for Request-URI:

1. **Current Behavior:**
   - `BUILD_ENDPOINT_URI` already tries to use AoR first
   - But may fall back to IP:port if domain extraction fails

2. **Fix:**
   - Ensure domain is always available from the stored AoR
   - Always use `sip:{AoR}` as Request-URI
   - Never fall back to IP:port format for Request-URI

**Note:** This approach was not implemented because it may not work for all endpoint types that register with IP:port formats.

## References

- [Snom Documentation: user_sipusername_as_line](https://service.snom.com/spaces/wiki/pages/234342279/user_sipusername_as_line)
- OpenSIPS Contact header handling
- SIP RFC 3261 - Contact header specification
- Related: `docs/ENDPOINT-LOCATION-CREATION.md` - When endpoint_location records are created
