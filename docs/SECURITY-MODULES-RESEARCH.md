# OpenSIPS Security Modules Research

**Date:** January 2026  
**OpenSIPS Version:** 3.6.3  
**Status:** 🔍 Research Phase  
**Phase:** Security & Threat Detection Project - Phase 0.1

## Objective

Research and evaluate OpenSIPS built-in security modules to determine what can be used vs. what needs to be built custom for the Security & Threat Detection project.

## Modules to Research

### 1. Rate Limiting & Attack Mitigation

#### `pike` Module
**Purpose:** Detect and block flooding attacks

**Availability:** ✅ **AVAILABLE** (`pike.so`)

**Key Features:**
- Detects SIP flood attacks (DoS/DDoS)
- Tracks request density from source IPs
- Marks/blocks/reports IPs exceeding thresholds
- Can whitelist trusted sources via `check_route` parameter
- Emits `E_PIKE_BLOCKED` event for monitoring

**Research Questions:**
- [x] Does it exist in OpenSIPS 3.6.3? ✅ Yes
- [x] What types of floods can it detect? ✅ SIP floods, DoS/DDoS attacks
- [x] How does it block attacks? ✅ Blocks/marks IPs exceeding thresholds
- [ ] Can it be configured per-IP or per-domain? (needs verification)
- [ ] Does it integrate with database for persistence? (needs verification)
- [ ] What are the performance characteristics? (needs testing)

**Documentation:** https://opensips.org/docs/modules/3.6.x/pike.html

**Status:** ✅ Basic research complete - needs testing

#### `ratelimit` Module
**Purpose:** Built-in rate limiting

**Availability:** ✅ **AVAILABLE** (`ratelimit.so`)

**Key Features:**
- Enforces rate limits (requests per second, etc.)
- Supports static and dynamic algorithms (TAILDROP, RED, etc.)
- Can limit per destination, per method, per user, or other grouping
- Can integrate with distributed key-value stores for scaling across instances
- Functions: `rl_check()`, `rl_dec_count()`, `rl_reset_count()`

**Research Questions:**
- [x] Does it exist in OpenSIPS 3.6.3? ✅ Yes
- [x] What rate limiting algorithms does it support? ✅ TAILDROP, RED, and others
- [x] Can it limit by IP, user, domain, or method? ✅ Yes, supports multiple grouping options
- [ ] Does it support different limits for different request types? (needs verification)
- [ ] Can limits be configured dynamically? (needs verification)
- [x] Does it integrate with database? ✅ Can use distributed key-value stores

**Documentation:** https://opensips.org/docs/modules/3.6.x/ratelimit.html

**Status:** ✅ Basic research complete - needs testing

#### `htable` Module
**Purpose:** Hash table for in-memory rate limiting

**Availability:** ⚠️ **NOT FOUND** (may be built-in or have different name)

**Research Questions:**
- [x] Does it exist in OpenSIPS 3.6.3? ⚠️ Not found as separate module
- [ ] Is it built into OpenSIPS core?
- [ ] What data structures does it support?
- [ ] Can it be used for rate limiting counters?
- [ ] What is the performance impact?
- [ ] Can it be shared across OpenSIPS instances?
- [ ] Does it support expiration/TTL?

**Status:** ⚠️ Need to verify if built-in

### 2. IP Management & Blocking

#### `ipban` Module
**Purpose:** IP banning capabilities

**Availability:** ❌ **NOT FOUND** (not available in OpenSIPS 3.6.3)

**Research Questions:**
- [x] Does it exist in OpenSIPS 3.6.3? ❌ No
- [ ] Alternative: Can `pike` module provide IP banning?
- [ ] Alternative: Can `permissions` module provide IP blocking?
- [ ] Do we need custom implementation?

**Status:** ⚠️ Need alternative solution

#### `permissions` Module
**Purpose:** IP-based access control

**Availability:** ✅ **AVAILABLE** (`permissions.so`)

**Key Features:**
- Controls access rules (routing permissions, registration permissions)
- Hosts.allow/deny-style validation of URIs and IPs
- Can reject unwanted REGISTER calls
- Can block specific From/R-URI patterns
- Supports database-backed ACLs

**Research Questions:**
- [x] Does it exist in OpenSIPS 3.6.3? ✅ Yes
- [x] How does it check permissions? ✅ Via allow/deny rules (file or database)
- [x] Can it use database for ACLs? ✅ Yes
- [x] Does it support allow/deny lists? ✅ Yes
- [ ] Can it be used for multi-tenant isolation? (needs verification)
- [x] Can it be used as IP ban alternative? ✅ Yes, can block IPs via deny rules

**Documentation:** https://opensips.org/docs/modules/3.6.x/permissions.html

**Status:** ✅ Basic research complete - needs testing

**Note:** Could potentially replace `ipban` module functionality

### 3. Authentication & Authorization

#### `auth_aaa` Module
**Purpose:** AAA authentication framework

**Availability:** ✅ **AVAILABLE** (`auth_aaa.so`)

**Research Questions:**
- [x] Does it exist in OpenSIPS 3.6.3? ✅ Yes (as auth_aaa.so)
- [ ] What authentication methods does it support?
- [ ] Can it track failed authentication attempts?
- [ ] Does it integrate with database?

**Status:** 🔍 Research in progress

#### `auth_db` Module
**Purpose:** Database-backed authentication

**Availability:** ✅ **AVAILABLE** (`auth_db.so`)

**Research Questions:**
- [x] Does it exist in OpenSIPS 3.6.3? ✅ Yes
- [ ] What database schemas does it support?
- [ ] Can it track authentication failures?
- [ ] Does it support password hashing?
- [ ] Can it be used for registration failure tracking?

**Status:** 🔍 Research in progress

### 4. Statistics & Monitoring

#### `statistics` Module
**Purpose:** Built-in statistics

**Research Questions:**
- [ ] Does it exist in OpenSIPS 3.6.3?
- [ ] What statistics does it provide?
- [ ] Can it track security events?
- [ ] How can statistics be accessed (MI, FIFO, etc.)?
- [ ] Can it export to Prometheus?

**Status:** ⏳ Pending research

## Currently Loaded Modules

From `config/opensips.cfg.template`, these modules are already in use:
- `sl.so` - Stateless replies
- `tm.so` - Transaction management
- `rr.so` - Record-Route
- `maxfwd.so` - Max-Forwards checking (security-related)
- `textops.so` - Text operations
- `db_mysql.so` - MySQL database
- `sqlops.so` - SQL operations
- `dispatcher.so` - Load balancing
- `nathelper.so` - NAT traversal
- `dialog.so` - Dialog tracking
- `acc.so` - Accounting
- `usrloc.so` - User location
- `registrar.so` - Registrar functions
- `domain.so` - Domain management

**Note:** No security-specific modules (`pike`, `ratelimit`, `ipban`, etc.) are currently loaded.

## Research Methodology

1. **Check Module Availability**
   - Verify modules exist in OpenSIPS 3.6.3 installation
   - Check module paths: `/usr/lib/x86_64-linux-gnu/opensips/modules/`
   - List available security modules

2. **Review Documentation**
   - OpenSIPS 3.6.3 module documentation: https://opensips.org/docs/modules/
   - Module README files
   - Example configurations
   - Community examples

3. **Test Basic Functionality**
   - Load modules in test configuration
   - Test basic features
   - Document capabilities and limitations
   - Measure performance impact

4. **Compare with Requirements**
   - Map module features to Security & Threat Detection requirements
   - Identify gaps
   - Determine if custom implementation needed

## Requirements Mapping

### Registration Security
- **Need:** Track registration failures
- **Need:** Rate limit registration attempts
- **Need:** Block IPs after threshold failures

### Rate Limiting
- **Need:** IP-based rate limiting
- **Need:** Registration-specific rate limiting
- **Need:** Method-specific rate limiting (INVITE, REGISTER, etc.)

### Attack Mitigation
- **Need:** Flood detection
- **Need:** Automatic IP blocking
- **Need:** Whitelist support

### Monitoring
- **Need:** Security event statistics
- **Need:** Failed registration tracking
- **Need:** Attack pattern detection

## Evaluation Criteria

For each module, evaluate:
1. **Availability:** Does it exist in OpenSIPS 3.6.3?
2. **Functionality:** Does it meet our requirements?
3. **Performance:** What is the performance impact?
4. **Maintainability:** Is it well-documented and maintained?
5. **Integration:** Can it integrate with our MySQL database?
6. **Multi-tenant:** Does it support multi-tenant scenarios?

## Research Findings

### Module Availability Check

**✅ COMPLETED:** Checked OpenSIPS 3.6.3 installation

**Results:**
```bash
$ ls /usr/lib/x86_64-linux-gnu/opensips/modules/ | grep -E "(pike|ratelimit|ipban|htable|permissions|auth)"
auth_aaa.so      ✅ Available
auth_db.so       ✅ Available
permissions.so   ✅ Available
pike.so          ✅ Available
ratelimit.so     ✅ Available
```

**Not Found:**
- `ipban.so` ❌ (not available - need alternative)
- `htable.so` ⚠️ (may be built-in or have different name)

**Location:** `/usr/lib/x86_64-linux-gnu/opensips/modules/`

### Documentation Review

**OpenSIPS 3.6 Documentation:**
- Module Index: https://opensips.org/docs/modules/3.6.x/
- Pike Module: https://opensips.org/docs/modules/3.6.x/pike.html
- Ratelimit Module: https://opensips.org/docs/modules/3.6.x/ratelimit.html
- IPBan Module: https://opensips.org/docs/modules/3.6.x/ipban.html
- HTable Module: https://opensips.org/docs/modules/3.6.x/htable.html
- Permissions Module: https://opensips.org/docs/modules/3.6.x/permissions.html

## Research Summary

### Available Modules ✅
- **pike.so** - Flood detection (DoS/DDoS protection)
- **ratelimit.so** - Rate limiting with multiple algorithms
- **permissions.so** - IP-based access control (can replace ipban)
- **auth_db.so** - Database-backed authentication
- **auth_aaa.so** - AAA authentication framework

### Missing Modules ❌
- **ipban.so** - Not available, but `permissions` module can provide IP blocking
- **htable.so** - Not found (may be built-in or have different name)

### Key Findings

1. **Flood Detection:** `pike` module available and suitable for DoS/DDoS protection
2. **Rate Limiting:** `ratelimit` module available with multiple algorithms
3. **IP Blocking:** `permissions` module can replace missing `ipban` module
4. **Authentication:** Both `auth_db` and `auth_aaa` available for registration security

## Next Steps

1. [x] Create research document structure
2. [x] Check module availability on OpenSIPS server ✅
3. [x] Review OpenSIPS 3.6.3 online documentation ✅
4. [ ] Test modules in test environment (when available)
5. [x] Document findings for each module ✅
6. [ ] Create evaluation matrix comparing modules vs requirements
7. [ ] Make recommendations on what to use vs build custom
8. [ ] Test module integration with MySQL database
9. [ ] Test multi-tenant scenarios with security modules

## References

- OpenSIPS 3.6 Documentation: https://opensips.org/docs/
- OpenSIPS Module Index: https://opensips.org/docs/modules/
- Security & Threat Detection Project Plan: `docs/SECURITY-THREAT-DETECTION-PROJECT.md`

---

**Last Updated:** January 2026  
**Status:** ✅ Module availability checked, basic research complete  
**Next Review:** After module testing
