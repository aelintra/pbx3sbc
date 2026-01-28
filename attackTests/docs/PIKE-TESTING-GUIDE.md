# Pike Module Testing Guide

**Date:** January 2026  
**Purpose:** Guide for testing OpenSIPS Pike module flood detection

---

## Current Configuration

**Pike Module Settings:**
- `sampling_time_unit`: 2 seconds
- `reqs_density_per_unit`: 16 requests per 2 seconds (8 req/sec threshold)
- `remove_latency`: 4 units = 8 seconds block duration
- `pike_log_level`: 1 (logs blocked IPs)
- **Mode:** Automatic (internal hooks)

**Event Route:** Configured to log blocked IPs

---

## Testing Methods

### Method 1: Automated Test Script

**Script:** `attackTests/scripts/test-pike-module.sh`

**Usage:**
```bash
cd attackTests
./scripts/test-pike-module.sh <sbc-ip> [sbc-port]
```

**Example:**
```bash
cd attackTests
./scripts/test-pike-module.sh 192.168.1.10 5060
```

**What it does:**
1. Tests normal traffic (should work)
2. Sends flood of requests (should trigger Pike)
3. Tests blocking behavior
4. Tests unblocking after timeout

**Requirements:**
- SIPp installed: `sudo apt-get install sipp`
- Run from test machine (not SBC server)

---

### Method 2: SIPVicious Attack Tools

**Tools Available:**
- `svwar` - Scan for extensions
- `svmap` - Scan for hosts
- `svcrack` - Brute force authentication
- `svreport` - Generate reports

**Example Attacks:**

**1. Extension Scanning (svwar):**
```bash
# Scan extensions 100-200 with INVITE method
svwar -e 100-200 -m INVITE <sbc-ip>:5060

# This will send many requests rapidly and should trigger Pike
```

**2. Host Scanning (svmap):**
```bash
# Scan network range
svmap <sbc-ip>/24

# Scan single host with many requests
svmap <sbc-ip>
```

**3. Brute Force (svcrack):**
```bash
# Brute force authentication (sends many REGISTER requests)
svcrack -u 1000 -d /usr/share/sipvicious/passwords.txt <sbc-ip>:5060
```

---

### Method 3: SIPp (Manual)

**Send Rapid Requests:**
```bash
# Send 20 requests rapidly (should trigger Pike)
sipp -sn uac -s 40004 -m 20 -r 20 -d 1000 <sbc-ip>:5060

# Parameters:
#   -sn uac: Use UAC scenario
#   -s 40004: SIP username
#   -m 20: Send 20 requests
#   -r 20: Rate of 20 requests/second
#   -d 1000: Delay 1000ms between requests
```

**Send Controlled Burst:**
```bash
# Send 30 requests in 1 second (definitely exceeds threshold)
sipp -sn uac -s 40004 -m 30 -r 30 -d 33 <sbc-ip>:5060
```

---

## Monitoring During Test

### On OpenSIPS Server

**Watch Pike Events:**
```bash
journalctl -u opensips -f | grep -i pike
```

**Watch All Logs:**
```bash
journalctl -u opensips -f
```

**Look for:**
```
L_WARN: PIKE: IP <attacker-ip> blocked due to flood detection (automatic mode)
```

### Expected Behavior

1. **Normal Traffic:** Requests succeed (or get normal SIP responses)
2. **Flood Detection:** After ~16 requests in 2 seconds:
   - Pike blocks the IP
   - Log message appears: "PIKE: IP ... blocked"
   - Subsequent requests are dropped (no response)
3. **Block Duration:** IP remains blocked for 8 seconds
4. **Unblocking:** After 8 seconds, IP can send requests again

---

## Test Checklist

When running tests, document:

### Test 1: Normal Traffic
- [ ] Send 5-10 normal requests
- [ ] All requests get responses (or normal SIP behavior)
- [ ] No false positives

### Test 2: Flood Detection
- [ ] Send 20+ requests rapidly (< 2 seconds)
- [ ] Pike event appears in logs
- [ ] IP gets blocked
- [ ] Blocked IP cannot send requests (no response)

### Test 3: Block Duration
- [ ] Wait 8 seconds after blocking
- [ ] IP is unblocked
- [ ] IP can send requests again

### Test 4: Threshold Accuracy
- [ ] Send exactly 16 requests in 2 seconds
- [ ] Does it block? (should be at threshold)
- [ ] Send 15 requests in 2 seconds
- [ ] Does it block? (should NOT block)

### Test 5: Performance Impact
- [ ] Monitor CPU/memory during test
- [ ] No significant performance degradation
- [ ] Normal traffic unaffected

---

## Troubleshooting

### Pike Not Triggering

**Check:**
1. Is Pike module loaded?
   ```bash
   opensipsctl fifo module_list | grep pike
   ```

2. Are thresholds too high?
   - Current: 16 requests per 2 seconds
   - Try lowering: `reqs_density_per_unit` to 10

3. Is automatic mode enabled?
   - Check config: Should have `loadmodule "pike.so"`
   - No manual `pike_check_req()` calls needed

### False Positives

**If legitimate traffic is blocked:**
1. Increase threshold: `reqs_density_per_unit` to 20 or higher
2. Add whitelist route: Use `check_route` parameter
3. Adjust `sampling_time_unit` if needed

### IP Not Unblocking

**Check:**
1. Is `remove_latency` set correctly? (should be 4 = 8 seconds)
2. Wait full duration before testing
3. Check if IP is blocked elsewhere (firewall, etc.)

---

## Documenting Results

After testing, update `docs/PHASE-0-PIKE-RESULTS.md` with:

1. **Test Results:** Fill in all test sections
2. **Findings:** Check appropriate boxes
3. **Issues:** Document any problems encountered
4. **Recommendations:** Optimal configuration values
5. **Recommendation:** Use/Don't use/Needs more testing

---

## Next Steps

After Pike testing:
1. Document results in `PHASE-0-PIKE-RESULTS.md`
2. Proceed to Ratelimit module testing
3. Proceed to Permissions module testing
4. Create architecture decision document

---

**Last Updated:** January 2026
