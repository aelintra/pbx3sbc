# Fail2Ban Management Deployment Decision

**Date:** January 2026  
**Status:** ✅ **DECISION MADE**

---

## Decision

**Short Term:** Admin panel will be **colocated** with OpenSIPS server for Fail2Ban management.

**Long Term:** Implement **SSH-based remote execution** to enable decoupled deployment.

---

## Rationale

### Why Colocate Now?

1. **Build & Test:** Need to build and test core functionality to satisfaction
2. **Simplicity:** Colocated deployment is simpler (no network complexity)
3. **Security:** Direct access is more secure (no network exposure)
4. **Speed:** No network latency for operations
5. **Validation:** Prove the concept works before adding complexity

### Why SSH for Future?

**Decision:** SSH-based remote execution (not message queue)

**Reasoning:**
- **Message Queue:** More "modern" but **overkill** for current needs
  - Requires RabbitMQ/Redis infrastructure
  - Additional complexity and maintenance
  - Overkill for single or small fleet deployments
  
- **SSH:** Less "sexy" but **pragmatic choice**
  - Uses existing infrastructure (SSH is ubiquitous)
  - Simpler implementation
  - More secure (well-understood security model)
  - Supports fleet management without over-engineering
  - Maintains decoupled architecture principle

**Trade-off:** Accept the "pain" of testing with colocated deployment in short term to validate functionality, then implement SSH-based remote execution once core features are proven.

---

## Current Architecture (Phase 1)

```
┌─────────────────────────────────────┐
│   OpenSIPS Server                    │
│                                      │
│  ┌──────────────┐  ┌─────────────┐ │
│  │   OpenSIPS   │  │  Fail2Ban   │ │
│  │   Service    │  │   Service   │ │
│  └──────────────┘  └─────────────┘ │
│                                      │
│  ┌──────────────────────────────┐   │
│  │   Admin Panel (Laravel)      │   │
│  │   - Fail2banService           │   │
│  │   - WhitelistSyncService     │   │
│  │   - Direct file access       │   │
│  │   - Direct command exec      │   │
│  └──────────────────────────────┘   │
│                                      │
│  ┌──────────────┐                    │
│  │   MySQL DB   │                    │
│  └──────────────┘                    │
└─────────────────────────────────────┘
```

**Characteristics:**
- All components on same server
- Direct file system access
- Direct command execution
- Simple and secure

---

## Future Architecture (Phase 2)

```
┌─────────────────────────────────────┐
│   Admin Panel Server                 │
│                                      │
│  ┌──────────────────────────────┐   │
│  │   Admin Panel (Laravel)      │   │
│  │   - Fail2banService           │   │
│  │   - SshExecutor              │   │
│  │   - Server Management        │   │
│  └──────────────────────────────┘   │
│         │                            │
│         │ SSH                         │
│         │                            │
└─────────┼────────────────────────────┘
          │
          ├──────────────────────────────┐
          │                              │
┌─────────▼─────────────────────────────┐│
│   OpenSIPS Server 1                   ││
│                                      ││
│  ┌──────────────┐  ┌─────────────┐  ││
│  │   OpenSIPS   │  │  Fail2Ban   │  ││
│  │   Service    │  │   Service   │  ││
│  └──────────────┘  └─────────────┘  ││
│                                      ││
│  ┌──────────────┐                    ││
│  │   MySQL DB   │                    ││
│  └──────────────┘                    ││
└──────────────────────────────────────┘│
                                        │
┌───────────────────────────────────────┘
│   OpenSIPS Server 2                   │
│                                      │
│  ┌──────────────┐  ┌─────────────┐ │
│  │   OpenSIPS   │  │  Fail2Ban   │ │
│  │   Service    │  │   Service   │ │
│  └──────────────┘  └─────────────┘ │
│                                      │
│  ┌──────────────┐                    │
│  │   MySQL DB   │                    │
│  └──────────────┘                    │
└──────────────────────────────────────┘
```

**Characteristics:**
- Admin panel independent server
- SSH-based remote execution
- Supports multiple OpenSIPS instances
- Decoupled architecture

---

## Implementation Phases

### Phase 1: Colocated (Current) ✅

**Timeline:** Now - until core functionality is validated

**Tasks:**
- ✅ Implement Fail2Ban management features
- ✅ Test with colocated deployment
- ✅ Refine features based on usage
- ✅ Document deployment requirements

**Acceptable Trade-offs:**
- Testing requires full server setup
- Cannot manage multiple servers from one admin panel
- Admin panel must be on OpenSIPS server

### Phase 2: SSH-Based Remote (Future)

**Timeline:** After Phase 1 validation

**Tasks:**
- Refactor services to executor pattern
- Add server management (opensips_servers table)
- Implement SSH executor
- Update UI for server selection
- Test with remote admin panel
- Update deployment documentation

**Benefits:**
- Decoupled architecture
- Fleet management
- Easier testing
- Maintains security

---

## Testing Strategy

### Phase 1 Testing (Colocated)

**Approach:**
- Deploy admin panel on OpenSIPS server
- Test all Fail2Ban features
- Accept "pain" of remote testing limitations
- Focus on functionality validation

**Workarounds:**
- Use SSH tunnel for some remote testing scenarios
- Focus on unit/integration tests that don't require Fail2Ban
- Accept that full testing requires server deployment

### Phase 2 Testing (Remote)

**Approach:**
- Admin panel on separate server
- SSH connection to OpenSIPS server
- Test remote execution
- Validate fleet management

---

## Related Documentation

- [Fail2Ban Admin Panel Implementation Summary](ADMIN-PANEL-IMPLEMENTATION.md) - Current implementation details
- [Fail2Ban Remote Management Options](REMOTE-MANAGEMENT-OPTIONS.md) - Detailed architecture options
- [Fail2Ban Admin Panel Enhancement](ADMIN-PANEL-ENHANCEMENT.md) - Feature specifications

---

**Status:** Phase 1 complete, Phase 2 planned for future implementation
