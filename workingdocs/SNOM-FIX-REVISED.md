# Snom Fix - Revised Approach

## Problem Identified

Looking at the SIP trace, the Request-URI is correctly set to `sip:1000@pjsipsbc.vcloudpbx.com`, but the Snom still rejects with 404.

The issue is that we're **constructing** the `contact_uri` as `sip:{AoR}` instead of using the **actual Contact header** from the REGISTER request.

## Current Implementation (Wrong)

```opensips
$var(contact_uri) = "sip:" + $var(endpoint_aor);
```

This creates `sip:1000@pjsipsbc.vcloudpbx.com` but the Snom may have registered with:
- `sip:1000@pjsipsbc.vcloudpbx.com:5060` (with port)
- `sip:1000@192.168.1.138:49554` (with IP and port)
- Or some other format with parameters

## Correct Implementation

We need to extract the **actual Contact URI** from the REGISTER Contact header.

### Option 1: Parse Contact Header (Complex)

Parse the Contact header string to extract the URI portion, removing angle brackets and parameters.

### Option 2: Use Contact Header Module (Recommended)

OpenSIPS may have functions to parse Contact headers, or we can use regex to extract the URI.

### Option 3: Use the Received Parameter (If NAT)

If NAT is involved, the `received` parameter might be relevant, but for Contact URI matching, we want the actual Contact value.

## Implementation

Extract the Contact URI from `$hdr(Contact)`:

```opensips
# Extract Contact URI from Contact header
# Format: <sip:user@domain:port> or sip:user@domain:port
# Remove angle brackets and extract URI (before semicolon if parameters exist)

# Try to extract URI from Contact header
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

## Testing

After implementing:
1. Register Snom endpoint
2. Check database: `SELECT aor, contact_uri FROM endpoint_locations WHERE aor LIKE '1000@%';`
3. Verify `contact_uri` matches the actual Contact header from REGISTER
4. Test call - should work without "support broken registrar"

