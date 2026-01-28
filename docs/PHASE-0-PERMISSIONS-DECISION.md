# Phase 0: Permissions Module Decision

**Date:** January 2026  
**Status:** ✅ **DECISION MADE** - Skip permissions module testing  
**Decision:** Use Fail2Ban for IP blocking instead of permissions module

---

## Decision

**Skip permissions module testing and use Fail2Ban for IP blocking.**

---

## Analysis

### Fail2Ban (Current Implementation)

**What it does:**
- Monitors OpenSIPS logs for security events
- Automatically blocks IPs at firewall level (iptables/ufw)
- Blocks packets before they reach OpenSIPS
- System-level blocking (more effective)

**Current Status:**
- ✅ Already implemented and working
- ✅ Configured for brute force detection
- ✅ Monitors failed registrations and door-knock attempts
- ✅ Whitelist support via `manage-fail2ban-whitelist.sh`
- ✅ Automatic IP blocking based on log patterns

**Advantages:**
- **More effective:** Blocks at firewall level (packets never reach OpenSIPS)
- **Reduces load:** OpenSIPS doesn't process blocked requests
- **System-level:** Blocks all traffic from IP, not just SIP
- **Already working:** No additional implementation needed
- **Well-tested:** Industry standard tool

### Permissions Module (Proposed)

**What it would do:**
- IP-based access control at OpenSIPS SIP layer
- Database-backed ACLs (whitelist/blacklist)
- Blocks requests after they reach OpenSIPS
- Application-level blocking

**Disadvantages:**
- **Less effective:** Packets reach OpenSIPS before blocking
- **Adds load:** OpenSIPS must process request before blocking
- **Redundant:** Fail2Ban already handles IP blocking
- **More complex:** Additional module to maintain
- **No clear advantage:** Doesn't provide functionality Fail2Ban lacks

---

## Comparison

| Feature | Fail2Ban | Permissions Module |
|---------|----------|-------------------|
| **Blocking Level** | Firewall (iptables) | Application (OpenSIPS) |
| **Effectiveness** | ✅ High (packets never reach OpenSIPS) | ⚠️ Lower (packets processed first) |
| **Performance Impact** | ✅ None (blocks before OpenSIPS) | ⚠️ Adds load (processes then blocks) |
| **Implementation Status** | ✅ Already implemented | ❌ Would need implementation |
| **Whitelist Support** | ✅ Yes (`manage-fail2ban-whitelist.sh`) | ✅ Yes (database ACLs) |
| **Automatic Blocking** | ✅ Yes (based on log patterns) | ⚠️ Manual (database entries) |
| **Multi-tenant Support** | ✅ Yes (whitelist per tenant) | ✅ Yes (groups/partitions) |
| **Maintenance** | ✅ Low (standard tool) | ⚠️ Medium (custom module) |

---

## Use Cases

### IP Blocking Needs

**1. Automatic Blocking (Brute Force/Floods):**
- ✅ **Fail2Ban:** Handles brute force detection (already implemented)
- ✅ **Pike Module:** Handles flood detection (Phase 0 testing)

**2. Manual Blocking (Administrative):**
- ✅ **Fail2Ban:** Can manually ban/unban IPs via `fail2ban-client`
- ✅ **Fail2Ban:** Whitelist management script available

**3. Whitelisting (Trusted Sources):**
- ✅ **Fail2Ban:** Whitelist support via `manage-fail2ban-whitelist.sh`
- ✅ **Fail2Ban:** Can whitelist IPs/CIDR ranges

**Conclusion:** Fail2Ban covers all IP blocking use cases.

---

## Edge Cases Considered

### 1. Domain-Specific Blocking
**Question:** Can permissions module block IPs per domain?

**Answer:** 
- Permissions module can use groups/partitions for domain-specific rules
- **But:** Fail2Ban can also be configured per-domain if needed (separate jails)
- **Reality:** We don't need domain-specific IP blocking - IP blocking is typically global

### 2. Method-Specific Blocking
**Question:** Can permissions module block IPs per SIP method?

**Answer:**
- Permissions module supports pattern matching
- **But:** Fail2Ban already monitors specific methods via log patterns
- **Reality:** Method-specific blocking not needed - IP blocking is typically global

### 3. Performance at Scale
**Question:** Would permissions module be faster than Fail2Ban?

**Answer:**
- Permissions module: Database lookup per request (adds latency)
- Fail2Ban: Firewall rule (no OpenSIPS processing needed)
- **Conclusion:** Fail2Ban is more performant (blocks before processing)

---

## Recommendation

**✅ Use Fail2Ban for IP blocking - Skip permissions module**

**Rationale:**
1. Fail2Ban already implemented and working
2. More effective (firewall-level blocking)
3. Reduces load on OpenSIPS
4. Covers all IP blocking use cases
5. No clear advantage of permissions module
6. Avoids unnecessary complexity

**For IP Blocking:**
- **Automatic:** Fail2Ban (brute force) + Pike (floods)
- **Manual:** Fail2Ban whitelist/ban management
- **Whitelisting:** Fail2Ban whitelist script

---

## Impact on Phase 0

**Updated Phase 0 Tasks:**
- ✅ Task 0.1.1: Test Pike Module (flood detection) - **KEEP**
- ✅ Task 0.1.2: Test Ratelimit Module (rate limiting) - **KEEP**
- ❌ Task 0.1.3: Test Permissions Module - **SKIP** (this decision)
- ✅ Task 0.1.4: Create Architecture Decision Document - **KEEP**

**Time Saved:** ~2 hours (permissions module testing)

**Updated Total:** ~5.5 hours (down from 7.5 hours)

---

## Related Documentation

- `config/fail2ban/README.md` - Fail2Ban configuration and usage
- `scripts/manage-fail2ban-whitelist.sh` - Whitelist management
- `docs/SECURITY-IMPLEMENTATION-PLAN.md` - Security project overview
- `docs/PHASE-0-EXECUTION-PLAN.md` - Phase 0 testing plan

---

**Last Updated:** January 2026  
**Status:** Decision made - Skip permissions module, use Fail2Ban
