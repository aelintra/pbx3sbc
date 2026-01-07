# usrloc Module Correction

**Date:** January 2026  
**Issue:** Initial implementation incorrectly assumed usrloc exports `save()` and `lookup()` functions

## Problem

The usrloc module does **not** export script functions directly. It's used internally by the registrar module. The `save()` and `lookup()` functions are from the registrar module, not usrloc.

## Solution

Since we're not acting as a full registrar (Asterisk is the registrar), we:
1. **Use SQL queries directly** to the `location` table for both saving and lookup
2. **Keep usrloc module loaded** for table structure management and potential future use
3. **Maintain backward compatibility** with legacy `endpoint_locations` table

## Changes Made

### REGISTER Handling
- **Before:** Used `save("location")` function (doesn't exist)
- **After:** Direct SQL INSERT to `location` table
- **Approach:**
  - DELETE existing contacts for username+domain
  - INSERT new contact with all required fields
  - Uses Unix timestamp for expires (location table uses INTEGER)

### Endpoint Lookup
- **Before:** Used `lookup("location")` function (doesn't exist)
- **After:** Direct SQL SELECT from `location` table
- **Approach:**
  - Query `location` table by username+domain (exact match)
  - Query `location` table by username only (fallback)
  - Extract IP/port from contact URI using regex
  - Fall back to legacy `endpoint_locations` table if needed

## Benefits

1. **Direct Control:** We control exactly what gets stored and when
2. **Compatibility:** Works with standard OpenSIPS `location` table structure
3. **Flexibility:** Can add custom fields or logic as needed
4. **Fallback:** Legacy table still works if location table has issues

## Location Table Fields Used

- `username` - Username from To header
- `domain` - Domain from To header
- `contact` - Full contact URI (sip:user@ip:port)
- `expires` - Unix timestamp (current_time + expires_seconds)
- `q` - Q value (default 1.0)
- `callid` - Call-ID from REGISTER
- `cseq` - CSeq number from REGISTER
- `last_modified` - Current timestamp
- `flags` - Flags (default 0)
- `user_agent` - User-Agent header

## Testing

1. **Registration:**
   - Register endpoint
   - Verify entry in `location` table
   - Check expires timestamp is correct

2. **Lookup:**
   - Query by exact AoR
   - Query by username only
   - Verify IP/port extraction works

3. **Expiration:**
   - Wait for registration to expire
   - Verify expired entries are not returned

## Future Considerations

If we want to use registrar module in the future:
- Load `registrar` module
- Use `save()` and `lookup()` functions from registrar
- Registrar will handle REGISTER requests fully
- Would need to decide: act as registrar or proxy to Asterisk?

For now, direct SQL approach works well for our use case.

