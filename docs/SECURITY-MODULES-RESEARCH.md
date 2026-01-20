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

**Research Questions:**
- [ ] Does it exist in OpenSIPS 3.6.3?
- [ ] What types of floods can it detect?
- [ ] How does it block attacks (drop, reject, redirect)?
- [ ] Can it be configured per-IP or per-domain?
- [ ] Does it integrate with database for persistence?
- [ ] What are the performance characteristics?

**Status:** ⏳ Pending research

#### `ratelimit` Module
**Purpose:** Built-in rate limiting

**Research Questions:**
- [ ] Does it exist in OpenSIPS 3.6.3?
- [ ] What rate limiting algorithms does it support?
- [ ] Can it limit by IP, user, domain, or method?
- [ ] Does it support different limits for different request types?
- [ ] Can limits be configured dynamically?
- [ ] Does it integrate with database?

**Status:** ⏳ Pending research

#### `htable` Module
**Purpose:** Hash table for in-memory rate limiting

**Research Questions:**
- [ ] Does it exist in OpenSIPS 3.6.3?
- [ ] What data structures does it support?
- [ ] Can it be used for rate limiting counters?
- [ ] What is the performance impact?
- [ ] Can it be shared across OpenSIPS instances?
- [ ] Does it support expiration/TTL?

**Status:** ⏳ Pending research

### 2. IP Management & Blocking

#### `ipban` Module
**Purpose:** IP banning capabilities

**Research Questions:**
- [ ] Does it exist in OpenSIPS 3.6.3?
- [ ] How does it ban IPs (drop, reject, redirect)?
- [ ] Can bans be temporary or permanent?
- [ ] Does it integrate with database?
- [ ] Can it auto-ban based on thresholds?
- [ ] Does it support whitelisting?

**Status:** ⏳ Pending research

#### `permissions` Module
**Purpose:** IP-based access control

**Research Questions:**
- [ ] Does it exist in OpenSIPS 3.6.3?
- [ ] How does it check permissions?
- [ ] Can it use database for ACLs?
- [ ] Does it support allow/deny lists?
- [ ] Can it be used for multi-tenant isolation?

**Status:** ⏳ Pending research

### 3. Authentication & Authorization

#### `auth` Module
**Purpose:** Authentication framework

**Research Questions:**
- [ ] Does it exist in OpenSIPS 3.6.3?
- [ ] What authentication methods does it support?
- [ ] Can it track failed authentication attempts?
- [ ] Does it integrate with database?

**Status:** ⏳ Pending research

#### `auth_db` Module
**Purpose:** Database-backed authentication

**Research Questions:**
- [ ] Does it exist in OpenSIPS 3.6.3?
- [ ] What database schemas does it support?
- [ ] Can it track authentication failures?
- [ ] Does it support password hashing?

**Status:** ⏳ Pending research

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

**Action Required:** Check OpenSIPS 3.6.3 installation for available modules:
```bash
ls /usr/lib/x86_64-linux-gnu/opensips/modules/ | grep -E "(pike|ratelimit|ipban|htable|permissions|auth)"
```

**Expected Location:** `/usr/lib/x86_64-linux-gnu/opensips/modules/`

### Documentation Review

**OpenSIPS 3.6 Documentation:**
- Module Index: https://opensips.org/docs/modules/3.6.x/
- Pike Module: https://opensips.org/docs/modules/3.6.x/pike.html
- Ratelimit Module: https://opensips.org/docs/modules/3.6.x/ratelimit.html
- IPBan Module: https://opensips.org/docs/modules/3.6.x/ipban.html
- HTable Module: https://opensips.org/docs/modules/3.6.x/htable.html
- Permissions Module: https://opensips.org/docs/modules/3.6.x/permissions.html

## Next Steps

1. [x] Create research document structure
2. [ ] Check module availability on OpenSIPS server
3. [ ] Review OpenSIPS 3.6.3 online documentation
4. [ ] Test modules in test environment (when available)
5. [ ] Document findings for each module
6. [ ] Create evaluation matrix comparing modules vs requirements
7. [ ] Make recommendations on what to use vs build custom

## References

- OpenSIPS 3.6 Documentation: https://opensips.org/docs/
- OpenSIPS Module Index: https://opensips.org/docs/modules/
- Security & Threat Detection Project Plan: `docs/SECURITY-THREAT-DETECTION-PROJECT.md`

---

**Last Updated:** January 2026  
**Next Review:** After module availability check
