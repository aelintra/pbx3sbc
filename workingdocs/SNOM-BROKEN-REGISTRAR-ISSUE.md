# Snom "Support Broken Registrar" Issue

## Problem

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

## Solution

We need to ensure the Request-URI in INVITEs matches the Contact URI format from REGISTER.

### Option 1: Store and Use Original Contact URI Format (Recommended)

Store the full Contact URI format from REGISTER and use it as the Request-URI:

1. **Database Schema Change:**
   - Add `contact_uri` column to `endpoint_locations` table
   - Store the normalized Contact URI format (e.g., `sip:user@domain` or `sip:user@ip:port`)

2. **REGISTER Handling:**
   - Extract and normalize the Contact header URI
   - Store it in `contact_uri` column
   - Continue storing `contact_ip` and `contact_port` for routing ($du)

3. **INVITE Routing:**
   - Use stored `contact_uri` for Request-URI ($ru)
   - Use `contact_ip:contact_port` for destination URI ($du) for actual routing

### Option 2: Use AoR Consistently (Simpler, but may not work for all endpoints)

Ensure we always use the AoR (user@domain) format for Request-URI:

1. **Current Behavior:**
   - `BUILD_ENDPOINT_URI` already tries to use AoR first
   - But may fall back to IP:port if domain extraction fails

2. **Fix:**
   - Ensure domain is always available from the stored AoR
   - Always use `sip:{AoR}` as Request-URI
   - Never fall back to IP:port format for Request-URI

### Option 3: Extract Contact URI Format from REGISTER

Extract the user@domain or user@ip:port format from the Contact header and store it:

1. **REGISTER Processing:**
   - Parse Contact header to extract the URI format
   - Store the format (e.g., `user@domain` or `user@ip:port`)
   - Use this stored format for Request-URI construction

## Recommended Implementation (Option 1)

### Database Schema

```sql
ALTER TABLE endpoint_locations 
ADD COLUMN contact_uri VARCHAR(255) AFTER contact_port;

-- Migration: Populate contact_uri from existing data
UPDATE endpoint_locations 
SET contact_uri = CONCAT('sip:', aor) 
WHERE contact_uri IS NULL OR contact_uri = '';
```

### REGISTER Processing

Extract and store the Contact URI format:
- If Contact header has domain: use `sip:user@domain`
- If Contact header has IP: use `sip:user@ip:port` (but prefer domain if AoR has domain)
- Store in `contact_uri` column

### INVITE Routing

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

## Testing

After implementing the fix:
1. Register a Snom endpoint
2. Check that `contact_uri` is stored correctly in database
3. Make a call to the Snom endpoint
4. Verify Request-URI in INVITE matches the Contact URI from REGISTER
5. Verify that "Support broken registrar" is no longer required

## References

- [Snom Documentation: user_sipusername_as_line](https://service.snom.com/spaces/wiki/pages/234342279/user_sipusername_as_line)
- OpenSIPS Contact header handling
- SIP RFC 3261 - Contact header specification

