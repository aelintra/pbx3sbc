# Snom Debugging Steps

## Current Status

The fix has been implemented to extract the actual Contact URI from REGISTER headers, but we need to verify:

1. **Config Applied?** Has the updated config been applied to running OpenSIPS?
2. **Snom Re-registered?** Has the Snom endpoint re-registered with the new code running?
3. **Contact URI Stored?** What Contact URI format is actually stored in the database?

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

