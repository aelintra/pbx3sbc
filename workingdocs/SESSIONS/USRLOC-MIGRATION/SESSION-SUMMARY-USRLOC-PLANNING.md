# Session Summary: Usrloc Migration Planning

**Date:** January 2026  
**Branch:** `usrloc`  
**Status:** Planning Complete - Ready for Implementation

---

## Session Overview

This session focused on planning the migration from custom `endpoint_locations` table to OpenSIPS standard `usrloc` module and `location` table. The migration was identified as **TOP PRIORITY** to prevent increasing technical debt.

---

## Key Decisions Made

### 1. Migration Priority
- **Decision:** Usrloc migration is now **#1 HIGHEST PRIORITY**
- **Rationale:** Must complete before other major work to avoid increasing technical debt
- **Impact:** All other major work should wait until migration complete
- **Updated:** `MASTER-PROJECT-PLAN.md` - moved to #1 in High Priority section

### 2. Multi-Tenant Critical Requirement
- **Problem Discovered:** Same extension numbers (2XX range) across different customer domains
- **Critical Issue:** Wildcard lookup (`@*`) returns "first match" - **UNACCEPTABLE** for production
- **Solution:** **MUST** determine domain from source IP (Asterisk → dispatcher → domain → lookup)
- **Documentation:** `MULTIPLE-DOMAINS-SAME-USERNAME.md` created with detailed analysis

### 3. Domain Context Solution
- **Approach:** Source IP → Dispatcher Set → Domain → Domain-Specific Lookup
- **Implementation:** `lookup("location", "uri", "sip:username@domain")` (NOT wildcard)
- **Status:** Solution designed, needs implementation (Week 2, Days 6-10)

### 4. Daily Step-by-Step Plan
- **Created:** 25-day breakdown (5 weeks) with specific daily tasks
- **Time Commitment:** 1-5 hours per day
- **Location:** `USRLOC-MIGRATION-PLAN.md` - "Easy-to-Digest Migration Steps" section

---

## Documents Created/Updated

### New Documents
1. **`docs/USRLOC-MIGRATION-PLAN.md`** - Comprehensive migration plan
2. **`docs/MULTIPLE-DOMAINS-SAME-USERNAME.md`** - Critical multi-tenant issue analysis
3. **`docs/WHY-USERNAME-ONLY-LOOKUP.md`** - Why username-only lookup is needed
4. **`scripts/create-location-table.sql`** - MySQL location table creation script

### Updated Documents
1. **`docs/MASTER-PROJECT-PLAN.md`** - Usrloc migration moved to #1 priority
2. **`docs/USRLOC-MIGRATION-PLAN.md`** - Added daily step-by-step guide, clarified unresolved questions

### Deleted Documents
1. **`docs/USERNAME-ONLY-LOOKUP-CONTEXT.md`** - Deleted (documented incorrect wildcard solution)

---

## Technical Confirmations

### Environment Verified
- ✅ **OpenSIPS Version:** 3.6.3 (x86_64/linux) - Confirmed
- ✅ **usrloc Module:** Exists at `/usr/lib/x86_64-linux-gnu/opensips/modules/usrloc.so`
- ✅ **MySQL Credentials:** `opensips/opensips` (documented)
- ✅ **Location Table:** Created on test machine

### Resolved Questions
- ✅ **Contact Header Parsing:** `lookup()` handles automatically, sets `$du`
- ✅ **contact_uri Field:** `lookup()` sets `$du` automatically - no manual construction needed
- ✅ **Diagnostic Logging:** Multiple options available (query location table or use `$du`)
- ✅ **OpenSIPS Version:** 3.6.3 confirmed
- ✅ **Request-URI Construction:** Will be resolved Day 5 (test `lookup()` and verify `$du` format)
- ✅ **Module Configuration:** Recommended config provided (`db_mode=2`, `use_domain=1`)
- ✅ **Performance:** Will be benchmarked Week 3, Day 14
- ✅ **Data Migration:** Decision point Week 5 (can start fresh - recommended)

### Remaining Implementation Tasks
- ⏳ **Domain Context from Source IP:** Week 2, Days 6-10
- ⏳ **Request-URI Construction:** Week 1, Day 5 (test and verify)
- ⏳ **Performance Benchmarking:** Week 3, Day 14

---

## Key Technical Insights

### 1. OpenSIPS Domain Separation
- OpenSIPS treats `user@domainA` and `user@domainB` as **completely separate entities**
- Contacts stored with `username@domain` as key in `location` table
- `lookup("location", "uri", "sip:401@tenant-a.com")` **only** finds contacts in `tenant-a.com`
- **Never cross-domain** - this is built into OpenSIPS architecture

### 2. Wildcard Lookup Behavior
- `lookup("location", "uri", "sip:username@*")` returns **first match**
- **UNACCEPTABLE** for multi-tenant (non-deterministic, may route to wrong customer)
- **Solution:** Domain-specific lookup is **ONLY acceptable primary method**

### 3. Proxy-Registrar Pattern
- **Current (WRONG):** Store location in request route (before proxying)
- **Target (CORRECT):** Store location in `onreply_route` (after successful 2xx reply)
- **Benefit:** No stale registrations (failed registrations don't create records)

### 4. Module Configuration
- **`use_domain = 1`** - **REQUIRED** for multi-tenant (allows same username across domains)
- **`db_mode = 2`** - Recommended (cached DB mode - best performance/persistence balance)
- **`nat_bflag = "NAT"`** - For NAT traversal support

---

## Implementation Status

### Week 1: Research & Setup
- **Day 1:** ✅ OpenSIPS version confirmed, ✅ usrloc module confirmed
- **Day 2:** ✅ Location table SQL script created, ✅ Added to installer
- **Days 3-5:** ⏳ Pending (load modules, test save/lookup)

### Week 2-5: ⏳ Pending
- All tasks documented in daily step-by-step guide

---

## Files Ready for Next Session

### Scripts
- ✅ `scripts/create-location-table.sql` - Ready to use
- ✅ `scripts/init-database.sh` - Updated to create location table

### Documentation
- ✅ `docs/USRLOC-MIGRATION-PLAN.md` - Complete with daily tasks
- ✅ `docs/MULTIPLE-DOMAINS-SAME-USERNAME.md` - Critical requirements documented
- ✅ `docs/WHY-USERNAME-ONLY-LOOKUP.md` - Context for username-only lookups

---

## Next Steps for Next Session

### Immediate (Continue Day 1)
1. Complete MySQL database connection verification
2. Review `endpoint_locations` table structure

### Week 1 Remaining
3. **Day 3:** Load modules in config (`usrloc.so`, `domain.so`)
4. **Day 4:** Test basic save in `onreply_route`
5. **Day 5:** Test basic lookup and verify `$du` format

### Week 2 (Critical)
6. **Days 6-10:** Implement domain context from source IP
   - Source IP → Dispatcher Set lookup
   - Dispatcher Set → Domain lookup
   - Domain-specific endpoint lookup
   - Multi-tenant testing

---

## Important Notes for Next Session

### Critical Requirements
1. **MUST use domain-specific lookup** - wildcard (`@*`) is unacceptable for multi-tenant
2. **MUST determine domain from source IP** - when Asterisk sends request with IP in Request-URI
3. **MUST configure `use_domain = 1`** - required for multi-tenant support

### Configuration
- **OpenSIPS Version:** 3.6.3
- **MySQL Credentials:** `opensips/opensips`
- **Module Path:** `/usr/lib/x86_64-linux-gnu/opensips/modules/usrloc.so`
- **Location Table:** Already created on test machine

### Architecture Context
- **Multi-tenant deployment:** Same extension numbers (2XX) across different customer domains
- **Business requirement:** Customers don't want to change extension numbers
- **Critical:** Must route to correct customer based on which Asterisk sent request

---

## Git Status

**Branch:** `usrloc`  
**Recent Commits:**
- `f835bd9` - Add location table creation to installer script
- `8a1574d` - Document confirmed OpenSIPS version 3.6.3
- `72c980f` - Confirm usrloc module exists at expected path
- `468793b` - Add MySQL connection details for Day 1 verification
- `b294940` - Clarify unresolved questions in usrloc migration plan
- `a177e9d` - Prioritize usrloc migration as top priority and add daily step-by-step guide
- `edf7961` - Remove USERNAME-ONLY-LOOKUP-CONTEXT.md and update references

**Status:** All changes committed and pushed to `usrloc` branch

---

## Questions Resolved This Session

1. ✅ Can we use wildcard lookup for username-only lookups?
   - **Answer:** Technically yes, but **UNACCEPTABLE** for multi-tenant (returns first match)

2. ✅ How to handle same username in multiple domains?
   - **Answer:** Determine domain from source IP, then use domain-specific lookup

3. ✅ What's the correct proxy-registrar pattern?
   - **Answer:** Save location in `onreply_route` after successful 2xx reply, not in request route

4. ✅ What OpenSIPS version are we using?
   - **Answer:** OpenSIPS 3.6.3 (x86_64/linux)

5. ✅ Does usrloc module exist?
   - **Answer:** Yes, at `/usr/lib/x86_64-linux-gnu/opensips/modules/usrloc.so`

6. ✅ How to create location table?
   - **Answer:** Use `scripts/create-location-table.sql` (already added to installer)

---

## Remaining Questions (Not Blockers)

1. ⏳ Request-URI construction format - Will be resolved Day 5 (test `lookup()`)
2. ⏳ Performance characteristics - Will be benchmarked Week 3, Day 14
3. ⏳ Data migration approach - Decision point Week 5 (can start fresh)

---

## Key Takeaways

1. **Migration is TOP PRIORITY** - Must be done first to avoid technical debt
2. **Multi-tenant is CRITICAL** - Domain context from source IP is required, not optional
3. **Wildcard lookup is UNACCEPTABLE** - Must use domain-specific lookup
4. **Daily plan is ready** - 25 days broken down with specific tasks
5. **Environment is verified** - OpenSIPS 3.6.3, usrloc module exists, location table created
6. **No blockers remain** - All questions have clear resolution paths

---

**Status:** ✅ Planning Complete - Ready to Begin Implementation  
**Next Session:** Continue with Week 1, Day 1 remaining tasks, then proceed to Day 3-5
