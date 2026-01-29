# Workingdocs – Agent Context

**Purpose:** This folder gives the next agent enough context to pick up the project quickly. Read this first.

---

## Start here (next agent)

1. **Read [QUICK-START.md](QUICK-START.md)** – Current state, recent work, what to do next.
2. **If continuing recent work:** Read [SESSIONS/RECENT/SESSION-SUMMARY-FAIL2BAN-ADMIN-PANEL-FIX.md](SESSIONS/RECENT/SESSION-SUMMARY-FAIL2BAN-ADMIN-PANEL-FIX.md) – Last major session (Fail2ban admin panel).
3. **If working on OpenSIPS routing/NAT/usrloc:** Use [QUICK-REFERENCES/USRLOC-QUICK-REFERENCE.md](QUICK-REFERENCES/USRLOC-QUICK-REFERENCE.md) and [ARCHITECTURE/ARCHITECTURE-PROXY-REGISTRAR-NAT.md](ARCHITECTURE/ARCHITECTURE-PROXY-REGISTRAR-NAT.md).

---

## Layout

| Path | Contents |
|------|----------|
| **QUICK-START.md** | Current state, recent context, next steps. **Read first.** |
| **QUICK-REFERENCES/** | Usrloc quick reference, Snom troubleshooting. |
| **ARCHITECTURE/** | Proxy-registrar/NAT design, domain–dispatcher link, historical “simplified” approach. |
| **SESSIONS/RECENT/** | Latest session summaries (Fail2ban admin panel, env vars). |
| **SESSIONS/NAT-TRAVERSAL/** | NAT, received, OPTIONS/NOTIFY, INVITE/ACK fixes. |
| **SESSIONS/USRLOC-MIGRATION/** | Usrloc planning, save fix, lookup complete. |
| **SESSIONS/AUDIO-ROUTING/** | ACK/BYE, received URI, regex, force-RPORT. |
| **SESSIONS/OTHER/** | DB schema, accounting/CDR. |
| **INSTALLATION/** | Manual install steps, install review. |
| **VERIFICATION/** | CDR verification checklist and results. |

---

## Repos and main docs

- **pbx3sbc** – OpenSIPS SBC (this repo). Config: `config/opensips.cfg.template`.
- **pbx3sbc-admin** – Laravel/Filament admin panel (separate repo).
- **docs/** – User-facing and project docs (see [docs/index.md](../docs/index.md)).
- **config/fail2ban/** – Fail2ban filters and jail config.
- **OpenSIPS DB schema (all tables, all modules):** [https://opensips.org/html/docs/db/db-schema-3.2.x.html](https://opensips.org/html/docs/db/db-schema-3.2.x.html) — drouting, carrierroute, location, dispatcher, alias, acc, dialog, etc.

---

## After a session

- Add or update a session summary in **SESSIONS/RECENT/** (or the right topic subdir).
- Update **QUICK-START.md** with current state and next steps so the next agent can continue cleanly.
