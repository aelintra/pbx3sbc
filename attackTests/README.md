# Attack Testing Directory

**Purpose:** Tools and guides for testing OpenSIPS security modules and attack detection

---

## Contents

### Documentation (`docs/`)

- **`PIKE-TESTING-GUIDE.md`** - Guide for testing Pike module flood detection
- **`SIPp-SETUP-GUIDE.md`** - Guide for installing and using SIPp testing tool

### Scripts (`scripts/`)

- **`test-pike-module.sh`** - Automated test script for Pike module
- **`setup-sipp.sh`** - SIPp installation script

---

## Quick Start

### 1. Set Up Testing Environment

**Install SIPp:**
```bash
cd attackTests
./scripts/setup-sipp.sh package
```

**Or use SIPVicious:**
```bash
sudo apt-get install -y sipvicious
```

### 2. Run Pike Module Tests

**Automated Test:**
```bash
cd attackTests
./scripts/test-pike-module.sh <sbc-ip> 5060
```

**Manual Test with SIPVicious:**
```bash
svwar -e 100-200 -m INVITE <sbc-ip>:5060
```

### 3. Monitor Results

**On OpenSIPS Server:**
```bash
journalctl -u opensips -f | grep -i pike
```

---

## Testing Phases

### Phase 0: Pike Module Testing
- Test flood detection
- Verify blocking behavior
- Test unblocking after timeout
- Document results in `docs/PHASE-0-PIKE-RESULTS.md`

### Phase 0: Ratelimit Module Testing
- Test rate limiting per IP/user
- Verify database persistence
- Document results in `docs/PHASE-0-RATELIMIT-RESULTS.md`

### Phase 0: Permissions Module Testing
- Test IP whitelist/blacklist
- Verify database performance
- Document results in `docs/PHASE-0-PERMISSIONS-RESULTS.md`

---

## Safety Notes

⚠️ **Important:**
- Only test against your own systems
- Use isolated test environments when possible
- Don't test against production without authorization
- Monitor system resources during tests
- Have rollback plan ready

---

## Related Documentation

- `docs/PHASE-0-EXECUTION-PLAN.md` - Phase 0 testing execution plan
- `docs/PHASE-0-PIKE-RESULTS.md` - Pike module test results
- `docs/SECURITY-THREAT-DETECTION-PROJECT.md` - Security project overview

---

**Last Updated:** January 2026
